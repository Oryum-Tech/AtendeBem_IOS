import AtendeBemCore
import SwiftUI

/// Sections inside Agenda's existing List; no extra tab or horizontal miniature calendar.
struct WeeklyAgendaSections: View {
    let snapshot: WeeklyAgendaSnapshot
    let selectedDay: String
    let search: String
    let typeCatalog: AppointmentTypeCatalog?
    let openDay: (Date) -> Void
    @State private var expandedDays: Set<String> = []

    var body: some View {
        Section {
            Text("\(snapshot.appointmentCount) agendamentos na semana").font(.headline)
            if snapshot.unavailableDayCount > 0 {
                Label("Resumo parcial: \(snapshot.unavailableDayCount) dia(s) indisponível(is).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if snapshot.namesUnavailable {
                Label("Alguns nomes não puderam ser atualizados.", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        } footer: {
            Text("Segunda a domingo, em UTC−03:00. Atualize para buscar alterações. A duração soma os agendamentos, sem descontar sobreposições; não representa horários disponíveis.")
        }
        ForEach(snapshot.days) { day in
            Section {
                switch day.state {
                case .unavailable(let explanation):
                    Label("Dia indisponível", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(explanation).foregroundStyle(.secondary)
                case .available(let appointments):
                    daySummary(day, appointments: appointments)
                    let matches = filtered(appointments)
                    if appointments.isEmpty {
                        Text("Sem agendamentos cadastrados").foregroundStyle(.secondary)
                    } else if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if matches.isEmpty { Text("Nenhum resultado neste dia").foregroundStyle(.secondary) }
                        ForEach(matches) { appointment in appointmentLink(appointment) }
                    } else {
                        DisclosureGroup(isExpanded: Binding(get: { expandedDays.contains(day.id) }, set: { value in
                            if value { expandedDays.insert(day.id) } else { expandedDays.remove(day.id) }
                        })) {
                            ForEach(appointments) { appointment in appointmentLink(appointment) }
                        } label: {
                            Text("Ver \(appointments.count) agendamentos").frame(minHeight: 44)
                        }.accessibilityIdentifier("agenda.week.expand.\(day.id)")
                    }
                }
                Button { openDay(day.date) } label: { Label("Abrir este dia", systemImage: "calendar.day.timeline.left") }
                    .frame(minHeight: 44).buttonStyle(.borderless)
                    .accessibilityLabel("Abrir \(dateLabel(day.date)) na visão diária")
                    .accessibilityIdentifier("agenda.week.day.\(day.id)")
            } header: {
                Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .environment(\.timeZone, ClinicClock.timeZone)
            }
        }
        .onAppear { expandedDays.insert(selectedDay) }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = ClinicClock.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func daySummary(_ day: WeeklyAgendaDay, appointments: [Appointment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(appointments.count) agendamentos").font(.headline)
            if let minutes = day.bookedMinutes, minutes > 0 {
                Text("\(minutes / 60) h \(minutes % 60) min de duração total").font(.subheadline).foregroundStyle(.secondary)
            }
            let cancelled = appointments.filter { ["cancelled", "no-show"].contains($0.status) }.count
            if cancelled > 0 { Text("\(cancelled) cancelados ou não compareceram").font(.subheadline).foregroundStyle(.secondary) }
            ProgressView(value: Double(appointments.count), total: Double(max(1, snapshot.days.compactMap { $0.appointments?.count }.max() ?? 1)))
                .accessibilityLabel("Volume de agendamentos do dia")
                .accessibilityValue("\(appointments.count) agendamentos")
        }.accessibilityElement(children: .combine)
    }

    private func filtered(_ values: [Appointment]) -> [Appointment] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return values }
        return values.filter {
            ((snapshot.patientNames[$0.pacienteId] ?? "") + " " + $0.statusLabel + " " + ($0.motivo ?? "")).localizedStandardContains(term)
        }
    }

    private func appointmentLink(_ appointment: Appointment) -> some View {
        NavigationLink { AppointmentDetailView(id: appointment.id, patientName: snapshot.patientNames[appointment.pacienteId], expectedPatientID: appointment.pacienteId, expectedProfessionalID: appointment.profissionalId) } label: {
            let type = typeCatalog?.itens.first { $0.id == (appointment.canal == "teleconsulta" ? "telemedicina" : appointment.tipo) }
            AgendaAppointmentRow(appointment: appointment, patientName: snapshot.patientNames[appointment.pacienteId], typeColor: type.flatMap { Color(hex: $0.cor) }, typeLabel: type?.rotulo)
        }
    }
}
