import Foundation
import Testing
@testable import AtendeBemCore

private func homeAppointment(_ id: String, at instant: String, status: String = "confirmed",
                             patientID: String = "fictional-patient") throws -> Appointment {
    let data = try JSONSerialization.data(withJSONObject: [
        "id": id, "inicio": instant, "duracaoMin": 30, "pacienteId": patientID,
        "profissionalId": "fictional-professional", "tipo": "consulta", "canal": "presencial", "status": status
    ])
    return try JSONDecoder().decode(Appointment.self, from: data)
}

@Test func homeNextAppointmentUsesChronologyWithoutReplacingServiceQueue() throws {
    let now = try #require(ClinicClock.parseInstant("2026-10-03T09:00:00-03:00"))
    let values = try [
        homeAppointment("late", at: "2026-10-03T08:30:00-03:00"),
        homeAppointment("waiting", at: "2026-10-03T09:05:00-03:00", status: "waiting"),
        homeAppointment("attending", at: "2026-10-03T09:10:00-03:00", status: "in-progress"),
        homeAppointment("later", at: "2026-10-03T11:00:00-03:00"),
        homeAppointment("next", at: "2026-10-03T10:00:00-03:00", status: "pending")
    ]
    let result = TodayOverview(appointments: values, loadedDay: "2026-10-03", now: now)
    #expect(result.nextAppointment?.id == "next")
    #expect(result.previewAppointments.map(\.id) == ["late", "waiting", "attending"])
    #expect(result.hasMoreAppointments)
    #expect(!result.hasUnusableAppointments)
}

@Test func homeNeverSuggestsCancelledCompletedAbsentOrUnknownStatusAsNext() throws {
    let now = try #require(ClinicClock.parseInstant("2026-10-03T09:00:00-03:00"))
    let values = try ["cancelled", "completed", "no-show", "future-server-state"].map {
        try homeAppointment($0, at: "2026-10-03T10:00:00-03:00", status: $0)
    }
    let result = TodayOverview(appointments: values, loadedDay: "2026-10-03", now: now, previewLimit: 10)
    #expect(result.nextAppointment == nil)
    #expect(Set(result.previewAppointments.map(\.status)) == Set(values.map(\.status)))
}

@Test func homeDropsYesterdayAtClinicMidnightIncludingUTCOffset() throws {
    let appointment = try homeAppointment("today", at: "2026-10-03T02:50:00Z")
    let before = try #require(ClinicClock.parseInstant("2026-10-03T02:45:00Z"))
    let after = try #require(ClinicClock.parseInstant("2026-10-03T03:00:00Z"))
    let stillToday = TodayOverview(appointments: [appointment], loadedDay: "2026-10-02", now: before)
    #expect(stillToday.isCurrentDay)
    #expect(stillToday.nextAppointment?.id == "today")
    let yesterday = TodayOverview(appointments: [appointment], loadedDay: "2026-10-02", now: after)
    #expect(!yesterday.isCurrentDay)
    #expect(yesterday.nextAppointment == nil)
    #expect(yesterday.previewAppointments.isEmpty)
    #expect(!yesterday.hasMoreAppointments)
}

@Test func homeMarksInvalidDatesWrongDaysAndAmbiguousIdentityAsUnusable() throws {
    let now = try #require(ClinicClock.parseInstant("2026-10-03T09:00:00-03:00"))
    let values = try [
        homeAppointment("wrong-day", at: "2026-10-04T10:00:00-03:00"),
        homeAppointment("invalid", at: "not-a-date"),
        homeAppointment("duplicate", at: "2026-10-03T10:00:00-03:00"),
        homeAppointment("duplicate", at: "2026-10-03T11:00:00-03:00", patientID: "different-fictional-patient"),
        homeAppointment("missing-patient", at: "2026-10-03T10:00:00-03:00", patientID: ""),
        homeAppointment("valid", at: "2026-10-03T12:00:00-03:00")
    ]
    let result = TodayOverview(appointments: values, loadedDay: "2026-10-03", now: now)
    #expect(result.hasUnusableAppointments)
    #expect(result.nextAppointment?.id == "valid")
    #expect(result.previewAppointments.isEmpty)
}

@Test func homeDoesNotRepeatFocusedAppointmentAndLimitsOnlyThePreview() throws {
    let now = try #require(ClinicClock.parseInstant("2026-10-03T09:00:00-03:00"))
    let values = try [
        homeAppointment("b", at: "2026-10-03T10:00:00-03:00"),
        homeAppointment("a", at: "2026-10-03T10:00:00-03:00"),
        homeAppointment("c", at: "2026-10-03T11:00:00-03:00")
    ]
    let result = TodayOverview(appointments: values, loadedDay: "2026-10-03", now: now, previewLimit: 1)
    #expect(result.nextAppointment?.id == "a")
    #expect(result.previewAppointments.map(\.id) == ["b"])
    #expect(result.hasMoreAppointments)
    let emptyPreview = TodayOverview(appointments: values, loadedDay: "2026-10-03", now: now, previewLimit: -1)
    #expect(emptyPreview.previewAppointments.isEmpty)
    #expect(emptyPreview.hasMoreAppointments)
    #expect(emptyPreview.nextAppointment?.id == "a")
}

@Test func homeEmptyLoadedDayHasNoInventedAppointmentOrPartialFlag() throws {
    let now = try #require(ClinicClock.parseInstant("2026-10-03T09:00:00-03:00"))
    let result = TodayOverview(appointments: [], loadedDay: "2026-10-03", now: now)
    #expect(result.isCurrentDay)
    #expect(result.nextAppointment == nil)
    #expect(result.previewAppointments.isEmpty)
    #expect(!result.hasMoreAppointments)
    #expect(!result.hasUnusableAppointments)
}
