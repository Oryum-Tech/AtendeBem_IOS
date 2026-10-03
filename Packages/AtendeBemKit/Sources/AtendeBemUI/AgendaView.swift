import AtendeBemCore
import SwiftUI

struct AgendaView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case day = "Dia", list = "Lista", week = "Semana"
        var id: String { rawValue }
    }
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Date.now
    @State private var showCreate = false
    @State private var displayMode = DisplayMode.day
    @State private var search = ""
    @State private var resource = RemoteResource<AgendaSnapshot>()
    @State private var typeCatalog = RemoteResource<AppointmentTypeCatalog>()
    @State private var weeklyResource = RemoteResource<WeeklyAgendaSnapshot>()
    @State private var dailyContext: UUID?
    @State private var loadedDayKey: String?
    @State private var weeklyContext: UUID?
    @State private var catalogContext: UUID?
    private var dayKey: String { ClinicClock.day(day) }
    private var week: AgendaWeek { AgendaWeek(containing: day) }
    private var isWeekly: Bool { displayMode == .week }
    private var active: Bool { scenePhase == .active }
    private var visibleDay: AgendaSnapshot? { dailyContext == app.contextID && loadedDayKey == dayKey ? resource.value : nil }
    private var visibleWeek: WeeklyAgendaSnapshot? {
        guard weeklyContext == app.contextID, weeklyResource.value?.week.id == week.id else { return nil }
        return weeklyResource.value
    }
    private var visibleCatalog: AppointmentTypeCatalog? { catalogContext == app.contextID ? typeCatalog.value : nil }

    var body: some View {
        Group {
            if app.user?.canReadAgenda == true {
                List {
                    Section {
                        Picker("Visualização", selection: $displayMode) {
                            ForEach(DisplayMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("agenda.displayMode")
                        DatePicker(isWeekly ? "Semana da data" : "Dia", selection: $day, displayedComponents: .date)
                            .environment(\.timeZone, ClinicClock.timeZone).accessibilityIdentifier("agenda.day")
                        HStack {
                            Button { moveDay(isWeekly ? -7 : -1) } label: { Label("Anterior", systemImage: "chevron.left") }
                                .accessibilityLabel(isWeekly ? "Semana anterior" : "Dia anterior")
                            Spacer()
                            Button("Hoje") { day = .now }
                            Spacer()
                            Button { moveDay(isWeekly ? 7 : 1) } label: { Label("Seguinte", systemImage: "chevron.right") }
                                .accessibilityLabel(isWeekly ? "Próxima semana" : "Próximo dia")
                        }.buttonStyle(.borderless).frame(minHeight: 44)
                    } footer: {
                        Text(isWeekly ? "Compare os sete dias da semana e abra os agendamentos ou um dia completo." : displayMode == .day ? "Linha do tempo do dia, por hora. Horários em UTC−03:00." : "Lista compacta dos agendamentos do dia selecionado. Horários em UTC−03:00.")
                    }
                    Section {
                        NavigationLink { OperationalQueueView(day: dayKey) } label: {
                            Label("Sala de espera e atendimentos", systemImage: "person.2")
                        }
                    }
                    if isWeekly {
                        Section {
                            ConnectionState(updatedAt: visibleWeek == nil ? nil : weeklyResource.updatedAt,
                                            error: weeklyContext == app.contextID ? weeklyResource.error : nil,
                                            isLoading: weeklyResource.isLoading)
                            Button("Atualizar semana") { Task { await refreshWeek(force: true) } }
                                .disabled(weeklyResource.isLoading).accessibilityIdentifier("agenda.week.refresh")
                        }
                        if let snapshot = visibleWeek {
                            WeeklyAgendaSections(snapshot: snapshot, selectedDay: dayKey, search: search, typeCatalog: visibleCatalog) { date in
                                day = date
                                displayMode = .day
                            }
                        }
                    } else {
                        Section {
                            ConnectionState(updatedAt: visibleDay == nil ? nil : resource.updatedAt,
                                            error: dailyContext == app.contextID && loadedDayKey == dayKey ? resource.error : nil,
                                            isLoading: resource.isLoading)
                            if resource.error != nil { Button("Tentar novamente") { Task { await refreshDay() } } }
                        }
                        if let snapshot = visibleDay { dailySections(snapshot) }
                    }
                }
                .searchable(text: $search, prompt: isWeekly ? "Buscar nesta semana" : "Buscar neste dia")
                .refreshable { await refresh() }
                .task(id: "\(app.contextID)-\(dayKey)-\(active)-\(isWeekly)") {
                    guard active, !isWeekly else { return }
                    await refreshDay()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        await refreshDay()
                    }
                }
                .task(id: "\(app.contextID)-\(week.id)-\(active)-\(isWeekly)") {
                    guard active, isWeekly else { return }
                    await refreshWeek()
                }
                .task(id: "\(app.contextID)-\(active)") {
                    guard active else { return }
                    let reset = catalogContext != app.contextID
                    catalogContext = app.contextID
                    await typeCatalog.load(reset: reset, app: app) {
                        try await app.api.get(["agenda", "tipos-atendimento"], query: [.init(name: "escopo", value: "todos")])
                    }
                }
            } else { RestrictedState() }
        }.navigationTitle("Agenda")
        .toolbar {
            if app.user?.canConfirmAppointment == true {
                Button { showCreate = true } label: { Label("Novo agendamento", systemImage: "plus") }.accessibilityIdentifier("agenda.create")
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                AppointmentForm(initialDate: day) {
                    weeklyResource.clear()
                    Task { await refresh() }
                }
            }
        }
    }
    @ViewBuilder private func dailySections(_ snapshot: AgendaSnapshot) -> some View {
        if snapshot.namesUnavailable { Section { Label("Alguns nomes não puderam ser atualizados.", systemImage: "person.crop.circle.badge.exclamationmark") } }
        let appointments = filtered(snapshot)
        if displayMode == .day && search.isEmpty {
            ForEach(AgendaPresentation.hours(for: appointments), id: \.self) { hour in
                let inHour = appointments.filter { AgendaPresentation.hour(of: $0) == hour }
                Section(String(format: "%02d:00", hour)) {
                    if inHour.isEmpty { Text("Sem agendamentos").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8) }
                    ForEach(inHour) { appointment in appointmentLink(appointment, snapshot: snapshot) }
                }.accessibilityIdentifier("agenda.hour.\(hour)")
            }
            let withoutDate = appointments.filter { $0.startDate == nil }
            if !withoutDate.isEmpty { Section("Horário indisponível") { ForEach(withoutDate) { appointmentLink($0, snapshot: snapshot) } } }
        } else {
            Section("\(appointments.count) agendamentos") {
                if appointments.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Agenda livre" : "Nenhum resultado", systemImage: "calendar", description: Text(search.isEmpty ? "Não há agendamentos para este dia." : "Tente outro nome ou situação."))
                }
                ForEach(appointments) { appointmentLink($0, snapshot: snapshot) }
            }.accessibilityIdentifier("agenda.compactList")
        }
    }
    private func filtered(_ snapshot: AgendaSnapshot) -> [Appointment] {
        guard !search.isEmpty else { return snapshot.appointments }
        return snapshot.appointments.filter {
            ((snapshot.patientNames[$0.pacienteId] ?? "") + " " + $0.statusLabel + " " + ($0.motivo ?? "")).localizedStandardContains(search)
        }
    }
    private func appointmentLink(_ appointment: Appointment, snapshot: AgendaSnapshot) -> some View {
        NavigationLink { AppointmentDetailView(id: appointment.id, patientName: snapshot.patientNames[appointment.pacienteId], expectedPatientID: appointment.pacienteId, expectedProfessionalID: appointment.profissionalId) } label: {
            let type = visibleCatalog?.itens.first { $0.id == (appointment.canal == "teleconsulta" ? "telemedicina" : appointment.tipo) }
            AgendaAppointmentRow(appointment: appointment, patientName: snapshot.patientNames[appointment.pacienteId], typeColor: type.flatMap { Color(hex: $0.cor) }, typeLabel: type?.rotulo)
        }
    }
    private func moveDay(_ offset: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ClinicClock.timeZone
        day = calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }
    private func refresh() async {
        if isWeekly { await refreshWeek(force: true) }
        else { await refreshDay() }
    }
    private func refreshDay() async {
        let key = dayKey
        let reset = dailyContext != app.contextID || loadedDayKey != key
        dailyContext = app.contextID
        loadedDayKey = key
        await resource.load(reset: reset, app: app) { try await ClinicalService(api: app.api).agenda(day: key) }
    }
    private func refreshWeek(force: Bool = false) async {
        let requested = week
        let reset = weeklyContext != app.contextID || weeklyResource.value?.week.id != requested.id
        // Switching display modes or selecting another date in the same week reuses the snapshot.
        // Foreground return refreshes only a snapshot older than five minutes; there is no weekly polling.
        if !force, !reset, let updated = weeklyResource.updatedAt, Date.now.timeIntervalSince(updated) < 300 { return }
        weeklyContext = app.contextID
        await weeklyResource.load(reset: reset, app: app) { try await WeeklyAgendaService(api: app.api).load(week: requested) }
    }
}

struct AppointmentDetailView: View {
    let id: String
    let patientName: String?
    let expectedPatientID: String
    let expectedProfessionalID: String
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var resource = RemoteResource<Appointment>()
    @State private var selectedAction: AppointmentAction?
    @State private var selectedAppointment: Appointment?
    @State private var showConfirmation = false
    @State private var showReschedule = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var savedMessage: String?
    @State private var detailContext: UUID?
    @State private var showRequestConfirmation = false
    private var visibleAppointment: Appointment? { detailContext == app.contextID ? resource.value : nil }

    var body: some View {
        List {
            Section { ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading) }
            if let appointment = visibleAppointment, app.user?.canReadAgenda == true {
                Section(patientName ?? "Agendamento") {
                    if let date = appointment.startDate {
                        Text(date, format: .dateTime.day().month().year()).environment(\.timeZone, ClinicClock.timeZone)
                    }
                    LabeledContent("Horário", value: appointment.startDate.map(ClinicClock.time) ?? "Indisponível")
                    LabeledContent("Duração", value: "\(appointment.duracaoMin) minutos")
                    LabeledContent("Situação", value: appointment.statusLabel)
                    LabeledContent("Canal", value: appointment.canal == "teleconsulta" ? "Teleconsulta" : "Presencial")
                    if let reason = appointment.motivo, !reason.isEmpty { Text(reason) }
                    if app.user?.canReadPatients == true {
                        NavigationLink("Abrir paciente") { PatientDetailView(id: appointment.pacienteId) }
                    }
                    if app.user?.canReadClinicalData == true {
                        NavigationLink {
                            ClinicalActionsLoader(patientID: appointment.pacienteId, appointment: appointment)
                        } label: { Label("Abrir atendimento e documentos", systemImage: "stethoscope") }
                    }
                }
                Section("Confirmação e presença") {
                    if let state = AppointmentConfirmationState.resolve(appointment) { Text(state.label) }
                    if let date = appointment.confirmacaoPedidaEm.flatMap(ClinicClock.parseInstant) {
                        LabeledContent("Pedido registrado") { Text(date, format: .dateTime.day().month().hour().minute()).environment(\.timeZone, ClinicClock.timeZone) }
                    }
                    if let date = appointment.confirmadoEm.flatMap(ClinicClock.parseInstant) {
                        LabeledContent("Confirmação registrada") { Text(date, format: .dateTime.day().month().hour().minute()).environment(\.timeZone, ClinicClock.timeZone) }
                    }
                    if let date = appointment.chegadaEm.flatMap(ClinicClock.parseInstant) {
                        LabeledContent("Chegada") { Text(ClinicClock.time(date)) }
                    }
                    if appointment.liberacaoExcepcional == true { Label("Início liberado sem confirmação de presença", systemImage: "exclamationmark.circle") }
                    if let user = app.user, AppointmentConfirmationState.canRequest(appointment, user: user) {
                        Button("Pedir confirmação ao paciente") { showRequestConfirmation = true }.disabled(saving)
                    }
                }
                if let user = app.user {
                    Section {
                        ForEach(AppointmentAction.allCases.filter { $0.allowed(for: appointment, user: user) }) { action in
                            Button(action == .confirm ? "Registrar confirmação" : action.title, role: action == .cancel ? .destructive : nil) {
                                selectedAppointment = appointment; selectedAction = action; showConfirmation = true
                            }.disabled(saving).frame(minHeight: 44)
                        }
                        if user.canConfirmAppointment && ["scheduled", "pending", "confirmed"].contains(appointment.status) {
                            Button("Reagendar") { showReschedule = true }.disabled(saving)
                        }
                    } header: { Text("Atualizar situação") } footer: {
                        Text("Registrar chegada coloca o paciente na fila. Iniciar e concluir atualizam o atendimento para toda a equipe.")
                    }
                }
            }
            if let savedMessage { Section { Label(savedMessage, systemImage: "checkmark.circle") } }
            if let saveError { Section { Text(saveError).foregroundStyle(.red) } }
            if saving { ProgressView("Atualizando…") }
            if resource.error != nil { Button("Tentar novamente") { Task { await refresh() } } }
        }.navigationTitle("Agendamento").inlineTitle()
            .refreshable { if !saving { await refresh() } }
            .task(id: "\(app.contextID)-\(scenePhase)") {
                guard scenePhase == .active else { return }
                await refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    if !saving { await refresh() }
                }
            }
            .sheet(isPresented: $showReschedule) {
                if let appointment = visibleAppointment {
                    NavigationStack { AppointmentForm(appointment: appointment) { Task { await refresh() } } }
                }
            }
            .sheet(isPresented: $showRequestConfirmation) {
                if let appointment = visibleAppointment {
                    let context = app.contextID
                    NavigationStack {
                        RequestAppointmentConfirmationView(initial: appointment, patientName: patientName, presentationContext: context) { updated in
                            guard app.contextID == context else { return }
                            resource.value = updated; resource.updatedAt = .now
                        }
                    }
                }
            }
            .onChange(of: app.contextID) { _, _ in
                resource.clear(); savedMessage = nil; saveError = nil; showConfirmation = false
                showReschedule = false; showRequestConfirmation = false; selectedAppointment = nil
            }
            .confirmationDialog(selectedAction?.title ?? "Atualizar agendamento", isPresented: $showConfirmation, titleVisibility: .visible) {
                if let action = selectedAction {
                    Button(action == .confirm ? "Registrar confirmação" : action.title, role: action == .cancel ? .destructive : nil) { Task { await perform(action) } }
                }
                Button("Voltar", role: .cancel) {}
            } message: {
                Text(selectedAction == .complete
                     ? "Conclua somente depois de salvar suas anotações. Esta ação altera a situação do agendamento; não salva nem assina o prontuário."
                     : selectedAction == .confirm
                        ? "Registre somente se o paciente confirmou que comparecerá. Esta ação afirma a confirmação; para perguntar ao paciente, use Pedir confirmação."
                        : "A alteração será registrada na clínica e ficará disponível também na versão web.")
            }
    }
    private func refresh() async {
        guard app.user?.canReadAgenda == true else { resource.clear(); return }
        let reset = detailContext != app.contextID
        detailContext = app.contextID
        await resource.load(reset: reset, app: app) {
            let result: Appointment = try await app.api.get(["agendamentos", id])
            guard result.id == id, result.pacienteId == expectedPatientID,
                  result.profissionalId == expectedProfessionalID else {
                resource.value = nil; resource.updatedAt = nil
                throw APIError.invalidResponse
            }
            return result
        }
    }
    private func perform(_ action: AppointmentAction) async {
        guard !saving, let user = app.user, let expected = selectedAppointment else { return }
        let context = app.contextID
        saving = true; saveError = nil; savedMessage = nil
        defer { saving = false }
        do {
            let updated = try await AppointmentService(api: app.api).perform(action, id: id, user: user, expectedAppointment: expected)
            guard app.contextID == context else { return }
            resource.value = updated; resource.updatedAt = .now
            savedMessage = "Situação atualizada: \(updated.statusLabel)."
        } catch {
            guard app.contextID == context else { return }
            if error as? APIError == .invalidResponse { resource.value = nil; resource.updatedAt = nil }
            saveError = message(for: error)
            await app.checkSession(after: error)
            await refresh()
        }
    }
}
