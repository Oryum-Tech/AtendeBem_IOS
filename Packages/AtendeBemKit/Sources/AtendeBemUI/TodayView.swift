import AtendeBemCore
import SwiftUI

struct TodayView: View {
    private enum PresentedForm: String, Identifiable {
        case appointment, patient
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var app
    @Environment(WorkspacePreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedAction: ClinicalShortcut?
    @State private var presentedForm: PresentedForm?
    @State private var agenda = RemoteResource<AgendaSnapshot>()
    @State private var agendaContext: UUID?
    @State private var loadedDay: String?
    @State private var currentDate = Date.now
    @State private var queueRefresh = 0
    @State private var showsAllContinuations = false

    private var day: String { ClinicClock.day(currentDate) }
    private var canReadAgenda: Bool { app.user?.canReadAgenda == true }
    private var showsAgenda: Bool { canReadAgenda && preferences.homeWidgets.contains(.todayAgenda) }
    private var agendaMatchesContext: Bool {
        agendaContext == app.contextID && loadedDay == day && day == ClinicClock.day(.now)
    }
    private var visibleAgenda: AgendaSnapshot? { agendaMatchesContext && canReadAgenda ? agenda.value : nil }
    private var overview: TodayOverview? {
        guard let snapshot = visibleAgenda, let loadedDay else { return nil }
        return TodayOverview(appointments: snapshot.appointments, loadedDay: loadedDay, now: currentDate)
    }
    private var visibleActions: [ClinicalShortcut] {
        preferences.quickActions.filter { $0.isAllowed(for: app.user) }
    }

    var body: some View {
        List {
            Section {
                HomeContextHeader(name: app.user?.nome, clinicName: app.clinicName, date: currentDate)
            }
            if preferences.homeWidgets.contains(.clinicalShortcuts), !visibleActions.isEmpty {
                Section("O que você precisa fazer?") {
                    HomeActionGrid(actions: visibleActions, selectedAction: $selectedAction)
                }
            }
            consultationContinuations
            if showsAgenda { nextAppointment }
            if app.user?.containsAnyRole(["recepcao"]) == true { receptionActions }
            if app.user?.canUseLARI == true {
                Section {
                    NavigationLink { LARIChatView() } label: {
                        HomeLARILabel(financialOnly: app.user?.canReadFinancialReports == true && app.user?.canReadClinicalData != true)
                    }.accessibilityIdentifier("home.lariAssistant")
                }
            }
            if app.user?.canReadFinancialReports == true { managementActions }
            if showsAgenda { agendaPreview }
            if canReadAgenda && preferences.homeWidgets.contains(.waitingQueue) {
                OperationalQueueSections(day: day, refreshTrigger: queueRefresh).id(app.contextID)
            }
            if !canReadAgenda && app.user?.canReadClinicalData != true && app.user?.canReadFinancialReports != true {
                Section {
                    Text("As áreas disponíveis respeitam seu perfil nesta clínica.").foregroundStyle(.secondary)
                    NavigationLink("Ver minha conta") { AccountView() }
                }
            }
        }
        .navigationTitle("Hoje")
        .navigationDestination(item: $selectedAction) { action in
            if action == .lari { LARIChatView() }
            else { PatientsView(action: action) }
        }
        .toolbar {
            if app.clinics.count > 1 {
                NavigationLink { ClinicsView() } label: { Label("Trocar clínica", systemImage: "building.2") }
            }
            NavigationLink { WorkspaceCustomizationView() } label: { Label("Personalizar início", systemImage: "slider.horizontal.3") }
        }
        .sheet(item: $presentedForm) { form in
            NavigationStack {
                switch form {
                case .appointment: AppointmentForm { Task { await refresh() } }
                case .patient: PatientForm { Task { await refresh() } }
                }
            }
        }
        .refreshable { await refresh() }
        .task(id: scenePhase) { await keepClockCurrent() }
        .task(id: "\(app.contextID)-\(day)-\(scenePhase)-\(showsAgenda)") {
            guard scenePhase == .active, showsAgenda else { return }
            await refresh(refreshQueue: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await refresh(refreshQueue: false)
            }
        }
        .onChange(of: app.contextID) { _, _ in
            selectedAction = nil; presentedForm = nil
            showsAllContinuations = false
            agenda.clear(); agendaContext = nil; loadedDay = nil
        }
    }

    @ViewBuilder private var consultationContinuations: some View {
        if app.user?.canReadClinicalData == true && !app.consultations.continuations.isEmpty {
            Section {
                if let session = app.consultations.continuations.first {
                    continuation(session)
                }
                if app.consultations.continuations.count > 1 {
                    DisclosureGroup(isExpanded: $showsAllContinuations) {
                        ForEach(Array(app.consultations.continuations.dropFirst())) { session in
                            continuation(session)
                        }
                    } label: {
                        Text("Ver outras consultas para retomar (\(app.consultations.continuations.count - 1))")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("home.otherContinuations")
                }
            } header: { Text("Continue de onde parou") } footer: {
                Text("Somente nesta sessão. Salve as anotações antes de encerrar o aplicativo, sair da conta ou trocar de clínica. Retomar não envia nem confirma uma evolução.")
            }
        }
    }

    private func continuation(_ session: ConsultationSessionStore.Entry) -> some View {
        NavigationLink { ContinueConsultationView(sessionID: session.id) } label: {
            HomeContinuationLabel(patientName: session.patientName, status: session.status)
        }
        .disabled(session.workflow.isBusy)
        .accessibilityHint("Abre as anotações desta consulta sem enviar ou confirmar uma evolução.")
        .accessibilityIdentifier("consultation.resume.\(session.id)")
    }

    @ViewBuilder private var nextAppointment: some View {
        Section {
            if let snapshot = visibleAgenda, let overview {
                if let appointment = overview.nextAppointment {
                    NavigationLink {
                        appointmentDetail(appointment, snapshot: snapshot)
                    } label: {
                        HomeAppointmentFocus(appointment: appointment, patientName: snapshot.patientNames[appointment.pacienteId])
                    }.accessibilityIdentifier("home.nextAppointment")
                    if app.user?.canReadPatients == true {
                        NavigationLink { PatientDetailView(id: appointment.pacienteId) } label: {
                            Label("Ver ficha do paciente", systemImage: "person.text.rectangle")
                        }
                        .accessibilityHint("Abre a ficha de \(snapshot.patientNames[appointment.pacienteId] ?? "quem está neste agendamento") para conferir os dados disponíveis ao seu perfil.")
                        .accessibilityIdentifier("home.nextPatient")
                    }
                } else {
                    HomeAgendaEmptyState(hasAppointments: !snapshot.appointments.isEmpty,
                                         hasUnusableAppointments: overview.hasUnusableAppointments)
                }
                if snapshot.namesUnavailable || snapshot.appointments.contains(where: { snapshot.patientNames[$0.pacienteId] == nil }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Identificação parcialmente disponível", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.subheadline.weight(.medium))
                        Text("Alguns nomes não foram carregados. Abra o agendamento para conferir o paciente ou tente atualizar.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if agenda.error == nil {
                        Button("Atualizar identificação dos pacientes") { Task { await refresh(refreshQueue: false) } }
                            .disabled(agenda.isLoading)
                            .accessibilityIdentifier("home.retryPatientNames")
                    }
                }
                if overview.hasUnusableAppointments {
                    Text("Alguns registros não puderam ser incluídos nesta prévia. Confira a agenda completa.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ConnectionState(updatedAt: visibleAgenda == nil ? nil : agenda.updatedAt,
                            error: agendaMatchesContext ? agenda.error : nil, isLoading: agenda.isLoading)
            if agendaMatchesContext && agenda.error != nil {
                Button("Atualizar agenda") { Task { await refresh() } }
                    .disabled(agenda.isLoading)
            }
            if app.user?.canConfirmAppointment == true && app.user?.containsAnyRole(["recepcao"]) != true {
                Button { presentedForm = .appointment } label: { Label("Agendar atendimento", systemImage: "calendar.badge.plus") }
                    .accessibilityIdentifier("home.createAppointment")
            }
            NavigationLink { OperationalQueueView(day: day) } label: {
                Label("Ver quem já chegou", systemImage: "person.2")
            }
            .accessibilityHint("Abre a sala de espera com a ordem informada pela clínica.")
            .accessibilityIdentifier("home.waitingRoom")
            NavigationLink { AgendaView() } label: { Label("Ver agenda completa", systemImage: "calendar") }
                .accessibilityIdentifier("home.fullAgenda")
        } header: { Text("Próximo agendamento") } footer: {
            Text("Por horário, no recorte disponível para seu perfil. A ordem de atendimento é acompanhada na sala de espera.")
        }
    }

    private var receptionActions: some View {
        Section("Recepção") {
            if app.user?.canConfirmAppointment == true {
                Button { presentedForm = .appointment } label: { Label("Agendar atendimento", systemImage: "calendar.badge.plus") }
                    .accessibilityIdentifier("home.createAppointment")
            }
            if app.user?.canCreatePatient == true {
                Button { presentedForm = .patient } label: { Label("Cadastrar paciente", systemImage: "person.badge.plus") }
            }
            NavigationLink { TeamChatView() } label: { Label("Falar com a equipe", systemImage: "bubble.left.and.bubble.right") }
        }
    }

    private var managementActions: some View {
        Section("Gestão da clínica") {
            NavigationLink { FinancialDashboardView() } label: { Label("Financeiro", systemImage: "chart.line.uptrend.xyaxis") }
            if app.user?.canReadReports == true {
                NavigationLink { ReportsView() } label: { Label("Relatórios", systemImage: "chart.bar.xaxis") }
            }
        }
    }

    @ViewBuilder private var agendaPreview: some View {
        if let snapshot = visibleAgenda, let overview, !overview.previewAppointments.isEmpty {
            Section {
                ForEach(overview.previewAppointments) { appointment in
                    NavigationLink { appointmentDetail(appointment, snapshot: snapshot) } label: {
                        AgendaAppointmentRow(appointment: appointment, patientName: snapshot.patientNames[appointment.pacienteId])
                    }
                }
                if overview.hasMoreAppointments {
                    NavigationLink { AgendaView() } label: {
                        Label("Ver os demais agendamentos", systemImage: "calendar")
                    }
                }
            } header: { Text(overview.nextAppointment == nil ? "Agenda de hoje" : "Mais na agenda de hoje") }
        }
    }

    private func appointmentDetail(_ appointment: Appointment, snapshot: AgendaSnapshot) -> some View {
        AppointmentDetailView(id: appointment.id, patientName: snapshot.patientNames[appointment.pacienteId],
                              expectedPatientID: appointment.pacienteId, expectedProfessionalID: appointment.profissionalId)
    }

    private func refresh(refreshQueue: Bool = true) async {
        guard canReadAgenda else { return }
        if refreshQueue { queueRefresh += 1 }
        guard showsAgenda else { return }
        let today = ClinicClock.day(.now)
        let reset = agendaContext != app.contextID || loadedDay != today
        agendaContext = app.contextID
        loadedDay = today
        await agenda.load(reset: reset, app: app) { try await ClinicalService(api: app.api).agenda(day: today) }
    }

    private func keepClockCurrent() async {
        guard scenePhase == .active else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ClinicClock.timeZone
        while !Task.isCancelled {
            let now = Date.now
            currentDate = now
            // Wake at midnight even when the 30-second tick straddles clinic days.
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            let interval = min(30, max(0.1, midnight?.timeIntervalSince(now) ?? 30))
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        }
    }
}
