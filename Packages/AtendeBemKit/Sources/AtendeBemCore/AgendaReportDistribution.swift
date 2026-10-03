import Foundation

/// Describes only the series returned by the agenda service; missing buckets are never filled locally.
public struct AgendaReportDistribution: Sendable {
    public enum State: Equatable, Sendable { case available, empty, unavailable, inconsistent }
    public let state: State
    public let values: [AgendaStatistics.Week]

    public init(_ statistics: AgendaStatistics) {
        values = statistics.porSemana
        guard !values.isEmpty else { state = .unavailable; return }
        var sum = 0
        var labels = Set<String>()
        for value in values {
            let label = value.rotulo.trimmingCharacters(in: .whitespacesAndNewlines)
            let addition = sum.addingReportingOverflow(value.total)
            guard value.total >= 0, !label.isEmpty, labels.insert(label).inserted,
                  !addition.overflow else { state = .inconsistent; return }
            sum = addition.partialValue
        }
        guard statistics.total >= 0, sum == statistics.total else { state = .inconsistent; return }
        state = sum == 0 ? .empty : .available
    }
}
