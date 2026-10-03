import Foundation
import Testing
@testable import AtendeBemCore

private let operationalNow = ClinicClock.parseInstant("2026-10-03T09:00:00-03:00")!
private func operationUser(_ roles: [String] = ["recepcao"]) throws -> User {
    try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id": "professional-fiction", "nome": "Equipe fictícia", "email": "example@example.invalid", "papeis": roles]))
}
private func operationAppointmentData(status: String = "scheduled", requested: String? = nil, via: String? = nil, patient: String = "patient-fiction", professional: String = "professional-fiction", start: String = "2026-10-04T09:00:00-03:00") throws -> Data {
    var fields: [String: Any] = ["id": "appointment-fiction", "inicio": start, "duracaoMin": 30, "pacienteId": patient, "profissionalId": professional, "tipo": "consulta", "canal": "presencial", "status": status]
    fields["confirmacaoPedidaEm"] = requested; fields["confirmadoVia"] = via
    return try JSONSerialization.data(withJSONObject: fields)
}
private func operationAppointment(status: String = "scheduled", requested: String? = nil, via: String? = nil, start: String = "2026-10-04T09:00:00-03:00") throws -> Appointment {
    try JSONDecoder().decode(Appointment.self, from: operationAppointmentData(status: status, requested: requested, via: via, start: start))
}
private actor OperationalTransport: HTTPTransport {
    struct Step: Sendable {
        let method: String
        let suffix: String
        let data: Data
        var status = 200
        var lost = false
    }
    var steps: [Step]
    var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { Issue.record("Unexpected operational request"); throw APIError.invalidResponse }
        let next = steps.removeFirst()
        #expect(request.httpMethod == next.method); #expect(request.url!.path.hasSuffix(next.suffix))
        if next.lost { throw URLError(.networkConnectionLost) }
        return (next.data, HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!)
    }
    func writes() -> Int { requests.filter { $0.httpMethod == "POST" && !$0.url!.path.hasSuffix("/auth/refresh") }.count }
    func allRequests() -> [URLRequest] { requests }
}
private func operationAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: pair)), transport: transport)
    _ = try await api.restoreSession(); return api
}
@MainActor private func confirmation(_ transport: OperationalTransport, initial: Appointment? = nil, role: String = "recepcao") async throws -> AppointmentConfirmationWorkflow {
    let api = try await operationAPI(transport)
    return AppointmentConfirmationWorkflow(appointment: try initial ?? operationAppointment(), user: try operationUser([role]), api: api, context: await api.requestContextID(), now: { operationalNow })
}

@Test func confirmationStateNeverConvertsRequestOrSilenceToConfirmed() throws {
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(), now: operationalNow) == .notRequested)
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(requested: "2026-10-03T08:00:00-03:00"), now: operationalNow) == .awaiting)
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(requested: "2026-10-02T09:00:00-03:00"), now: operationalNow) == .noConfirmation)
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(requested: "invalid"), now: operationalNow) == .invalidRequestDate)
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(status: "waiting"), now: operationalNow) == nil)
}
@Test func confirmationOriginRemainsUnknownWhenNotExplicit() throws {
    for via in [nil, "legacy", ""] as [String?] {
        #expect(AppointmentConfirmationState.resolve(try operationAppointment(status: "confirmed", via: via)) == .unknownOrigin)
    }
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(status: "confirmed", via: "paciente")) == .patient)
    #expect(AppointmentConfirmationState.resolve(try operationAppointment(status: "confirmed", via: "equipe")) == .team)
}
@Test func confirmationRequestMirrorsTimeWindowAndLiteralRoles() throws {
    for role in User.careRoles + ["recepcao", "admin"] { #expect(AppointmentConfirmationState.canRequest(try operationAppointment(), user: try operationUser([role]), now: operationalNow)) }
    for role in ["gestor", "paciente", "contabilista"] { #expect(!AppointmentConfirmationState.canRequest(try operationAppointment(), user: try operationUser([role]), now: operationalNow)) }
    let user = try operationUser()
    #expect(!AppointmentConfirmationState.canRequest(try operationAppointment(start: "2026-10-03T09:00:00-03:00"), user: user, now: operationalNow))
    #expect(!AppointmentConfirmationState.canRequest(try operationAppointment(requested: "2026-10-02T21:00:01-03:00"), user: user, now: operationalNow))
    #expect(AppointmentConfirmationState.canRequest(try operationAppointment(requested: "2026-10-02T21:00:00-03:00"), user: user, now: operationalNow))
    #expect(!AppointmentConfirmationState.canRequest(try operationAppointment(requested: "unknown"), user: user, now: operationalNow))
}
@Test func queueScopeIsOwnForClinicalRolesUnlessAdministrativeRolePresent() throws {
    for role in User.careRoles {
        #expect(try OperationalAgendaPolicy.professionalID(user: operationUser([role]), selected: "colleague") == "professional-fiction")
    }
    for roles in [["recepcao"], ["gestor"], ["admin"], ["medico", "recepcao"]] {
        #expect(try OperationalAgendaPolicy.professionalID(user: operationUser(roles), selected: nil) == nil)
        #expect(try OperationalAgendaPolicy.professionalID(user: operationUser(roles), selected: "colleague") == "colleague")
    }
    #expect(throws: APIError.self) { try OperationalAgendaPolicy.professionalID(user: operationUser(["paciente"]), selected: nil) }
}
@Test @MainActor func confirmationPostOnlyAfterExplicitRequestAndReflectsRecordedNotDelivered() async throws {
    let current = try operationAppointmentData(), posted = try operationAppointmentData(requested: "2026-10-03T09:00:01-03:00")
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: current), .init(method: "POST", suffix: "/pedir-confirmacao", data: posted)])
    let model = try await confirmation(transport)
    #expect(await transport.allRequests().isEmpty)
    await model.request(); await model.request()
    #expect(model.outcome == .succeeded); #expect(model.appointment?.status == "scheduled")
    #expect(await transport.writes() == 1)
}
@Test @MainActor func confirmationLostResponseRequiresGetReconciliationAndNeverReplays() async throws {
    let current = try operationAppointmentData(), recorded = try operationAppointmentData(requested: "2026-10-03T09:00:01-03:00")
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: current), .init(method: "POST", suffix: "/pedir-confirmacao", data: Data(), lost: true), .init(method: "GET", suffix: "/appointment-fiction", data: recorded)])
    let model = try await confirmation(transport)
    await model.request(); #expect(model.outcome == .uncertain)
    await model.request(); #expect(await transport.writes() == 1)
    await model.reconcile(); #expect(model.outcome == .succeeded); #expect(model.appointment?.status == "scheduled")
    #expect(await transport.writes() == 1)
}
@Test @MainActor func confirmationUnchangedReadDoesNotUnlockAnotherWrite() async throws {
    let current = try operationAppointmentData()
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: current), .init(method: "POST", suffix: "/pedir-confirmacao", data: Data(), lost: true), .init(method: "GET", suffix: "/appointment-fiction", data: current)])
    let model = try await confirmation(transport); await model.request(); await model.reconcile(); await model.request()
    #expect(model.outcome == .uncertain); #expect(!model.canRequest); #expect(await transport.writes() == 1)
}
@Test @MainActor func confirmationPreflightChangedPatientOrProfessionalPreventsPost() async throws {
    for current in [try operationAppointmentData(patient: "other"), try operationAppointmentData(professional: "other")] {
        let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: current)])
        let model = try await confirmation(transport); await model.request()
        #expect(!model.canRequest); #expect(await transport.writes() == 0)
    }
}
@Test @MainActor func confirmationChangedTimeNeedsAnotherReviewAndGesture() async throws {
    let current = try operationAppointmentData(start: "2026-10-05T09:00:00-03:00")
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: current)])
    let model = try await confirmation(transport); await model.request()
    #expect(model.outcome == .ready); #expect(model.error != nil); #expect(model.appointment?.inicio == "2026-10-05T09:00:00-03:00"); #expect(await transport.writes() == 0)
}
@Test @MainActor func confirmationWrongPostIdentityStaysUncertainAndBlocked() async throws {
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: try operationAppointmentData()),
        .init(method: "POST", suffix: "/pedir-confirmacao", data: try operationAppointmentData(requested: "2026-10-03T09:00:01-03:00", patient: "other"))])
    let model = try await confirmation(transport); await model.request()
    #expect(model.outcome == .uncertain); #expect(!model.canRequest); #expect(model.appointment == nil)
}
@Test @MainActor func confirmationInvalidationAndContextChangePreventNetwork() async throws {
    let transport = OperationalTransport([]), api = try await operationAPI(transport)
    let model = AppointmentConfirmationWorkflow(appointment: try operationAppointment(), user: try operationUser(), api: api, context: await api.requestContextID(), now: { operationalNow })
    try await api.logout(); await model.request()
    #expect(!model.canRequest); #expect(await transport.allRequests().isEmpty)
    let another = try await confirmation(transport); another.invalidate(); await another.request()
    #expect(await transport.allRequests().isEmpty)
}

private func queueData(professional: String = "professional-fiction", day: String = "2026-10-03", duplicate: Bool = false) throws -> Data {
    let first: [String: Any] = ["agendamentoId": "late-first", "pacienteId": "p1", "profissionalId": professional, "posicao": 1, "inicio": "2026-10-03T10:00:00-03:00", "esperaMin": 3, "atrasoMin": -60, "chegadaEm": "2026-10-03T08:57:00-03:00", "autoCheckin": true, "liberacaoExcepcional": false]
    let second: [String: Any] = ["agendamentoId": duplicate ? "late-first" : "early-second", "pacienteId": "p2", "profissionalId": professional, "posicao": 2, "inicio": "2026-10-03T08:00:00-03:00", "esperaMin": 2, "atrasoMin": 60, "liberacaoExcepcional": true, "liberacaoMotivo": "Justificativa fictícia"]
    return try JSONSerialization.data(withJSONObject: ["dia": day, "geradoEm": "2026-10-03T09:00:00-03:00", "totalAguardando": 2, "emAtendimento": [], "itens": [first, second]])
}
@Test func queuePreservesServerOrderingPositionAndUnknownArrival() async throws {
    let transport = OperationalTransport([.init(method: "GET", suffix: "/fila", data: try queueData()), .init(method: "GET", suffix: "/pacientes", data: Data(#"{"total":2,"itens":[{"id":"p1","nome":"Fictício 1"},{"id":"p2","nome":"Fictício 2"}]}"#.utf8))])
    let api = try await operationAPI(transport)
    let snapshot = try await OperationalQueueService(api: api).load(day: "2026-10-03", user: operationUser(["medico"]), professionalID: "other", context: await api.requestContextID())
    #expect(snapshot.queue.itens.map(\.id) == ["late-first", "early-second"])
    #expect(snapshot.queue.itens.map(\.posicao) == [1, 2]); #expect(snapshot.queue.itens[1].chegadaEm == nil)
    #expect(snapshot.queue.itens[0].autoCheckin == true); #expect(snapshot.queue.itens[0].atrasoMin == -60)
    let request = try #require(await transport.allRequests().first)
    #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "profissionalId" })?.value == "professional-fiction")
}
@Test func queueRejectsWrongDayForeignProfessionalAndDuplicateIDsBeforePatientReads() async throws {
    for data in [try queueData(day: "2026-10-04"), try queueData(professional: "other"), try queueData(duplicate: true)] {
        let transport = OperationalTransport([.init(method: "GET", suffix: "/fila", data: data)]), api = try await operationAPI(transport)
        await #expect(throws: APIError.invalidResponse) { try await OperationalQueueService(api: api).load(day: "2026-10-03", user: operationUser(["medico"]), context: await api.requestContextID()) }
        #expect(await transport.allRequests().count == 1)
    }
}

@Test @MainActor func confirmationRevokedPermissionClearsReviewedAppointment() async throws {
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: Data(), status: 403)])
    let model = try await confirmation(transport); await model.request()
    #expect(model.appointment == nil); #expect(!model.canRequest); #expect(await transport.writes() == 0)
}

@Test @MainActor func confirmationRejected401OnlyRefreshesThroughReadAndNeverReplaysPost() async throws {
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: try operationAppointmentData()),
        .init(method: "POST", suffix: "/pedir-confirmacao", data: Data(), status: 401),
        .init(method: "GET", suffix: "/me", data: Data(#"{"id":"professional-fiction","nome":"Fictício","email":"fiction@example.invalid","papeis":["recepcao"]}"#.utf8))])
    let model = try await confirmation(transport); await model.request()
    #expect(model.outcome == .ready); #expect(await transport.writes() == 1); #expect(await transport.allRequests().count == 3)
}

private actor DelayedOperationalTransport: HTTPTransport {
    var continuation: CheckedContinuation<Void, Never>?
    var started = false
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        started = true
        await withCheckedContinuation { continuation = $0 }
        return (try operationAppointmentData(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func hasStarted() -> Bool { started }
    func complete() { continuation?.resume(); continuation = nil }
}
@Test @MainActor func confirmationLocalInvalidationDiscardsLateReadWithoutWriting() async throws {
    let transport = DelayedOperationalTransport(), api = try await operationAPI(transport)
    let model = AppointmentConfirmationWorkflow(appointment: try operationAppointment(), user: try operationUser(), api: api, context: await api.requestContextID(), now: { operationalNow })
    let task = Task { await model.request() }
    while !(await transport.hasStarted()) { await Task.yield() }
    model.invalidate(); await transport.complete(); await task.value
    #expect(model.appointment == nil); #expect(!model.canRequest)
}

@Test func appointmentActionRejectsReassignedPatientAndProfessionalBeforeWriting() async throws {
    let expected = try operationAppointment()
    for record in [try operationAppointmentData(patient: "other"), try operationAppointmentData(professional: "other")] {
        let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: record)]), api = try await operationAPI(transport)
        await #expect(throws: APIError.invalidResponse) {
            try await AppointmentService(api: api).perform(.confirm, id: expected.id, user: operationUser(), expectedAppointment: expected)
        }
        #expect(await transport.writes() == 0)
    }
}
@Test func appointmentActionRequiresExactScheduleReviewedWhenDialogOpened() async throws {
    let expected = try operationAppointment()
    for record in [try operationAppointmentData(start: "2026-10-05T09:00:00-03:00"), try operationAppointmentData(status: "pending")] {
        let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: record)]), api = try await operationAPI(transport)
        await #expect(throws: APIError.http(409)) {
            try await AppointmentService(api: api).perform(.confirm, id: expected.id, user: operationUser(), expectedAppointment: expected)
        }
        #expect(await transport.writes() == 0)
    }
}
@Test func appointmentActionRejectsMismatchedWriteResponse() async throws {
    let expected = try operationAppointment()
    let transport = OperationalTransport([.init(method: "GET", suffix: "/appointment-fiction", data: try operationAppointmentData()),
        .init(method: "POST", suffix: "/confirmar", data: try operationAppointmentData(status: "confirmed", patient: "other"))]), api = try await operationAPI(transport)
    await #expect(throws: APIError.invalidResponse) {
        try await AppointmentService(api: api).perform(.confirm, id: expected.id, user: operationUser(), expectedAppointment: expected)
    }
    #expect(await transport.writes() == 1)
}
