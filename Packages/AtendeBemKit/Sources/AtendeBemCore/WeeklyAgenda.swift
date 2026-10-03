import Foundation

/// Calendar weeks always follow the agenda service's fixed UTC−03:00 day.
public struct AgendaWeek: Equatable, Sendable, Identifiable {
    public let dates: [Date]
    public var id: String { ClinicClock.day(dates[0]) }
    public var dayKeys: [String] { dates.map(ClinicClock.day) }

    public init(containing date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ClinicClock.timeZone
        let midnight = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: midnight) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: midnight)!
        dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
    }
}

public struct WeeklyAgendaDay: Sendable, Identifiable {
    public enum State: Sendable {
        case available([Appointment])
        case unavailable(String)
    }
    public let date: Date
    public let state: State
    public var id: String { ClinicClock.day(date) }
    public var appointments: [Appointment]? {
        guard case .available(let values) = state else { return nil }
        return values
    }
    /// Only booked/completed work contributes. Cancelled and no-show entries remain visible.
    public var bookedMinutes: Int? {
        appointments.map { $0.filter { !["cancelled", "no-show"].contains($0.status) }.reduce(0) { $0 + max(0, $1.duracaoMin) } }
    }
}

public struct WeeklyAgendaSnapshot: Sendable {
    public let week: AgendaWeek
    public let days: [WeeklyAgendaDay]
    public let patientNames: [String: String]
    public let namesUnavailable: Bool
    public var unavailableDayCount: Int { days.filter { $0.appointments == nil }.count }
    public var appointmentCount: Int { days.reduce(0) { $0 + ($1.appointments?.count ?? 0) } }
}

public struct WeeklyAgendaService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load(week: AgendaWeek) async throws -> WeeklyAgendaSnapshot {
        let context = await api.requestContextID()
        try await requireContext(context)
        let days = try await withThrowingTaskGroup(of: (Int, WeeklyAgendaDay).self) { group in
            // At most three day requests in flight; the public contract accepts a single day.
            var next = 0
            for _ in 0..<min(3, week.dates.count) {
                let index = next
                group.addTask { (index, try await loadDay(week.dates[index], context: context)) }
                next += 1
            }
            var results: [Int: WeeklyAgendaDay] = [:]
            while let (index, day) = try await group.next() {
                results[index] = day
                if next < week.dates.count {
                    let index = next
                    group.addTask { (index, try await loadDay(week.dates[index], context: context)) }
                    next += 1
                }
            }
            return (0..<week.dates.count).compactMap { results[$0] }
        }
        try await requireContext(context)
        let ids = Array(Set(days.flatMap { $0.appointments ?? [] }.map(\.pacienteId))).sorted()
        var names: [String: String] = [:]
        var namesUnavailable = false
        for offset in stride(from: 0, to: ids.count, by: 100) {
            try await requireContext(context)
            let batch = Array(ids[offset..<min(offset + 100, ids.count)])
            do {
                let page: PatientPage = try await api.get(["pacientes"], query: [
                    .init(name: "ids", value: batch.joined(separator: ",")),
                    .init(name: "perPage", value: "100"), .init(name: "page", value: "1")
                ])
                try await requireContext(context)
                let requested = Set(batch)
                for patient in page.itens where requested.contains(patient.id) { names[patient.id] = patient.nome }
                if page.truncado == true || page.itens.count < page.total || batch.contains(where: { names[$0] == nil }) {
                    namesUnavailable = true
                }
            } catch {
                try await requireContext(context)
                try propagateCritical(error)
                namesUnavailable = true
            }
        }
        try await requireContext(context)
        return WeeklyAgendaSnapshot(week: week, days: days, patientNames: names, namesUnavailable: namesUnavailable)
    }

    private func loadDay(_ date: Date, context: UUID) async throws -> WeeklyAgendaDay {
        try await requireContext(context)
        do {
            let key = ClinicClock.day(date)
            let page: AppointmentPage = try await api.get(["agendamentos"], query: [.init(name: "dia", value: key)])
            try await requireContext(context)
            // Do not assign an appointment to the wrong day if an endpoint returns an inconsistent payload.
            guard page.itens.allSatisfy({ $0.startDate.map { ClinicClock.day($0) == key } ?? true }),
                  Set(page.itens.map(\.id)).count == page.itens.count else { throw APIError.invalidResponse }
            let appointments = page.itens.sorted {
                let first = $0.startDate ?? .distantFuture, second = $1.startDate ?? .distantFuture
                return first == second ? $0.id < $1.id : first < second
            }
            return WeeklyAgendaDay(date: date, state: .available(appointments))
        } catch {
            try await requireContext(context)
            try propagateCritical(error)
            return WeeklyAgendaDay(date: date, state: .unavailable("Não foi possível carregar este dia. Atualize a semana para tentar novamente."))
        }
    }

    private func requireContext(_ expected: UUID) async throws {
        try Task.checkCancellation()
        guard await api.requestContextID() == expected else { throw APIError.contextChanged }
    }

    private func propagateCritical(_ error: Error) throws {
        if error is CancellationError { throw error }
        if let api = error as? APIError,
           [.sessionExpired, .contextChanged, .http(401), .http(403)].contains(api) { throw error }
        if let network = error as? URLError, network.code == .cancelled { throw CancellationError() }
    }
}
