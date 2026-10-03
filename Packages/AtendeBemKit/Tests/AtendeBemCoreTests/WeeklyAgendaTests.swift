import Foundation
import Testing
@testable import AtendeBemCore

private func weeklySession() throws -> StoredSession {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"fixture-access","refreshToken":"fixture-refresh","expiraEm":900}"#.utf8))
    return StoredSession(tokens: pair)
}

private func weeklyFixture(_ day: String, patients: [String] = ["fixture-patient"]) throws -> String {
    let values: [[String: Any]] = patients.enumerated().map { index, patient in
        ["id": "\(day)-\(index)", "pacienteId": patient, "profissionalId": "fixture-professional",
         "inicio": "\(day)T10:00:00-03:00", "duracaoMin": 30, "tipo": "consulta", "canal": "presencial", "status": "confirmed"]
    }
    return String(decoding: try JSONSerialization.data(withJSONObject: ["itens": values]), as: UTF8.self)
}

private func query(_ request: URLRequest, _ key: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == key }?.value
}

/// Holds the first batch so concurrency/cancellation assertions do not rely on response timing.
private actor WeeklyRequestGate {
    let target: Int
    private var arrived = 0
    private var active = 0
    private var maximum = 0
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    init(_ target: Int = 3) { self.target = target }
    func enter() async {
        arrived += 1
        active += 1
        maximum = max(maximum, active)
        if !released { await withCheckedContinuation { continuations.append($0) } }
    }
    func leave() { active -= 1 }
    func release() {
        released = true
        continuations.forEach { $0.resume() }
        continuations = []
    }
    func maximumActive() -> Int { maximum }
    func waitForBatch() async throws {
        for _ in 0..<200 {
            if arrived >= target { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw APIError.invalidResponse
    }
}

@Test func weeklyAgendaUsesMondayAndClinicDayAcrossMonthYearAndUTC() throws {
    let newYear = try #require(ClinicClock.parseInstant("2027-01-01T12:00:00Z"))
    #expect(AgendaWeek(containing: newYear).dayKeys == ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
    // Monday in UTC is still Sunday at the clinic, belonging to the preceding week.
    let utcMonday = try #require(ClinicClock.parseInstant("2026-03-02T01:00:00Z"))
    let week = AgendaWeek(containing: utcMonday)
    #expect(week.id == "2026-02-23")
    #expect(week.dayKeys.last == "2026-03-01")
    #expect(Set(week.dayKeys).count == 7)
}

@Test func weeklyAgendaBoundsConcurrencyAndDistinguishesUnavailableFromEmpty() async throws {
    let gate = WeeklyRequestGate()
    let week = AgendaWeek(containing: try #require(ClinicClock.parseInstant("2026-10-02T12:00:00Z")))
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/agendamentos")
        await gate.enter()
        await gate.leave()
        return query(request, "dia") == week.dayKeys[2] ? ("{}", 503) : (#"{"itens":[]}"#, 200)
    }
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: transport)
    _ = try await api.restoreSession()
    let task = Task { try await WeeklyAgendaService(api: api).load(week: week) }
    try await gate.waitForBatch()
    #expect(await transport.count("/v1/agendamentos") == 3)
    await gate.release()
    let result = try await task.value
    #expect(await gate.maximumActive() == 3)
    #expect(await transport.count("/v1/agendamentos") == 7)
    #expect(result.days.map(\.id) == week.dayKeys)
    #expect(result.unavailableDayCount == 1)
    #expect(result.days[2].appointments == nil)
    #expect(result.days[2].bookedMinutes == nil)
    #expect(result.days[0].appointments?.isEmpty == true)
    #expect(result.days[0].bookedMinutes == 0)
}

@Test func weeklyAgendaBatchesUniquePatientIDsAndRejectsUnrequestedNames() async throws {
    let week = AgendaWeek(containing: try #require(ClinicClock.parseInstant("2026-10-02T12:00:00Z")))
    let ids = (0..<101).map { "fixture-\($0)" }
    let transport = StubTransport { request in
        if request.url?.path == "/v1/agendamentos" {
            return (try weeklyFixture(try #require(query(request, "dia")), patients: ids), 200)
        }
        #expect(request.url?.path == "/v1/pacientes")
        #expect(query(request, "perPage") == "100")
        let requested = try #require(query(request, "ids")).split(separator: ",").map(String.init)
        #expect(requested.count <= 100)
        var names = requested.filter { $0 != "fixture-0" }.map { ["id": $0, "nome": "Paciente fictício"] }
        names.append(["id": "foreign-patient", "nome": "Não pertence ao lote"])
        return (String(decoding: try JSONSerialization.data(withJSONObject: ["total": names.count, "itens": names]), as: UTF8.self), 200)
    }
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: transport)
    _ = try await api.restoreSession()
    let result = try await WeeklyAgendaService(api: api).load(week: week)
    #expect(await transport.count("/v1/pacientes") == 2)
    #expect(result.appointmentCount == 707)
    #expect(result.patientNames.count == 100)
    #expect(result.patientNames["foreign-patient"] == nil)
    #expect(result.patientNames["fixture-0"] == nil)
    #expect(result.namesUnavailable)
}

@Test func weeklyAgendaNeverPresentsForbiddenDaysAsPartialSuccess() async throws {
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: StubTransport { _ in ("{}", 403) })
    _ = try await api.restoreSession()
    await #expect(throws: APIError.http(403)) {
        try await WeeklyAgendaService(api: api).load(week: AgendaWeek(containing: .now))
    }
}

@Test func weeklyAgendaDiscardsClinicSwitchDuringDayRequests() async throws {
    let gate = WeeklyRequestGate()
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: StubTransport { request in
        if request.url?.path == "/v1/auth/trocar-clinica" {
            return (#"{"accessToken":"other-access","refreshToken":"other-refresh","expiraEm":900}"#, 200)
        }
        await gate.enter()
        await gate.leave()
        return (#"{"itens":[]}"#, 200)
    })
    _ = try await api.restoreSession()
    let original = await api.requestContextID()
    let task = Task { try await WeeklyAgendaService(api: api).load(week: AgendaWeek(containing: .now)) }
    try await gate.waitForBatch()
    try await api.switchClinic(id: "fixture-other-clinic")
    #expect(await api.requestContextID() != original)
    await gate.release()
    await #expect(throws: APIError.contextChanged) { try await task.value }
}

@Test func weeklyAgendaDiscardsLogoutWhilePatientNamesAreLoading() async throws {
    let gate = WeeklyRequestGate(1)
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: StubTransport { request in
        if request.url?.path == "/v1/agendamentos" { return (try weeklyFixture(try #require(query(request, "dia"))), 200) }
        await gate.enter()
        await gate.leave()
        return (#"{"total":1,"itens":[{"id":"fixture-patient","nome":"Paciente fictício"}]}"#, 200)
    })
    _ = try await api.restoreSession()
    let task = Task { try await WeeklyAgendaService(api: api).load(week: AgendaWeek(containing: .now)) }
    try await gate.waitForBatch()
    try await api.logout()
    await gate.release()
    await #expect(throws: APIError.contextChanged) { try await task.value }
}

@Test func weeklyAgendaPropagatesCancellationWithoutReturningEmptyDays() async throws {
    let gate = WeeklyRequestGate()
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: StubTransport { _ in
        await gate.enter()
        await gate.leave()
        return (#"{"itens":[]}"#, 200)
    })
    _ = try await api.restoreSession()
    let task = Task { try await WeeklyAgendaService(api: api).load(week: AgendaWeek(containing: .now)) }
    try await gate.waitForBatch()
    task.cancel()
    await gate.release()
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func weeklyAgendaMarksMismatchedDayPayloadUnavailable() async throws {
    let week = AgendaWeek(containing: try #require(ClinicClock.parseInstant("2026-10-02T12:00:00Z")))
    let api = APIClient(storage: MemoryStorage(try weeklySession()), transport: StubTransport { _ in
        (try weeklyFixture("2026-01-01"), 200)
    })
    _ = try await api.restoreSession()
    let result = try await WeeklyAgendaService(api: api).load(week: week)
    #expect(result.unavailableDayCount == 7)
    #expect(result.patientNames.isEmpty)
}
