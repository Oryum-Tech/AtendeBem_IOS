import Foundation
import Testing
@testable import AtendeBemCore

private func reportDate(_ value: String) throws -> Date {
    try #require(ClinicClock.parseInstant(value))
}

@Test func reportPresetsUseClinicDayAtUTCMonthBoundary() throws {
    let date = try reportDate("2027-01-01T01:30:00Z")
    #expect(ReportingPeriod.preset(.today, relativeTo: date).id == "2026-12-31..2026-12-31")
    #expect(ReportingPeriod.preset(.month, relativeTo: date).id == "2026-12-01..2026-12-31")
    #expect(ReportingPeriod.preset(.previousMonth, relativeTo: date).id == "2026-11-01..2026-11-30")
}

@Test func reportWeeksRunMondayThroughSundayAcrossYears() throws {
    let friday = try reportDate("2027-01-01T12:00:00Z")
    #expect(ReportingPeriod.preset(.week, relativeTo: friday).id == "2026-12-28..2027-01-03")
    let utcMondayStillLocalSunday = try reportDate("2026-03-02T01:00:00Z")
    #expect(ReportingPeriod.preset(.week, relativeTo: utcMondayStillLocalSunday).id == "2026-02-23..2026-03-01")
}

@Test func reportMonthsHandleLeapYearsAndJanuaryRollover() throws {
    let leapMarch = try reportDate("2028-03-31T12:00:00Z")
    #expect(ReportingPeriod.preset(.previousMonth, relativeTo: leapMarch).id == "2028-02-01..2028-02-29")
    let ordinaryMarch = try reportDate("2027-03-31T12:00:00Z")
    #expect(ReportingPeriod.preset(.previousMonth, relativeTo: ordinaryMarch).id == "2027-02-01..2027-02-28")
    let january = try reportDate("2027-01-31T12:00:00Z")
    #expect(ReportingPeriod.preset(.previousMonth, relativeTo: january).id == "2026-12-01..2026-12-31")
}

@Test func reportCustomPeriodNormalizesCivilDaysAndRejectsReversedRange() throws {
    let early = try reportDate("2026-10-02T03:05:00Z")
    let late = try reportDate("2026-10-03T02:59:00Z")
    let sameDay = try #require(ReportingPeriod(start: late, end: early))
    #expect(sameDay.id == "2026-10-02..2026-10-02")
    #expect(sameDay.start == sameDay.end)
    #expect(ReportingPeriod(start: try reportDate("2026-10-03T03:00:00Z"), end: early) == nil)
    #expect(sameDay.queryItems == [URLQueryItem(name: "de", value: "2026-10-02"), URLQueryItem(name: "ate", value: "2026-10-02")])
}

@Test func reportWeeklyBucketLabelsFollowRangeStartAndClipLastDay() throws {
    let period = try #require(ReportingPeriod(start: try reportDate("2026-09-30T12:00:00Z"), end: try reportDate("2026-10-08T12:00:00Z")))
    #expect(period.weeklyBucket(label: "S1")?.id == "2026-09-30..2026-10-06")
    #expect(period.weeklyBucket(label: "S2")?.id == "2026-10-07..2026-10-08")
    #expect(period.weeklyBucket(label: "S3") == nil)
    #expect(period.weeklyBucket(label: "S0") == nil)
    #expect(period.weeklyBucket(label: "S01") == nil)
    #expect(period.weeklyBucket(label: "2026-10") == nil)
    let longPeriod = try #require(ReportingPeriod(start: period.start, end: try reportDate("2026-12-31T12:00:00Z")))
    #expect(longPeriod.weeklyBucket(label: "S1") == nil)
}

private let reportAgendaFixture = #"{"mes":"2026-10-02..2026-10-02","total":7,"concluidas":4,"faltas":1,"taxaFaltas":0.14285714285714285,"porSemana":[{"rotulo":"S1","total":7}]}"#
private let reportPrescriptionFixture = #"{"mes":"2026-10-02..2026-10-02","total":6,"emitidas":3,"rascunhos":2,"canceladas":1}"#

private func reportingAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"fixture-access","refreshToken":"fixture-refresh","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: pair)), transport: transport)
    _ = try await api.restoreSession()
    return api
}

@Test func reportServiceSendsInclusiveDatesAndKeepsExactServerIndicators() async throws {
    let period = ReportingPeriod.preset(.today, relativeTo: try reportDate("2026-10-02T12:00:00Z"))
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == period.queryItems)
        return (request.url?.path == "/v1/agendamentos/stats" ? reportAgendaFixture : reportPrescriptionFixture, 200)
    }
    let service = ReportService(api: try await reportingAPI(transport))
    let agenda = try await service.agenda(period: period)
    let prescriptions = try await service.prescriptions(period: period)
    #expect(agenda.total == 7)
    #expect(agenda.taxaFaltas == 0.14285714285714285)
    #expect(agenda.porSemana[0].total == 7)
    #expect(prescriptions.total == 6)
    #expect(prescriptions.emitidas == 3)
    #expect(await transport.count("/v1/agendamentos/stats") == 1)
    #expect(await transport.count("/v1/receitas/stats") == 1)
}

@Test func reportServiceRejectsResponseForAnotherPeriodForBothSources() async throws {
    let period = ReportingPeriod.preset(.today, relativeTo: try reportDate("2026-10-03T12:00:00Z"))
    let service = ReportService(api: try await reportingAPI(StubTransport { request in
        (request.url?.path == "/v1/agendamentos/stats" ? reportAgendaFixture : reportPrescriptionFixture, 200)
    }))
    await #expect(throws: APIError.invalidResponse) { try await service.agenda(period: period) }
    await #expect(throws: APIError.invalidResponse) { try await service.prescriptions(period: period) }
}

@Test func reportPrescriptionSourceRemainsAvailableWhenAgendaFails() async throws {
    let period = ReportingPeriod.preset(.today, relativeTo: try reportDate("2026-10-02T12:00:00Z"))
    let service = ReportService(api: try await reportingAPI(StubTransport { request in
        if request.url?.path == "/v1/agendamentos/stats" { return ("{}", 503) }
        return (reportPrescriptionFixture, 200)
    }))
    await #expect(throws: APIError.http(503)) { try await service.agenda(period: period) }
    #expect(try await service.prescriptions(period: period).total == 6)
}

@Test func reportServiceDiscardsResultsAfterClinicSwitch() async throws {
    let gate = ResponseGate()
    let period = ReportingPeriod.preset(.today, relativeTo: try reportDate("2026-10-02T12:00:00Z"))
    let api = try await reportingAPI(StubTransport { request in
        if request.url?.path == "/v1/auth/trocar-clinica" {
            return (#"{"accessToken":"fixture-next","refreshToken":"fixture-next-refresh","expiraEm":900}"#, 200)
        }
        await gate.suspend()
        return (reportAgendaFixture, 200)
    })
    let task = Task { try await ReportService(api: api).agenda(period: period) }
    try await gate.waitForRequest()
    try await api.switchClinic(id: "fixture-next-clinic")
    await gate.resume()
    await #expect(throws: APIError.contextChanged) { try await task.value }
}

@Test func reportServiceDiscardsCancelledPrescriptionLoad() async throws {
    let gate = ResponseGate()
    let period = ReportingPeriod.preset(.today, relativeTo: try reportDate("2026-10-02T12:00:00Z"))
    let api = try await reportingAPI(StubTransport { _ in
        await gate.suspend()
        return (reportPrescriptionFixture, 200)
    })
    let task = Task { try await ReportService(api: api).prescriptions(period: period) }
    try await gate.waitForRequest()
    task.cancel()
    await gate.resume()
    await #expect(throws: CancellationError.self) { try await task.value }
}
