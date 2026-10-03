import Foundation

/// A chronological preview of one loaded clinic day, not a clinical queue or a total.
public struct TodayOverview: Sendable {
    public let isCurrentDay: Bool
    public let nextAppointment: Appointment?
    public let previewAppointments: [Appointment]
    public let hasMoreAppointments: Bool
    public let hasUnusableAppointments: Bool

    public init(appointments: [Appointment], loadedDay: String, now: Date, previewLimit: Int = 3) {
        isCurrentDay = loadedDay == ClinicClock.day(now)
        guard isCurrentDay else {
            nextAppointment = nil
            previewAppointments = []
            hasMoreAppointments = false
            hasUnusableAppointments = false
            return
        }

        let occurrences = Dictionary(grouping: appointments, by: \.id)
        let dated = appointments.compactMap { appointment -> (Appointment, Date)? in
            guard !appointment.id.isEmpty, !appointment.pacienteId.isEmpty, !appointment.profissionalId.isEmpty,
                  occurrences[appointment.id]?.count == 1,
                  let date = appointment.startDate, ClinicClock.day(date) == loadedDay else { return nil }
            return (appointment, date)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 < rhs.1
        }
        hasUnusableAppointments = dated.count != appointments.count
        // Arrived/in-progress appointments belong to the service-ordered queue.
        // A past appointment is not relabelled as the next patient's turn.
        let upcomingStates: Set<String> = ["scheduled", "pending", "confirmed"]
        let next = dated.first { $0.1 >= now && upcomingStates.contains($0.0.status) }?.0
        nextAppointment = next
        let remaining = dated.map(\.0).filter { $0.id != next?.id }
        previewAppointments = Array(remaining.prefix(max(0, previewLimit)))
        hasMoreAppointments = remaining.count > previewAppointments.count
    }
}
