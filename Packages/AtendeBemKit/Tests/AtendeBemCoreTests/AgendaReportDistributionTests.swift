import Foundation
import Testing
@testable import AtendeBemCore

private func reportDistribution(total: Int, rows: [[String: Any]]) throws -> AgendaReportDistribution {
    let json: [String: Any] = ["mes": "2026-10-01..2026-10-31", "total": total,
        "concluidas": 0, "faltas": 0, "taxaFaltas": 0, "porSemana": rows]
    return AgendaReportDistribution(try JSONDecoder().decode(AgendaStatistics.self, from: JSONSerialization.data(withJSONObject: json)))
}

@Test func reportMissingSeriesNeverBecomesAZeroChart() throws {
    #expect(try reportDistribution(total: 7, rows: []).state == .unavailable)
    #expect(try reportDistribution(total: 0, rows: []).state == .unavailable)
    let zeros = try reportDistribution(total: 0, rows: [["rotulo": "S1", "total": 0], ["rotulo": "S2", "total": 0]])
    #expect(zeros.state == .empty)
    #expect(zeros.values.count == 2)
}

@Test func reportDistributionPreservesEveryReturnedInterval() throws {
    let result = try reportDistribution(total: 8, rows: [["rotulo": "S1", "total": 3], ["rotulo": "S2", "total": 0], ["rotulo": "S3", "total": 5]])
    #expect(result.state == .available)
    #expect(result.values.map(\.rotulo) == ["S1", "S2", "S3"])
    #expect(result.values.map(\.total) == [3, 0, 5])
}

@Test func reportDistributionRejectsInvalidOrContradictorySeriesWithoutEstimating() throws {
    let invalidRows: [[[String: Any]]] = [
        [["rotulo": "S1", "total": -1]],
        [["rotulo": "S1", "total": 1], ["rotulo": "S1", "total": 1]],
        [["rotulo": "", "total": 2]],
        [["rotulo": "S1", "total": 1]],
        [["rotulo": "S1", "total": Int.max], ["rotulo": "S2", "total": 1]]
    ]
    for rows in invalidRows {
        #expect(try reportDistribution(total: 2, rows: rows).state == .inconsistent)
    }
}
