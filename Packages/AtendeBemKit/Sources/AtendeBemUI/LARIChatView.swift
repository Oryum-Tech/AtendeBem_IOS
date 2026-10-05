import AtendeBemCore
import SwiftUI

struct LARIChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var conversation: LARIConversation?
    @State private var messages: [Entry] = []
    @State private var draft = ""
    @State private var includesConversationContext = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var confirmNew = false
    @State private var agreedToProcessing = false
    @State private var showProcessingConsent = false
    @State private var pendingQuestion: String?
    @State private var sendingTask: Task<Void, Never>?
    @State private var operationID: UUID?
    @State private var contextNotice: String?
    @State private var showTaskCatalog = false
    @State private var showsAllStarters = false
    @State private var taskSearch = ""
    @State private var onlyTasksToContinue = false
    @State private var selectedTask: LocalTaskRequest?
    private typealias LocalTaskRequest = LARITaskRequest
    private var taskHistory: [LocalTaskRequest] {
        guard let user = app.user else { return [] }
        return app.lariTasks.requests.reversed().filter {
            $0.context == app.contextID && $0.route.isAllowed(for: user)
        }
    }
    private var visibleTasks: [LocalTaskRequest] {
        taskHistory.filter { request in
            let progress = app.lariTasks.progress(for: request)
            return !onlyTasksToContinue || progress.needsAttention || progress.isWorking
        }
    }
    private var draftRoute: LARITaskRoute { .resolve(draft, includesConversationContext: includesConversationContext) }
    private var hasGeneralTextConsent: Bool {
        app.aiConsent.hasGeneralTextConsent(userID: app.user?.id, clinicID: app.activeClinicID)
    }
    private var canSendDraft: Bool {
        outcome.canSubmit && (draftRoute != .conversation || (hasGeneralTextConsent && app.user?.canReadClinicalData == true))
    }

    private struct Entry: Identifiable {
        let id = UUID()
        let question: String
        let reply: LARIReply
    }
    var body: some View {
        Group {
            if app.user?.canUseLARI == true {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if messages.isEmpty && taskHistory.isEmpty {
                                introduction
                                if let user = app.user {
                                    taskStarters(user: user)
                                }
                                if app.user?.canReadClinicalData == true {
                                NavigationLink { LARIAssistantView(patient: nil) } label: {
                                    Label("Organizar anotações em SOAP", systemImage: "doc.text")
                                }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                                Text("Inclua em cada pergunta o contexto necessário: o serviço ainda não usa automaticamente as mensagens anteriores para gerar a próxima resposta.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if app.user?.canReadClinicalData == true {
                                DisclosureGroup("Conversa com IA · autorização e privacidade", isExpanded: $showProcessingConsent) {
                                    AIProcessingNotice(includesPatient: false, agreed: $agreedToProcessing, rememberGeneralTextConsent: true)
                                }.id("processing-consent")
                            }
                            if (!messages.isEmpty || !taskHistory.isEmpty), let user = app.user {
                                DisclosureGroup("Nova tarefa", isExpanded: $showTaskCatalog) {
                                    taskStarters(user: user)
                                }.accessibilityIdentifier("lari.newTask")
                            }
                            if !taskHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Tarefas desta sessão").font(.headline)
                                    Picker("Mostrar tarefas", selection: $onlyTasksToContinue) {
                                        Text("Todas").tag(false)
                                        Text("Para continuar").tag(true)
                                    }.pickerStyle(.segmented)
                                        .accessibilityIdentifier("lari.taskFilter")
                                    if visibleTasks.isEmpty {
                                        Text("Nenhuma tarefa precisa de continuidade nesta sessão. Você pode consultar as anteriores em Todas.")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    ForEach(visibleTasks) { request in
                                        taskCard(request)
                                    }
                                }
                            }
                            ForEach(messages) { entry in
                                MessageBubble(author: "Você", text: entry.question, isOwn: true)
                                VStack(alignment: .leading, spacing: 12) {
                                    MessageBubble(author: "LARI", text: entry.reply.text, isOwn: false)
                                    if !entry.reply.citations.isEmpty {
                                        Text("Fontes da resposta").font(.subheadline.bold())
                                        ForEach(Array(entry.reply.citations.enumerated()), id: \.offset) { _, citation in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(citation.fonte)
                                                if let reference = citation.referencia {
                                                    if let url = URL(string: reference), url.scheme == "https", url.host != nil,
                                                       url.user == nil, url.password == nil { Link(reference, destination: url) }
                                                    else { Text(reference) }
                                                }
                                            }.font(.footnote)
                                        }
                                    }
                                    Text(entry.reply.disclaimer).font(.footnote).foregroundStyle(.secondary)
                                    if entry.reply.requiresSupervision {
                                        Label("Revisão profissional necessária", systemImage: "person.badge.shield.checkmark").font(.footnote.bold())
                                    }
                                    if entry.id == messages.last?.id {
                                        Button { addContext(from: entry) } label: {
                                            Label("Adicionar último contexto ao rascunho", systemImage: "text.badge.plus")
                                        }.frame(minHeight: 44).disabled(outcome != .ready)
                                            .accessibilityIdentifier("lari.addPreviousContext")
                                    }
                                }.id(entry.id)
                            }
                            if let pendingQuestion { MessageBubble(author: "Você · aguardando confirmação", text: pendingQuestion, isOwn: true) }
                            if outcome == .sending {
                                VStack(alignment: .leading, spacing: 12) {
                                    ProgressView("A LARI está preparando a resposta…")
                                    Text("O serviço envia o texto após concluir o processamento.").font(.footnote).foregroundStyle(.secondary)
                                    Button("Parar espera") { sendingTask?.cancel() }.frame(minHeight: 44)
                                        .accessibilityIdentifier("lari.cancel")
                                }
                            }
                            if let error { Text(error).foregroundStyle(.red) }
                            if draftRoute == .clarify, !draft.isEmpty {
                                Button {
                                    taskSearch = ""
                                    showTaskCatalog = true
                                    proxy.scrollTo("task-catalog", anchor: .top)
                                } label: { Label("Escolher uma tarefa", systemImage: "square.grid.2x2") }
                                    .frame(minHeight: 44).accessibilityIdentifier("lari.clarify")
                                Text("Seu pedido permanece no campo de mensagem. Escolher uma tarefa abre uma nova preparação, sem executar o texto ambíguo.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if let contextNotice { Text(contextNotice).font(.footnote).foregroundStyle(.secondary) }
                            if outcome == .uncertain {
                                Text("Não foi possível confirmar a resposta. Sua mensagem pode ter sido recebida. Ela não será reenviada automaticamente. Seu rascunho foi preservado; iniciar outra conversa permite revisá-lo antes de decidir por um novo envio.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Button("Nova conversa com este rascunho") { confirmNew = true }
                                    .frame(minHeight: 44).accessibilityIdentifier("lari.recover")
                            }
                            Color.clear.frame(height: 1).id("latest")
                        }.padding()
                            .frame(maxWidth: 840)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                    .onChange(of: outcome) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 0) {
                            if !hasGeneralTextConsent && draftRoute == .conversation && app.user?.canReadClinicalData == true {
                                Button("Leia e autorize o processamento para enviar") {
                                    showProcessingConsent = true
                                    proxy.scrollTo("processing-consent", anchor: .bottom)
                                }
                                    .font(.footnote).padding(.horizontal).frame(minHeight: 44)
                                    .accessibilityIdentifier("lari.reviewConsent")
                            }
                            MessageComposer(text: $draft, sending: outcome == .sending,
                                enabled: canSendDraft, prompt: "Peça uma tarefa ou escreva uma mensagem", send: startSending)
                            Text(draftRoute != .conversation
                                 ? "Você revisará os dados e as autorizações na tela da tarefa antes de qualquer ação."
                                 : app.user?.canReadClinicalData == true
                                    ? "Na conversa com IA, evite identificar pacientes. As respostas precisam de revisão."
                                    : "Escolha uma tarefa disponível para seu perfil na clínica atual.")
                                .font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 6)
                        }.background(.bar)
                    }
                }
            } else { RestrictedState() }
        }
        .navigationTitle("LARI").inlineTitle()
        .onChange(of: app.aiConsent.hasGeneralTextConsent(userID: app.user?.id, clinicID: app.activeClinicID), initial: true) { _, consent in
            agreedToProcessing = consent
            if !consent { sendingTask?.cancel() }
        }
        .toolbar {
            Button { confirmNew = true } label: { Label("Nova conversa", systemImage: "square.and.pencil") }
                .disabled(outcome == .sending || (messages.isEmpty && draft.isEmpty && error == nil))
        }
        .confirmationDialog("Iniciar outra conversa?", isPresented: $confirmNew, titleVisibility: .visible) {
            if !draft.isEmpty { Button("Nova conversa e manter rascunho") { resetConversation(keepDraft: true) } }
            Button("Nova conversa vazia", role: .destructive) { resetConversation(keepDraft: false) }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("As respostas atuais sairão desta tela e as gravações de áudio desta conversa serão descartadas. Receitas, agendamentos e exames já iniciados permanecem disponíveis nesta sessão, inclusive resultados incertos. Nenhuma mensagem será enviada ao iniciar a conversa.") }
        .sheet(item: $selectedTask) { request in
            NavigationStack {
                Group {
                    if request.context != app.contextID {
                        ContentUnavailableView("Clínica ou sessão alterada", systemImage: "lock",
                            description: Text("Feche esta tarefa e confira seu acesso na clínica atual."))
                    } else if let user = app.user, request.route.isAllowed(for: user) {
                        taskContent(request)
                    } else {
                        RestrictedState()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fechar") { selectedTask = nil }
                            .disabled(taskIsWorking(request))
                    }
                }
                .interactiveDismissDisabled(taskIsWorking(request))
            }
        }
        .onDisappear { sendingTask?.cancel() }
        .onChange(of: draft) { _, value in if value.isEmpty { includesConversationContext = false } }
        .onChange(of: app.contextID) { _, _ in
            sendingTask?.cancel(); sendingTask = nil; operationID = nil
            resetConversation(keepDraft: false)
            agreedToProcessing = hasGeneralTextConsent; showProcessingConsent = false
            app.lariTasks.invalidateAll()
            selectedTask = nil
            taskSearch = ""; onlyTasksToContinue = false
            showsAllStarters = false
        }
    }
    private func taskCard(_ request: LocalTaskRequest) -> some View {
        let progress = app.lariTasks.progress(for: request)
        return VStack(alignment: .leading, spacing: 8) {
            Button { selectedTask = request } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label(request.title, systemImage: request.symbol).font(.headline)
                    Label(progress.title, systemImage: progress.symbol).font(.subheadline.bold())
                    Text(progress.detail).font(.footnote).foregroundStyle(.secondary)
                    Text(request.command).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.buttonStyle(.bordered)
                .accessibilityHint("Abre os dados e a situação desta tarefa para revisão.")
                .accessibilityIdentifier("lari.task.\(request.route.rawValue)")
            if app.lariTasks.canStartAnother(after: request) {
                Button("Criar outra tarefa com nova revisão") {
                    selectedTask = app.lariTasks.startAnother(after: request)
                }.frame(minHeight: 44).accessibilityIdentifier("lari.task.new.\(request.route.rawValue)")
            }
        }
    }
    private func taskIsWorking(_ request: LocalTaskRequest) -> Bool { app.lariTasks.isWorking(request) }
    @ViewBuilder private func taskContent(_ request: LocalTaskRequest) -> some View {
        switch request.route {
        case .prescription:
            LARIPrescriptionTaskView(command: request.command, task: app.lariTasks.prescriptionTasks[request.id]) { task in
                guard request.context == app.contextID else { task.invalidate(); return }
                app.lariTasks.prescriptionTasks[request.id] = task
            }
        case .appointment:
            LARIAppointmentTaskView(command: request.command, task: app.lariTasks.appointmentTasks[request.id]) { task in
                guard request.context == app.contextID else { task.invalidate(); return }
                app.lariTasks.appointmentTasks[request.id] = task
            }
        case .patientHistory:
            LARIHistoryTaskView(command: request.command, task: app.lariTasks.historyTasks[request.id]) { task in
                guard request.context == app.contextID else { task.invalidate(); return }
                app.lariTasks.historyTasks[request.id] = task
            }
        case .examRequest:
            LARIExamRequestTaskView(command: request.command, task: app.lariTasks.examTasks[request.id]) { task in
                guard request.context == app.contextID else { task.invalidate(); return }
                app.lariTasks.examTasks[request.id] = task
            }
        case .financial: LARIFinancialReportView(command: request.command)
        case .transcription:
            LARITranscriptionTaskView(command: request.command, session: app.lariTasks.audioSessions[request.id]) { session in
                guard request.context == app.contextID else { session.invalidate(); return }
                app.lariTasks.audioSessions[request.id] = session
            }
        case .analytics: LARIAnalyticsTaskView(command: request.command)
        case .interactions: LARIInteractionsTaskView(command: request.command)
        case .medicineReference: LARIMedicineReferenceTaskView(command: request.command)
        case .clarify, .conversation: EmptyView()
        }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Como posso ajudar?", systemImage: "sparkles")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text("Cuide da consulta e da rotina da clínica em um só lugar. Cada tarefa mostra os dados usados e respeita seu acesso.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var starterColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)]
    }
    private func taskStarters(user: User) -> some View {
        let matchingTasks = LARITaskRoute.availableTasks(for: user, matching: taskSearch)
        let isSearching = taskSearch.trimmedOrNil != nil
        let presentedTasks = showsAllStarters || isSearching ? matchingTasks : Array(matchingTasks.prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            Text("O que você precisa fazer?").font(.headline)
            TextField("Buscar tarefa: prontuário, áudio, bulas…", text: $taskSearch)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                .accessibilityLabel("Buscar tarefa da LARI")
                .accessibilityIdentifier("lari.taskSearch")
            if matchingTasks.isEmpty {
                Text("Nenhuma tarefa encontrada para seu acesso. Tente outro termo.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: starterColumns, alignment: .leading, spacing: 12) {
                ForEach(presentedTasks) { route in
                    taskStarter(route)
                }
            }
            if !isSearching && matchingTasks.count > 4 {
                Button(showsAllStarters ? "Mostrar menos" : "Ver todas as tarefas (\(matchingTasks.count))") {
                    showsAllStarters.toggle()
                }.frame(minHeight: 44)
                    .accessibilityIdentifier("lari.allTasks")
            }
        }.id("task-catalog")
    }
    private func taskStarter(_ route: LARITaskRoute) -> some View {
        Button {
            startTask(command: route.starter, route: route, preservingDraft: true)
            showTaskCatalog = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: route.symbol).font(.title3).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(route.title).font(.headline).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(route.explanation).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
        }.buttonStyle(.bordered).accessibilityIdentifier("lari.starter.\(route.rawValue)")
    }
    private func resetConversation(keepDraft: Bool) {
        app.lariTasks.discardAudioSessions()
        showTaskCatalog = true
        conversation = nil; messages = []; pendingQuestion = nil; error = nil; outcome = .ready; contextNotice = nil
        if !keepDraft { draft = ""; includesConversationContext = false }
    }
    private func addContext(from entry: Entry) {
        guard outcome == .ready else { return }
        do {
            let combined = try LARIContinuation.draft(question: entry.question, reply: entry.reply.text, preserving: draft)
            includesConversationContext = true
            draft = combined
            error = nil
            contextNotice = "A última pergunta e resposta foram adicionadas ao rascunho. Revise esse conteúdo e escreva sua próxima pergunta. O texto será enviado aos provedores de IA somente quando você tocar em Enviar."
        } catch {
            contextNotice = (error as? LARIContinuationError)?.localizedDescription ?? "Não foi possível adicionar o contexto. Seu rascunho foi preservado."
        }
    }
    private func startSending() {
        guard outcome.canSubmit, sendingTask == nil else { return }
        guard let command = draft.trimmedOrNil, command.count <= LARIContinuation.maximumCharacters else { return }
        let route = draftRoute
        if route != .conversation {
            startTask(command: command, route: route)
            return
        }
        guard app.user?.canReadClinicalData == true, hasGeneralTextConsent else {
            error = "Use uma das tarefas disponíveis para seu perfil. A conversa clínica com IA exige acesso assistencial e autorização."
            return
        }
        let id = UUID()
        operationID = id
        sendingTask = Task { await send(operation: id) }
    }
    private func startTask(command: String, route: LARITaskRoute, preservingDraft: Bool = false) {
        guard let user = app.user, user.canUseLARI else { return }
        error = nil
        guard route != .clarify else {
            error = "Escolha uma tarefa ou ajuste seu pedido. Agendamentos novos têm preparação própria; alterações e cancelamentos devem ser feitos pela Agenda. Seu texto foi preservado."
            showTaskCatalog = true
            taskSearch = ""
            return
        }
        guard route != .conversation else { return }
        guard route.isAllowed(for: user) else {
            error = "Seu perfil nesta clínica não permite esta tarefa: \(route.title.lowercased())."
            return
        }
        // The owner lives in AppState, so leaving and reopening LARI preserves uncertain operations.
        selectedTask = app.lariTasks.request(command: command, route: route, context: app.contextID)
        if !preservingDraft { draft = ""; includesConversationContext = false }
        contextNotice = preservingDraft && !draft.isEmpty ? "Sua mensagem foi preservada. A tarefa foi aberta separadamente para revisão." : nil
    }
    private func send(operation: UUID) async {
        defer {
            if operationID == operation { sendingTask = nil; operationID = nil }
        }
        guard hasGeneralTextConsent, outcome.canSubmit, let text = draft.trimmedOrNil, app.user?.canReadClinicalData == true else { return }
        let context = app.contextID
        outcome = .sending; error = nil; pendingQuestion = text; contextNotice = nil
        let apiContext = await app.api.requestContextID()
        guard app.contextID == context, operationID == operation else { return }
        guard hasGeneralTextConsent, app.user?.canReadClinicalData == true else {
            outcome = .ready; pendingQuestion = nil
            error = "Confira seu acesso e autorize o texto geral antes de enviar. Seu rascunho foi preservado."
            return
        }
        do {
            let exchange = try await LARIService(api: app.api).send(text: text, conversation: conversation, expectedContext: apiContext)
            guard app.contextID == context, operationID == operation else { return }
            conversation = exchange.conversation
            messages.append(Entry(question: text, reply: exchange.reply)); pendingQuestion = nil; draft = ""; outcome = .ready
        } catch {
            guard app.contextID == context, operationID == operation else { return }
            if let failure = error as? LARISendFailure {
                conversation = failure.conversation
                outcome = failure.messageMayHaveBeenReceived ? .uncertain : .ready
                if !failure.messageMayHaveBeenReceived { pendingQuestion = nil }
                if failure.sessionRenewed {
                    self.error = "Sua sessão foi renovada. O rascunho está preservado; toque em Enviar para tentar novamente."
                } else if failure.underlying is CancellationError {
                    self.error = failure.messageMayHaveBeenReceived ? "A espera foi interrompida; o serviço ainda pode concluir a resposta." : "A espera foi interrompida antes do envio da mensagem."
                } else { self.error = message(for: failure.underlying) }
                await app.checkSession(after: failure.underlying)
            } else {
                outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
                await app.checkSession(after: error)
            }
        }
    }
}

struct MessageComposer: View {
    @Binding var text: String
    let sending: Bool
    let enabled: Bool
    var prompt = "Mensagem"
    var limit = 4_000
    let send: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(1...6).padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(sending)
                Button(action: send) {
                    if sending { ProgressView().frame(width: 44, height: 44) }
                    else { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
                }.accessibilityLabel("Enviar mensagem")
                    .disabled(!enabled || sending || text.trimmedOrNil == nil || text.count > limit)
            }
            if text.count > limit { Text("Limite de \(limit) caracteres.").font(.caption).foregroundStyle(.red) }
        }.padding().background(.bar)
    }
}

struct MessageBubble: View {
    let author: String
    let text: String
    let isOwn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(author).font(.caption.bold()).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isOwn ? Brand.accent.opacity(0.1) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
