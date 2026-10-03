import Foundation
import Testing
@testable import AtendeBemCore

private func financialDate(_ text: String) throws -> Date { try #require(ClinicClock.parseInstant(text)) }
private func financialUser(_ roles: [String] = ["gestor"]) throws -> User {
    let data = try JSONSerialization.data(withJSONObject: ["id": "financial-user-fixture", "nome": "Pessoa fictícia", "email": "fixture@example.invalid", "papeis": roles])
    return try JSONDecoder().decode(User.self, from: data)
}
private func financialAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"finance-fixture","refreshToken":"finance-refresh-fixture","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: pair)), transport: transport)
    _ = try await api.restoreSession(); return api
}
private let financialSummaryJSON = #"{"faturamento":100.30,"recebido":70.20,"aReceber":30.10,"despesas":25.10,"ticketMedio":35.10,"inadimplencia":0.300099700897308}"#
private let financialLedgerJSON = #"{"de":"2026-01-01","ate":"2026-01-31","moeda":"BRL","serie":[{"data":"2026-01-04","receita":100.30,"despesa":25.10,"saldo":75.20}],"totais":{"receita":100.30,"despesa":25.10,"saldo":75.20}}"#
private func januaryPeriod() throws -> ReportingPeriod { try #require(LARIFinancialPeriod.monthPeriod(month: 1, year: 2026)) }

@Test func lariFinancialResolvesNamedExplicitMonthsAndCurrentYear() throws {
    let now = try financialDate("2026-10-03T02:00:00Z")
    for command in ["me diga como foi o financeiro de janeiro desse ano", "financeiro de janeiro deste ano", "relatório de janeiro de 2026", "financeiro 01/2026"] {
        #expect(LARIFinancialPeriod.resolve(command: command, relativeTo: now) == .resolved(try januaryPeriod()))
    }
    #expect(LARIFinancialPeriod.resolve(command: "Financeiro de MARÇO de 2026", relativeTo: now) == .resolved(try #require(LARIFinancialPeriod.monthPeriod(month: 3, year: 2026))))
}

@Test func lariFinancialCurrentYearAndRelativeMonthsUseClinicTimezone() throws {
    let now = try financialDate("2027-01-01T01:30:00Z")
    #expect(LARIFinancialPeriod.resolve(command: "janeiro desse ano", relativeTo: now) == .resolved(try januaryPeriod()))
    #expect(LARIFinancialPeriod.resolve(command: "financeiro este mês", relativeTo: now) == .resolved(try #require(LARIFinancialPeriod.monthPeriod(month: 12, year: 2026))))
    #expect(LARIFinancialPeriod.resolve(command: "financeiro mês anterior", relativeTo: now) == .resolved(try #require(LARIFinancialPeriod.monthPeriod(month: 11, year: 2026))))
    let january = try financialDate("2027-01-31T12:00:00Z")
    #expect(LARIFinancialPeriod.resolve(command: "financeiro mês passado", relativeTo: january) == .resolved(try #require(LARIFinancialPeriod.monthPeriod(month: 12, year: 2026))))
}

@Test func lariFinancialPeriodHandlesMonthLengthsLeapYearsAndInvalidMonth() throws {
    #expect(LARIFinancialPeriod.monthPeriod(month: 2, year: 2028)?.id == "2028-02-01..2028-02-29")
    #expect(LARIFinancialPeriod.monthPeriod(month: 2, year: 2027)?.id == "2027-02-01..2027-02-28")
    #expect(LARIFinancialPeriod.monthPeriod(month: 4, year: 2026)?.id == "2026-04-01..2026-04-30")
    #expect(LARIFinancialPeriod.monthPeriod(month: 1, year: 2026)?.id == "2026-01-01..2026-01-31")
    #expect(LARIFinancialPeriod.monthPeriod(month: 13, year: 2026) == nil)
    #expect(LARIFinancialPeriod.monthPeriod(month: 1, year: 0) == nil)
}

@Test func lariFinancialAmbiguousOrPartialIntervalsRequireSelection() {
    for command in ["financeiro janeiro", "financeiro", "janeiro ou fevereiro de 2026", "entre janeiro e março de 2026", "janeiro 2025 e 2026", "janeiro deste ano 2026", "janeiro de 2026 até 15", "financeiro de 15 de janeiro 2026", "01/01/2026", "este mês e mês anterior", "janeiro 2026 comparado com fevereiro 2026"] {
        #expect(LARIFinancialPeriod.resolve(command: command) == .needsSelection, "Do not silently widen or guess: \(command)")
    }
}

@Test func lariFinancialServiceUsesReadOnlyInclusiveRoutesAndExactDecimals() async throws {
    let period = try januaryPeriod()
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        if request.url?.path == "/v1/resumo" { #expect(query == period.queryItems); return (financialSummaryJSON, 200) }
        #expect(request.url?.path == "/v1/relatorios/faturamento")
        #expect(query == period.queryItems + [.init(name: "formato", value: "json")])
        return (financialLedgerJSON, 200)
    }
    let api = try await financialAPI(transport)
    let value = try await LARIFinancialReportService(api: api).load(period: period, user: financialUser(), expectedContext: await api.requestContextID())
    #expect(value.summary?.faturamento == Decimal(string: "100.30"))
    #expect(value.ledger?.totais.saldo == Decimal(string: "75.20"))
    #expect(!value.isPartial)
    #expect(await transport.all().count == 2)
}

@Test func lariFinancialPermissionsAreLiteralAndDenyBeforeNetwork() async throws {
    for role in ["gestor", "admin", "contabilista"] { #expect(LARIFinancialReportService.isAllowed(try financialUser([role]))) }
    let transport = StubTransport { _ in Issue.record("Denied profile must not query finance"); return ("{}", 500) }
    let api = try await financialAPI(transport)
    for role in ["medico", "dentista", "recepcao", "enfermeiro", "Gestor", "unknown"] {
        await #expect(throws: LARIFinancialReportError.permissionDenied) {
            try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser([role]), expectedContext: await api.requestContextID())
        }
    }
    #expect(await transport.all().isEmpty)
}

@Test func lariFinancialSummaryFailurePreservesLedgerWithoutFabricatedZero() async throws {
    let api = try await financialAPI(StubTransport { request in request.url?.path == "/v1/resumo" ? ("{}", 503) : (financialLedgerJSON, 200) })
    let report = try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: await api.requestContextID())
    #expect(report.summary == nil)
    #expect(report.ledger != nil)
    #expect(report.unavailableSources == ["Resumo financeiro"])
    #expect(!report.text(clinicName: "Clínica fictícia").contains("Recebido:"))
    #expect(report.text(clinicName: "Clínica fictícia").contains("Relatório parcial"))
}

@Test func lariFinancialLedgerFailurePreservesSummaryWithoutInventedBalance() async throws {
    let api = try await financialAPI(StubTransport { request in request.url?.path == "/v1/resumo" ? (financialSummaryJSON, 200) : ("{}", 503) })
    let report = try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: await api.requestContextID())
    #expect(report.summary != nil)
    #expect(report.ledger == nil)
    #expect(report.unavailableSources == ["Relatório de faturamento"])
    #expect(!report.text(clinicName: "Fictícia").contains("Saldo dos lançamentos do período:"))
}

@Test func lariFinancialBothFailuresDoNotProduceAReport() async throws {
    let api = try await financialAPI(StubTransport { _ in ("{}", 503) })
    await #expect(throws: LARIFinancialReportError.sourcesUnavailable) {
        try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: await api.requestContextID())
    }
}

@Test func lariFinancialPermissionLossDiscardsPreviouslyReadSummary() async throws {
    let api = try await financialAPI(StubTransport { request in request.url?.path == "/v1/resumo" ? (financialSummaryJSON, 200) : ("{}", 403) })
    await #expect(throws: APIError.http(403)) {
        try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: await api.requestContextID())
    }
}

@Test func lariFinancialLedgerRejectsWrongPeriodCurrencyDatesAndInconsistentTotals() throws {
    for fixture in [
        financialLedgerJSON.replacingOccurrences(of: "2026-01-31", with: "2026-02-28"),
        financialLedgerJSON.replacingOccurrences(of: "BRL", with: "USD"),
        financialLedgerJSON.replacingOccurrences(of: "2026-01-04", with: "2026-02-01"),
        financialLedgerJSON.replacingOccurrences(of: "2026-01-04", with: "2026-01-32"),
        financialLedgerJSON.replacingOccurrences(of: "2026-01-04", with: "2026-1-4"),
        financialLedgerJSON.replacingOccurrences(of: "75.20", with: "99.20"),
        financialLedgerJSON.replacingOccurrences(of: #""totais":{"receita":100.30"#, with: #""totais":{"receita":200.30"#)
    ] {
        let ledger = try JSONDecoder().decode(LARIFinancialLedger.self, from: Data(fixture.utf8))
        #expect(throws: APIError.invalidResponse) { try ledger.validate(period: januaryPeriod()) }
    }
}

@Test func lariFinancialLedgerRejectsDuplicateDaysAndAllowsEmptyRealZero() throws {
    let empty = #"{"de":"2026-01-01","ate":"2026-01-31","moeda":"BRL","serie":[],"totais":{"receita":0,"despesa":0,"saldo":0}}"#
    try JSONDecoder().decode(LARIFinancialLedger.self, from: Data(empty.utf8)).validate(period: januaryPeriod())
    let day = #"{"data":"2026-01-04","receita":0,"despesa":0,"saldo":0}"#
    let duplicated = empty.replacingOccurrences(of: "[]", with: "[\(day),\(day)]")
    let ledger = try JSONDecoder().decode(LARIFinancialLedger.self, from: Data(duplicated.utf8))
    #expect(throws: APIError.invalidResponse) { try ledger.validate(period: januaryPeriod()) }
}

@Test func lariFinancialRejectsNonFiniteSummaryAndOverflowingResponse() async throws {
    let summary = LARIFinancialSummary(faturamento: .nan, recebido: 1, aReceber: 0, despesas: 0, ticketMedio: 1, inadimplencia: 0)
    #expect(throws: APIError.invalidResponse) { try summary.validate() }
    let invalid = financialSummaryJSON.replacingOccurrences(of: "100.30", with: "1e999")
    let api = try await financialAPI(StubTransport { request in request.url?.path == "/v1/resumo" ? (invalid, 200) : (financialLedgerJSON, 200) })
    let report = try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: await api.requestContextID())
    #expect(report.summary == nil)
    #expect(report.isPartial)
}

@Test func lariFinancialOldContextDeniedBeforeAnyRead() async throws {
    let transport = StubTransport { _ in Issue.record("Old context must not read"); return ("{}", 500) }
    let api = try await financialAPI(transport)
    let old = await api.requestContextID(); try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: old)
    }
    #expect(await transport.all().isEmpty)
}

@Test func lariFinancialLateResponseAfterClinicChangeIsDiscarded() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { request in
        if request.url?.path == "/v1/auth/trocar-clinica" { return (#"{"accessToken":"next-finance","refreshToken":"next-refresh","expiraEm":900}"#, 200) }
        await gate.suspend(); return (financialSummaryJSON, 200)
    }
    let api = try await financialAPI(transport)
    let context = await api.requestContextID()
    let task = Task { try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: context) }
    try await gate.waitForRequest(); try await api.switchClinic(id: "next-clinic-fixture"); await gate.resume()
    await #expect(throws: APIError.contextChanged) { try await task.value }
    #expect(await transport.count("/v1/relatorios/faturamento") == 0)
}

@Test func lariFinancialCancelledReadDoesNotContinueToNextSource() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { _ in await gate.suspend(); return (financialSummaryJSON, 200) }
    let api = try await financialAPI(transport)
    let context = await api.requestContextID()
    let task = Task { try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: context) }
    try await gate.waitForRequest(); task.cancel(); await gate.resume()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await transport.count("/v1/relatorios/faturamento") == 0)
}

@Test func lariFinancialShareTextStatesMeaningAndDoesNotCallPendenciesOverdue() async throws {
    let api = try await financialAPI(StubTransport { request in request.url?.path == "/v1/resumo" ? (financialSummaryJSON, 200) : (financialLedgerJSON, 200) })
    let report = try await LARIFinancialReportService(api: api).load(period: januaryPeriod(), user: financialUser(), expectedContext: await api.requestContextID())
    let text = report.text(clinicName: "Clínica fictícia")
    #expect(text.contains("Clínica fictícia"))
    #expect(text.contains("não identifica dívidas vencidas"))
    #expect(text.contains("não representa caixa, saldo bancário ou lucro"))
    #expect(text.contains("não enviada a um provedor de IA"))
    #expect(!text.contains("Inadimplência:"))
}
