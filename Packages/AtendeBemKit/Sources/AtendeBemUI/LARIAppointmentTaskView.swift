import AtendeBemCore
import SwiftUI

struct LARIAppointmentTaskView: View {
    let command: String
    var task: LARIAppointmentTask? = nil
    var onTaskReady: ((LARIAppointmentTask) -> Void)? = nil
    @Environment(AppState.self) private var app
    @State private var model: LARIAppointmentTask?
    @State private var confirmCreate = false
    var body: some View {
        Group {
            if app.user?.canConfirmAppointment != true { RestrictedState() }
            else if let model { content(model) }
            else { ProgressView("Preparando agendamento…") }
        }.navigationTitle("Agendar com LARI").inlineTitle()
            .interactiveDismissDisabled(model?.isWorking == true)
            .task { [app] in
                guard model == nil, let user = app.user, user.canConfirmAppointment else { return }
                if let task { model = task; return }
                let context = app.contextID, apiContext = await app.api.requestContextID()
                guard context == app.contextID else { return }
                let created = LARIAppointmentTask(command: command, api: app.api, context: apiContext, user: user,
                    isContextCurrent: { [weak app] in app?.contextID == context && app?.user?.id == user.id && app?.user?.canConfirmAppointment == true })
                model = created; onTaskReady?(created)
                await created.loadOptions(); await created.searchPatients(); await recover()
            }
            .confirmationDialog("Confirmar este agendamento?", isPresented: $confirmCreate, titleVisibility: .visible) {
                Button("Criar agendamento") { Task { await model?.create(); await recover() } }
                Button("Voltar à revisão", role: .cancel) {}
            } message: { Text("O paciente e o horário serão conferidos novamente. A criação usa as regras e as notificações já configuradas pela clínica.") }
    }
    private func content(_ model: LARIAppointmentTask) -> some View {
        @Bindable var form = model
        return Form {
            LARITaskContextSection(command: command, explanation: "Vou encontrar horários do profissional e preparar o agendamento para sua confirmação.")
            if let appointment = model.appointment {
                Section {
                    Label("Agendamento confirmado pelo sistema", systemImage: "checkmark.circle")
                    if let patient = model.lookup.patient { LARIPatientIdentity(patient: patient) }
                    if let date = appointment.startDate { Text(date, format: .dateTime.weekday().day().month().year().hour().minute()).environment(\.timeZone, ClinicClock.timeZone) }
                    LabeledContent("Duração", value: "\(appointment.duracaoMin) minutos")
                    LabeledContent("Situação", value: appointment.statusLabel)
                    NavigationLink("Abrir agendamento") { AppointmentDetailView(id: appointment.id, patientName: model.lookup.patient?.nome, expectedPatientID: appointment.pacienteId, expectedProfessionalID: appointment.profissionalId) }
                } footer: { Text("A situação retornada pelo serviço é diferente de confirmação ou recebimento de mensagem pelo paciente.") }
            } else {
                LARIPatientTaskSection(lookup: model.lookup, editable: model.canEdit, search: model.searchPatients, select: model.selectPatient, change: model.changePatient)
                Section("Profissional e atendimento") {
                    Picker("Profissional", selection: $form.professionalID) {
                        Text("Selecionar profissional").tag("")
                        ForEach(model.professionals) { Text($0.nome).tag($0.id) }
                    }
                    Picker("Tipo de atendimento", selection: $form.typeID) {
                        Text("Selecionar tipo").tag("")
                        ForEach(model.types) { Text($0.rotulo).tag($0.id) }
                    }
                    Picker("Canal", selection: $form.channel) {
                        Text("Selecionar canal").tag("")
                        Text("Presencial").tag("presencial"); Text("Teleconsulta").tag("teleconsulta")
                    }
                    Button("Atualizar profissionais e tipos") { Task { await model.loadOptions(); await recover() } }
                }.disabled(!model.canEdit)
                Section {
                    DatePicker("Dia para procurar", selection: $form.day, displayedComponents: .date).environment(\.timeZone, ClinicClock.timeZone)
                    if let requested = model.command.requestedStart {
                        Text("Horário informado no seu pedido:").font(.footnote)
                        Text(requested, format: .dateTime.day().month().year().hour().minute()).font(.footnote).environment(\.timeZone, ClinicClock.timeZone)
                        Text("Escolha uma opção retornada pelo sistema.").font(.footnote)
                    }
                    if let duration = model.command.requestedDuration {
                        Text("Duração solicitada: \(duration) minutos. Só poderão ser confirmados horários com essa duração.").font(.footnote)
                    }
                    Button("Consultar horários disponíveis") { Task { await model.loadAvailability(); await recover() } }
                        .disabled(!model.canEdit || model.selectedProfessional == nil)
                    if model.availabilityLoaded && model.slots.isEmpty { Text("Nenhum horário futuro disponível foi retornado para esse dia.").font(.footnote) }
                    ForEach(model.slots) { slot in
                        if let date = slot.date {
                            Button { model.selectSlot(slot) } label: {
                                HStack {
                                    Text(date, format: .dateTime.hour().minute()).environment(\.timeZone, ClinicClock.timeZone)
                                    Text("· \(slot.duracaoMin) min").foregroundStyle(.secondary)
                                    Spacer()
                                    if model.selectedSlot == slot { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Selecionado") }
                                }.frame(minHeight: 32)
                            }.disabled(!model.canEdit || (model.command.requestedDuration != nil && model.command.requestedDuration != slot.duracaoMin))
                        }
                    }
                } header: { Text("Horário") } footer: { Text("Horário da clínica: UTC−03:00. A consulta de disponibilidade não reserva a vaga. O servidor confere conflitos novamente ao criar.") }
                .disabled(!model.canEdit)
                if let patient = model.lookup.patient, let slot = model.selectedSlot, let professional = model.selectedProfessional, let type = model.selectedType {
                    Section("Revisão do agendamento") {
                        LabeledContent("Paciente", value: patient.nome)
                        LabeledContent("Profissional", value: professional.nome)
                        LabeledContent("Atendimento", value: type.rotulo)
                        if let date = slot.date { Text(date, format: .dateTime.day().month().year().hour().minute()).environment(\.timeZone, ClinicClock.timeZone) }
                        LabeledContent("Duração", value: "\(slot.duracaoMin) minutos")
                        Toggle("Conferi paciente, profissional, tipo, canal e horário", isOn: $form.reviewed).disabled(!model.canEdit)
                        Button("Confirmar agendamento") { confirmCreate = true }.disabled(!model.canCreate)
                    }
                }
            }
            Section {
                if model.busy { ProgressView("Conferindo o sistema…") }
                WriteStatus(outcome: model.outcome, error: model.error)
                if model.outcome == .uncertain {
                    Button("Conferir o resultado deste pedido") { Task { await model.reconcile(); await recover() } }.disabled(model.isWorking)
                    Text("A consulta usa o identificador original. O agendamento não será repetido automaticamente.").font(.footnote)
                }
            }
        }
    }
    private func recover() async { if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) } }
}
