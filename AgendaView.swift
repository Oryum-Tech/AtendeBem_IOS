import SwiftUI
import AtendeBemCore

struct AgendaView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = ClinicClock.day(.now)
    @State private var agenda = RemoteResource<AgendaSnapshot>()

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    DatePicker("Dia", selection: Binding(get: {
                        ISO8601DateFormatter().date(from: day + "T12:00:00Z") ?? Date()
                    }, set: { newValue in
                        day = ClinicClock.day(newValue)
                        agenda.clear()
                    }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
            }
            Section {
                ConnectionState(updatedAt: agenda.updatedAt, error: agenda.error, isLoading: agenda.isLoading)
                if agenda.error != nil { Button("Atualizar agenda") { Task { await refresh(reset: true) } } }
            }
            if let snapshot = agenda.value {
                Section("Agendamentos") {
                    if snapshot.appointments.isEmpty {
                        Text("Nenhum agendamento neste dia.").foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.appointments) { appt in
                        AgendaAppointmentRow(appointment: appt, patientName: snapshot.patientNames[appt.pacienteId])
                    }
                    if snapshot.namesUnavailable {
                        Text("Nem todos os nomes puderam ser carregados.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Agenda")
        .inlineTitle()
        .refreshable { await refresh(reset: true) }
        .task(id: "\(day)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            await refresh(reset: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await refresh()
            }
        }
    }

    private func shift(_ days: Int) {
        let cal = Calendar(identifier: .gregorian)
        let base = ISO8601DateFormatter().date(from: day + "T12:00:00Z") ?? Date()
        if let next = cal.date(byAdding: .day, value: days, to: base) {
            day = ClinicClock.day(next)
            agenda.clear()
        }
    }

    private func refresh(reset: Bool = false) async {
        let selected = day
        await agenda.load(reset: reset, app: app) {
            try await ClinicalService(api: app.api).agenda(day: selected)
        }
    }
}

