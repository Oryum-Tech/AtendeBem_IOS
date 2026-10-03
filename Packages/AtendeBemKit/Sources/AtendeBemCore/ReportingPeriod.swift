import Foundation

/// Inclusive civil days sent to the existing report endpoints. Presets use UTC−03:00,
/// consistently with the agenda; the prescription service applies its clinic's own time zone.
public struct ReportingPeriod: Equatable, Hashable, Sendable, Identifiable {
    public let start: Date
    public let end: Date
    public var id: String { "\(ClinicClock.day(start))..\(ClinicClock.day(end))" }
    public var queryItems: [URLQueryItem] {
        [.init(name: "de", value: ClinicClock.day(start)), .init(name: "ate", value: ClinicClock.day(end))]
    }

    public init?(start: Date, end: Date) {
        let first = Self.calendar.startOfDay(for: start)
        let last = Self.calendar.startOfDay(for: end)
        guard first <= last else { return nil }
        self.start = first
        self.end = last
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ClinicClock.timeZone
        return calendar
    }

    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case today, week, month, previousMonth
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .today: "Hoje"
            case .week: "Esta semana"
            case .month: "Este mês"
            case .previousMonth: "Mês anterior"
            }
        }
    }

    public static func preset(_ preset: Preset, relativeTo date: Date = .now) -> ReportingPeriod {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: date)
        switch preset {
        case .today:
            return ReportingPeriod(start: today, end: today)!
        case .week:
            let week = AgendaWeek(containing: today)
            return ReportingPeriod(start: week.dates[0], end: week.dates[6])!
        case .month, .previousMonth:
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            let first = preset == .previousMonth ? calendar.date(byAdding: .month, value: -1, to: month)! : month
            let next = calendar.date(byAdding: .month, value: 1, to: first)!
            return ReportingPeriod(start: first, end: calendar.date(byAdding: .day, value: -1, to: next)!)!
        }
    }

    /// The interval endpoint labels consecutive seven-day buckets S1…Sn, starting
    /// at `de`, not at the calendar week's Monday. Longer ranges use month labels.
    public func weeklyBucket(label: String) -> ReportingPeriod? {
        guard label.first == "S", let number = Int(label.dropFirst()), (1...10).contains(number),
              label == "S\(number)",
              let days = Self.calendar.dateComponents([.day], from: start, to: end).day,
              days < 70,
              let first = Self.calendar.date(byAdding: .day, value: (number - 1) * 7, to: start), first <= end,
              let last = Self.calendar.date(byAdding: .day, value: 6, to: first) else { return nil }
        return ReportingPeriod(start: first, end: min(last, end))
    }
}

public struct ReportService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func agenda(period: ReportingPeriod) async throws -> AgendaStatistics {
        let context = await api.requestContextID()
        try await requireContext(context)
        let result: AgendaStatistics = try await api.get(["agendamentos", "stats"], query: period.queryItems)
        try await requireContext(context)
        guard result.mes == period.id else { throw APIError.invalidResponse }
        return result
    }

    public func prescriptions(period: ReportingPeriod) async throws -> PrescriptionStatistics {
        let context = await api.requestContextID()
        try await requireContext(context)
        let result: PrescriptionStatistics = try await api.get(["receitas", "stats"], query: period.queryItems)
        try await requireContext(context)
        guard result.mes == period.id else { throw APIError.invalidResponse }
        return result
    }

    private func requireContext(_ expected: UUID) async throws {
        try Task.checkCancellation()
        guard await api.requestContextID() == expected else { throw APIError.contextChanged }
    }
}
