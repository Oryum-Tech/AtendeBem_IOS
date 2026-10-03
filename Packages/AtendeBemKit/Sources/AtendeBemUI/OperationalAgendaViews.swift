import AtendeBemCore
import SwiftUI

/// Embedded in Today and reached from Agenda; no additional root tab.
struct OperationalQueueSections: View {
    let day: String
    var refreshTrigger: Int = 0
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var professionalID = ""
    @State private var resource = RemoteResource<OperationalQueueSnapshot>()
    @State private var loadedContext: UUID?
    @State private var loadedFilter: String?
    @State private var loadedDay: String?
    private var visible: OperationalQueueSnapshot? {
        guard loadedContext == app.contextID, loadedFilter == professionalID, loadedDay == day else { return nil }
        return resource.value
    }
    var body: some View {
        Section {
            if let user = app.user, OperationalAgendaPolicy.canFilterTeam(user) {
                Picker("Profissional da fila", selection: $professionalID) {
                    Text("Toda a equipe").tag("")
                    // Keep available options when a filter hides the previous snapshot.
                    ForEach(loadedContext == app.contextID ? resource.value?.professionals ?? [] : []) { person in
                        Text(person.nome).tag(person.id)
                    }
                    if !professionalID.isEmpty, resource.value?.professionals.contains(where: { $0.id == professionalID }) != true {
                        Text("Profissional selecionado").tag(professionalID)
                    }
                }.accessibilityIdentifier("queue.professional")
            } else { Label("Minha fila de atendimentos", systemImage: "person.crop.circle") }
            ConnectionState(updatedAt: visible == nil ? nil : resource.updatedAt,
                            error: loadedContext == app.contextID && loadedFilter == professionalID ? resource.error : nil,
                            isLoading: resource.isLoading)
            if let snapshot = visible {
                if snapshot.namesUnavailable { Text("Alguns nomes de pacientes não puderam ser carregados.").font(.footnote).foregroundStyle(.secondary) }
                if snapshot.teamUnavailable { Text("Os nomes da equipe estão indisponíveis. A fila continua no recorte informado.").font(.footnote).foregroundStyle(.secondary) }
                if let date = ClinicClock.parseInstant(snapshot.queue.geradoEm) {
                    Text("Tempos calculados às \(ClinicClock.time(date))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Atualizar fila") { Task { await refresh() } }.disabled(resource.isLoading)
                .accessibilityIdentifier("queue.refresh")
        } header: { Text("Sala de espera") } footer: {
            Text("A ordem e os tempos vêm da clínica. Atualização a cada 30 segundos enquanto esta tela está ativa. Horários em UTC−03:00.")
        }
            .task(id: "\(app.contextID)-\(day)-\(professionalID)-\(scenePhase)-\(refreshTrigger)") {
                guard scenePhase == .active, app.user?.canReadAgenda == true else { return }
                await refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await refresh()
                }
            }
        if let snapshot = visible {
            Section("Aguardando · \(snapshot.queue.totalAguardando)") {
                if snapshot.queue.itens.isEmpty { Text("Ninguém aguardando neste momento.").foregroundStyle(.secondary) }
                ForEach(snapshot.queue.itens) { item in row(item, snapshot: snapshot, attending: false) }
            }
            Section("Em atendimento · \(snapshot.queue.emAtendimento.count)") {
                if snapshot.queue.emAtendimento.isEmpty { Text("Nenhum atendimento em andamento.").foregroundStyle(.secondary) }
                ForEach(snapshot.queue.emAtendimento) { item in row(item, snapshot: snapshot, attending: true) }
            }
        }

    }
    private func row(_ item: WaitingItem, snapshot: OperationalQueueSnapshot, attending: Bool) -> some View {
        NavigationLink {
            AppointmentDetailView(id: item.agendamentoId, patientName: snapshot.patientNames[item.pacienteId],
                                  expectedPatientID: item.pacienteId, expectedProfessionalID: item.profissionalId)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.patientNames[item.pacienteId] ?? "Nome indisponível").font(.headline)
                if !attending, let position = item.posicao { Text("Posição \(position) na fila").font(.subheadline.weight(.medium)) }
                if let date = ClinicClock.parseInstant(item.inicio) { Text("Agendado para \(ClinicClock.time(date))").font(.subheadline).monospacedDigit() }
                if let arrival = item.chegadaEm.flatMap(ClinicClock.parseInstant) {
                    Text("Chegada às \(ClinicClock.time(arrival))").font(.caption)
                    if !attending { Text("Aguardando há \(item.esperaMin) min").font(.subheadline) }
                } else { Text("Chegada não registrada").font(.caption).foregroundStyle(.secondary) }
                if !attending, let delay = item.atrasoMin {
                    Text(delay > 0 ? "\(delay) min além do horário agendado" : delay < 0 ? "Faltam \(delay.magnitude) min para o horário agendado" : "No horário agendado")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let name = snapshot.professionals.first(where: { $0.id == item.profissionalId })?.nome {
                    Label(name, systemImage: "stethoscope").font(.caption).foregroundStyle(.secondary)
                }
                if item.autoCheckin == true { Label("Chegada informada pelo paciente", systemImage: "person.crop.circle.badge.checkmark").font(.caption) }
                if item.liberacaoExcepcional == true {
                    Label("Início liberado sem confirmação de presença", systemImage: "exclamationmark.circle").font(.caption)
                    if let reason = item.liberacaoMotivo, !reason.isEmpty { Text("Justificativa: \(reason)").font(.caption).foregroundStyle(.secondary) }
                }
            }.padding(.vertical, 6).accessibilityElement(children: .combine)
        }.accessibilityIdentifier("queue.appointment.\(item.agendamentoId)")
    }
    private func refresh() async {
        guard let user = app.user, user.canReadAgenda else { resource.clear(); return }
        let reset = loadedContext != app.contextID || loadedDay != day || loadedFilter != professionalID
        loadedContext = app.contextID; loadedDay = day; loadedFilter = professionalID
        let selected = professionalID.isEmpty ? nil : professionalID
        await resource.load(reset: reset, app: app) {
            let context = await app.api.requestContextID()
            return try await OperationalQueueService(api: app.api).load(day: day, user: user, professionalID: selected, context: context)
        }
    }
}

struct OperationalQueueView: View {
    let day: String
    @Environment(AppState.self) private var app
    var body: some View {
        List {
            if app.user?.canReadAgenda == true { OperationalQueueSections(day: day).id(app.contextID) }
            else { RestrictedState() }
        }.navigationTitle("Sala de espera").inlineTitle()
    }
}

struct RequestAppointmentConfirmationView: View {
    let initial: Appointment
    let patientName: String?
    let presentationContext: UUID
    let updated: (Appointment?) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var workflow: AppointmentConfirmationWorkflow?
    @State private var loadedContext: UUID?
    @State private var showSend = false
    @State private var validatedName: String?
    @State private var preparationError: String?
    var body: some View {
        List {
            if presentationContext == app.contextID, loadedContext == app.contextID, let model = workflow {
                if let appointment = model.appointment {
                Section("Confira antes de solicitar") {
                    Text(validatedName ?? "Nome indisponível").font(.headline)
                    if let date = appointment.startDate {
                        Text(date, format: .dateTime.day().month().year().hour().minute()).environment(\.timeZone, ClinicClock.timeZone)
                    }
                    LabeledContent("Situação", value: appointment.statusLabel)
                    if let state = AppointmentConfirmationState.resolve(appointment) { Text(state.label) }
                }
                }
                Section {
                    if model.appointment == nil {
                        Text("O acesso ao agendamento não está disponível. Feche esta tela e atualize a agenda.")
                    } else if model.outcome == .succeeded {
                        Label("Pedido registrado na clínica", systemImage: "checkmark.circle")
                        Text("Isso não comprova a entrega da mensagem nem a confirmação do paciente.").font(.subheadline)
                    } else if model.outcome == .uncertain {
                        Text("O pedido pode ter sido registrado. O envio não será repetido automaticamente.")
                        Button("Consultar situação do pedido") { Task { await model.reconcile(); await apply(model) } }
                            .disabled(model.busy)
                    } else if model.appointment != nil {
                        Button("Pedir confirmação ao paciente") { showSend = true }.disabled(!model.canRequest || validatedName == nil)
                            .accessibilityIdentifier("confirmation.request")
                    }
                    if model.busy { ProgressView("Conferindo agendamento…") }
                    if let error = model.error { Text(error).foregroundStyle(.red) }

                } footer: {
                    Text("Este pedido inicia o fluxo de mensagem da clínica para o paciente. Registrar que o paciente confirmou é uma ação separada. Um novo pedido é permitido somente após 12 horas.")
                }
            } else if let preparationError {
                Section { Text(preparationError).foregroundStyle(.red); Text("Feche e abra novamente para conferir o paciente antes de solicitar a mensagem.") }
            } else { ProgressView("Conferindo paciente…") }
        }.navigationTitle("Pedir confirmação").inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.disabled(workflow?.busy == true) } }
            .interactiveDismissDisabled(workflow?.busy == true)
            .task(id: app.contextID) {
                workflow?.invalidate(); workflow = nil; validatedName = nil; preparationError = nil
                guard presentationContext == app.contextID, let user = app.user, user.canConfirmAppointment else { dismiss(); return }
                let context = app.contextID
                let apiContext = await app.api.requestContextID()
                guard app.contextID == context else { return }
                do {
                    let patient: Patient = try await app.api.get(["pacientes", initial.pacienteId])
                    guard app.contextID == context, await app.api.requestContextID() == apiContext else { return }
                    guard patient.id == initial.pacienteId, !patient.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidResponse }
                    validatedName = patient.nome
                    loadedContext = context
                    workflow = AppointmentConfirmationWorkflow(appointment: initial, user: user, api: app.api, context: apiContext)
                } catch {
                    guard app.contextID == context else { return }
                    preparationError = message(for: error)
                    await app.checkSession(after: error)
                }
            }
            .onChange(of: app.contextID) { _, _ in workflow?.invalidate(); workflow = nil; dismiss() }
            .onDisappear { workflow?.invalidate() }
            .confirmationDialog("Solicitar confirmação deste agendamento?", isPresented: $showSend, titleVisibility: .visible) {
                Button("Solicitar mensagem ao paciente") {
                    Task {
                        guard loadedContext == app.contextID, let model = workflow else { return }
                        await model.request()
                        guard loadedContext == app.contextID else { return }
                        await apply(model)
                    }
                }
                Button("Voltar", role: .cancel) {}
            } message: {
                Text("A clínica solicitará uma mensagem para \(validatedName ?? "o paciente") sobre o horário exibido. O agendamento continuará sem confirmação até ela ser registrada.")
            }
    }
    private func apply(_ model: AppointmentConfirmationWorkflow) async {
        guard presentationContext == app.contextID else { return }
        updated(model.appointment)
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }

}
