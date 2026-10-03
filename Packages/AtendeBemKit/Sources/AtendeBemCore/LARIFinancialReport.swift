import Foundation

public enum LARIFinancialPeriodResolution: Equatable, Sendable {
    case resolved(ReportingPeriod)
    case needsSelection
}

/// Only unambiguous civil months are inferred. Other requests remain editable selections.
public enum LARIFinancialPeriod {
    public static func resolve(command: String, relativeTo now: Date = .now) -> LARIFinancialPeriodResolution {
        let text = command.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let months = ["janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
        let named = months.enumerated().filter { !matches("\\b\($0.element)\\b", in: text).isEmpty }.map { $0.offset + 1 }
        let years = matches("\\b(?:19|20|21)[0-9]{2}\\b", in: text).compactMap(Int.init)
        let current = !matches("\\b(?:este|esse|neste|nesse) mes\\b", in: text).isEmpty
        let previous = !matches("\\b(?:mes (?:anterior|passado)|ultimo mes)\\b", in: text).isEmpty
        let thisYear = !matches("\\b(?:deste|desse|este|esse|neste|nesse) ano\\b", in: text).isEmpty
        // Comparisons, ranges and partial dates cannot become a whole month silently.
        guard matches("\\b(?:entre|ate|comparar|compare|comparado|versus|semana|semanas|trimestre|semestre|dias)\\b|\\b[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}\\b", in: text).isEmpty,
              matches("\\b[0-9]{1,2} (?:de )?(?:\(months.joined(separator: "|")))\\b", in: text).isEmpty,
              named.count <= 1, years.count <= 1, !(current && previous) else { return .needsSelection }
        if current || previous {
            guard named.isEmpty, years.isEmpty, !thisYear else { return .needsSelection }
            return .resolved(.preset(previous ? .previousMonth : .month, relativeTo: now))
        }
        if let month = named.first {
            guard !(thisYear && !years.isEmpty), matches("\\b[0-9]{1,2}\\b", in: text).isEmpty else { return .needsSelection }
            let year: Int?
            if thisYear { year = calendar.component(.year, from: now) } else { year = years.first }
            guard let year, let period = monthPeriod(month: month, year: year) else { return .needsSelection }
            return .resolved(period)
        }
        let numeric = matches("\\b(?:0?[1-9]|1[0-2])/(?:19|20|21)[0-9]{2}\\b", in: text)
        guard numeric.count == 1, !thisYear else { return .needsSelection }
        let pieces = numeric[0].split(separator: "/").compactMap { Int($0) }
        guard pieces.count == 2, let period = monthPeriod(month: pieces[0], year: pieces[1]) else { return .needsSelection }
        return .resolved(period)
    }

    public static func monthPeriod(month: Int, year: Int) -> ReportingPeriod? {
        guard (1...12).contains(month), (1900...2199).contains(year),
              let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let next = calendar.date(byAdding: .month, value: 1, to: first),
              let last = calendar.date(byAdding: .day, value: -1, to: next) else { return nil }
        return ReportingPeriod(start: first, end: last)
    }

    public static func label(_ period: ReportingPeriod) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR"); formatter.timeZone = ClinicClock.timeZone
        formatter.dateStyle = .long
        let first = formatter.string(from: period.start)
        return period.start == period.end ? first : "\(first) a \(formatter.string(from: period.end))"
    }

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = ClinicClock.timeZone; return value
    }
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

public struct LARIFinancialSummary: Decodable, Sendable {
    public let faturamento: Decimal
    public let recebido: Decimal
    public let aReceber: Decimal
    public let despesas: Decimal
    public let ticketMedio: Decimal
    public let inadimplencia: Decimal

    func validate() throws {
        guard [faturamento, recebido, aReceber, despesas, ticketMedio, inadimplencia].allSatisfy(finite) else { throw APIError.invalidResponse }
    }
}

public struct LARIFinancialLedger: Decodable, Sendable {
    public struct Amounts: Decodable, Sendable {
        public let receita: Decimal
        public let despesa: Decimal
        public let saldo: Decimal
    }
    public struct Day: Decodable, Sendable, Identifiable {
        public let data: String
        public let receita: Decimal
        public let despesa: Decimal
        public let saldo: Decimal
        public var id: String { data }
    }
    public let de: String
    public let ate: String
    public let moeda: String
    public let serie: [Day]
    public let totais: Amounts

    func validate(period: ReportingPeriod) throws {
        guard de == ClinicClock.day(period.start), ate == ClinicClock.day(period.end), moeda == "BRL",
              Set(serie.map(\.data)).count == serie.count,
              [totais.receita, totais.despesa, totais.saldo].allSatisfy(finite),
              approximatelyEqual(totais.receita - totais.despesa, totais.saldo) else { throw APIError.invalidResponse }
        let formatter = DateFormatter()
        formatter.calendar = LARIFinancialPeriod.calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ClinicClock.timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        for day in serie {
            guard let date = formatter.date(from: day.data), formatter.string(from: date) == day.data,
                  date >= period.start, date <= period.end,
                  [day.receita, day.despesa, day.saldo].allSatisfy(finite),
                  approximatelyEqual(day.receita - day.despesa, day.saldo) else { throw APIError.invalidResponse }
        }
        guard approximatelyEqual(serie.reduce(Decimal.zero) { $0 + $1.receita }, totais.receita),
              approximatelyEqual(serie.reduce(Decimal.zero) { $0 + $1.despesa }, totais.despesa) else { throw APIError.invalidResponse }
    }
}

private func finite(_ value: Decimal) -> Bool { !value.isNaN && NSDecimalNumber(decimal: value).doubleValue.isFinite }
private func approximatelyEqual(_ a: Decimal, _ b: Decimal) -> Bool { abs(a - b) <= Decimal(string: "0.01")! }

public struct LARIFinancialReport: Sendable {
    public let period: ReportingPeriod
    public let summary: LARIFinancialSummary?
    public let ledger: LARIFinancialLedger?
    public let unavailableSources: [String]
    public let consultedAt: Date
    public var isPartial: Bool { !unavailableSources.isEmpty }

    public static func money(_ amount: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .currency; formatter.currencyCode = "BRL"
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? NSDecimalNumber(decimal: amount).stringValue + " BRL"
    }
    public static func percentage(_ amount: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .percent; formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? NSDecimalNumber(decimal: amount * 100).stringValue + "%"
    }
    public func text(clinicName: String) -> String {
        var lines = ["Relatório financeiro — \(clinicName)", LARIFinancialPeriod.label(period)]
        if let summary {
            lines += ["Faturamento: \(Self.money(summary.faturamento))", "Recebido: \(Self.money(summary.recebido))",
                      "A receber: \(Self.money(summary.aReceber)) (\(Self.percentage(summary.inadimplencia)) do faturamento)",
                      "Despesas: \(Self.money(summary.despesas))", "Ticket médio recebido: \(Self.money(summary.ticketMedio))"]
        }
        if let ledger { lines += ["Saldo dos lançamentos do período: \(Self.money(ledger.totais.saldo))"] }
        lines += ["Valores dos lançamentos não cancelados; receitas e despesas podem incluir pendências. O saldo não representa caixa, saldo bancário ou lucro. O percentual a receber não identifica dívidas vencidas."]
        if isPartial { lines += ["Relatório parcial. Fontes indisponíveis: \(unavailableSources.joined(separator: ", ")). Nenhum valor ausente foi substituído por zero."] }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "pt_BR"); formatter.timeZone = ClinicClock.timeZone
        formatter.dateStyle = .short; formatter.timeStyle = .short
        lines += ["Consultado em \(formatter.string(from: consultedAt)) (UTC−03). Fontes: resumo financeiro e relatório de faturamento do AtendeBem, conforme disponibilidade. Síntese calculada no aplicativo; não enviada a um provedor de IA."]
        return lines.joined(separator: "\n\n")
    }
}

public enum LARIFinancialReportError: LocalizedError, Equatable {
    case permissionDenied, sourcesUnavailable
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Seu perfil nesta clínica não permite consultar o financeiro."
        case .sourcesUnavailable: "Não foi possível consultar as fontes financeiras. Nenhum valor foi calculado. Tente novamente."
        }
    }
}

public struct LARIFinancialReportService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }
    public static func isAllowed(_ user: User) -> Bool { user.canReadFinancialReports }

    public func load(period: ReportingPeriod, user: User, expectedContext: UUID) async throws -> LARIFinancialReport {
        guard Self.isAllowed(user) else { throw LARIFinancialReportError.permissionDenied }
        try await requireContext(expectedContext)
        var summary: LARIFinancialSummary?
        var ledger: LARIFinancialLedger?
        var missing: [String] = []
        do {
            let value: LARIFinancialSummary = try await api.get(["resumo"], query: period.queryItems)
            try await requireContext(expectedContext); try value.validate(); summary = value
        } catch {
            try await requireContext(expectedContext); try rejectFatal(error)
            missing.append("Resumo financeiro")
        }
        do {
            let value: LARIFinancialLedger = try await api.get(["relatorios", "faturamento"], query: period.queryItems + [.init(name: "formato", value: "json")])
            try await requireContext(expectedContext); try value.validate(period: period); ledger = value
        } catch {
            try await requireContext(expectedContext); try rejectFatal(error)
            missing.append("Relatório de faturamento")
        }
        try await requireContext(expectedContext)
        guard summary != nil || ledger != nil else { throw LARIFinancialReportError.sourcesUnavailable }
        return LARIFinancialReport(period: period, summary: summary, ledger: ledger, unavailableSources: missing, consultedAt: .now)
    }
    private func requireContext(_ context: UUID) async throws {
        try Task.checkCancellation()
        guard await api.requestContextID() == context else { throw APIError.contextChanged }
    }
    private func rejectFatal(_ error: Error) throws {
        if error is CancellationError { throw error }
        if let error = error as? APIError, [.http(401), .http(403), .sessionExpired, .contextChanged].contains(error) { throw error }
    }
}
