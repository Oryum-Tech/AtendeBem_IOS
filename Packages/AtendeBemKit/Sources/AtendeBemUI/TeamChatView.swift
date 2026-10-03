import AtendeBemCore
import SwiftUI

struct TeamChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var conversations = RemoteResource<[TeamConversation]>()
    @State private var members = RemoteResource<[TeamMember]>()
    @State private var showMembers = false
    @State private var selected: TeamConversation?
    @State private var opening = false
    @State private var error: String?
    @State private var search = ""

    var body: some View {
        List {
            Section {
                Text(app.clinicName).font(.subheadline).foregroundStyle(.secondary)
                ConnectionState(updatedAt: conversations.updatedAt, error: conversations.error, isLoading: conversations.isLoading)
                if conversations.error != nil || members.error != nil {
                    if let error = members.error { Text(error).foregroundStyle(.secondary) }
                    Button("Tentar novamente") { Task { await refresh() } }
                }
            }
            if let values = conversations.value {
                if values.isEmpty {
                    ContentUnavailableView("Converse com sua equipe", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Inicie uma conversa com um membro desta clínica."))
                }
                ForEach(values) { conversation in
                    NavigationLink {
                        TeamConversationView(conversation: conversation, name: name(conversation.outroId))
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(name(conversation.outroId)).font(.headline)
                                Spacer()
                                if conversation.naoLidas > 0 {
                                    Text("\(conversation.naoLidas)").font(.caption.bold()).foregroundStyle(Brand.accent)
                                        .accessibilityLabel("\(conversation.naoLidas) mensagens não lidas")
                                }
                            }
                            Text(conversation.ultimaMensagem?.conteudo ?? "Conversa iniciada")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Chat da equipe").inlineTitle()
        .toolbar { Button { showMembers = true } label: { Label("Nova conversa", systemImage: "square.and.pencil") } }
        .sheet(isPresented: $showMembers) {
            NavigationStack {
                List {
                    if opening { ProgressView("Abrindo conversa…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    ForEach((members.value ?? []).filter { $0.id != app.user?.id && (search.isEmpty || $0.nome.localizedCaseInsensitiveContains(search)) }) { member in
                        Button(member.nome) { Task { await open(member) } }.disabled(opening)
                    }
                    if members.isLoading { ProgressView("Buscando equipe…") }
                    if let error = members.error { Text(error).foregroundStyle(.red) }
                    if !members.isLoading && (members.value ?? []).filter({ $0.id != app.user?.id }).isEmpty {
                        Text("Nenhum outro membro disponível nesta clínica.").foregroundStyle(.secondary)
                    }
                }
                .searchable(text: $search, prompt: "Nome do profissional")
                .navigationTitle("Nova conversa").inlineTitle()
                .toolbar { Button("Fechar") { showMembers = false }.disabled(opening) }
            }.interactiveDismissDisabled(opening)
        }
        .navigationDestination(item: $selected) { conversation in
            TeamConversationView(conversation: conversation, name: name(conversation.outroId))
        }
        .refreshable { await refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await conversations.load(app: app) { try await app.api.get(["equipe", "conversas"]) }
            }
        }
    }
    private func name(_ id: String) -> String { members.value?.first { $0.id == id }?.nome ?? "Membro da equipe" }
    private func refresh() async {
        await conversations.load(app: app) { try await app.api.get(["equipe", "conversas"]) }
        await members.load(app: app) { try await app.api.get(["usuarios"]) }
    }
    private func open(_ member: TeamMember) async {
        guard !opening else { return }
        let context = app.contextID
        opening = true; error = nil
        defer { opening = false }
        do {
            let value: TeamConversation = try await app.api.post(["equipe", "conversas"], body: ["paraId": member.id])
            guard app.contextID == context else { return }
            showMembers = false; selected = value
        } catch {
            guard app.contextID == context else { return }
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

struct TeamConversationView: View {
    let conversationID: String
    let name: String
    let pathPrefix: [String]
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages = RemoteResource<[TeamMessage]>()
    @State private var confirmedSent: [TeamMessage] = []
    @State private var draft = ""
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var confirmRetry = false
    @State private var confirmRead = false
    @State private var markingRead = false
    @State private var readNotice: String?
    init(conversation: TeamConversation, name: String) {
        self.conversationID = conversation.id; self.name = name; self.pathPrefix = ["equipe"]
    }
    init(conversationID: String, name: String, pathPrefix: [String]) {
        self.conversationID = conversationID; self.name = name; self.pathPrefix = pathPrefix
    }
    private var path: [String] { pathPrefix + ["conversas", conversationID, "mensagens"] }
    private var visibleMessages: [TeamMessage] {
        guard var values = messages.value else { return [] }
        let ids = Set(values.map(\.id))
        values += confirmedSent.filter { !ids.contains($0.id) }
        return values.sorted { $0.criadoEm < $1.criadoEm }
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ConnectionState(updatedAt: messages.updatedAt, error: messages.error, isLoading: messages.isLoading)
                    if pathPrefix.first == "comunidade" {
                        Text("Conversa entre profissionais. Não envie dados que identifiquem pacientes.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let readNotice { Text(readNotice).font(.footnote).foregroundStyle(.secondary) }
                    if messages.error != nil { Button("Atualizar conversa") { Task { await refresh() } } }
                    if (messages.value?.count ?? 0) >= 50 {
                        Text("O serviço limitou o histórico retornado. Mensagens mais recentes podem não aparecer. Confira também na web.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if messages.value?.isEmpty == true && confirmedSent.isEmpty {
                        ContentUnavailableView("Comece a conversa", systemImage: "bubble.left", description: Text("As mensagens ficam disponíveis para vocês nesta clínica."))
                    }
                    ForEach(visibleMessages) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            MessageBubble(author: item.autorId == app.user?.id ? "Você" : name, text: item.conteudo, isOwn: item.autorId == app.user?.id)
                            if let date = ClinicClock.parseInstant(item.criadoEm) {
                                Text(date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                        }.id(item.id)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    if outcome == .uncertain {
                        Text("O envio não foi confirmado. Confira as mensagens antes de tentar de novo para evitar duplicatas.").font(.footnote)
                        Button("Já conferi a conversa") { confirmRetry = true }
                    }
                    Color.clear.frame(height: 1).id("latest")
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: confirmedSent.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            .safeAreaInset(edge: .bottom) {
                MessageComposer(text: $draft, sending: outcome == .sending, enabled: outcome.canSubmit && messages.value != nil && messages.error == nil) { Task { await send() } }
            }
            .refreshable { await refresh() }
        }
        .navigationTitle(name).inlineTitle()
        .toolbar {
            Menu {
                Button("Marcar todas como lidas") { confirmRead = true }
                    .disabled(markingRead || messages.value == nil || messages.error != nil)
            } label: { Label("Ações da conversa", systemImage: "ellipsis.circle") }
        }
        .confirmationDialog("Marcar todas as mensagens como lidas?", isPresented: $confirmRead, titleVisibility: .visible) {
            Button("Marcar todas como lidas") { Task { await markRead() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação inclui todas as mensagens recebidas nesta conversa, mesmo as que não aparecem no histórico limitado pelo serviço.")
        }
        .confirmationDialog("O texto ainda está no campo de mensagem", isPresented: $confirmRetry, titleVisibility: .visible) {
            Button("Manter texto para revisar") { outcome = .ready; error = nil }
            Button("Limpar texto já enviado") { draft = ""; outcome = .ready; error = nil }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Se a mensagem já apareceu no histórico, limpe o campo para evitar enviar duas vezes.") }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await refresh()
            }
        }
    }
    private func refresh() async {
        await messages.load(app: app) { try await app.api.get(path) }
    }
    private func markRead() async {
        guard !markingRead else { return }
        let context = app.contextID
        markingRead = true; readNotice = nil
        defer { markingRead = false }
        do {
            let _: EmptyResponse = try await app.api.post(pathPrefix + ["conversas", conversationID, "ler"])
            guard app.contextID == context else { return }
            readNotice = "Mensagens marcadas como lidas pelo serviço."
            await refresh()
        } catch {
            guard app.contextID == context else { return }
            readNotice = "Não foi possível confirmar a marcação de leitura. \(message(for: error))"
            await app.checkSession(after: error)
        }
    }
    private func send() async {
        guard outcome.canSubmit, let text = draft.trimmedOrNil, text.count <= 4_000 else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let sent: TeamMessage = try await app.api.post(path, body: ["conteudo": text])
            guard app.contextID == context else { return }
            confirmedSent.append(sent); draft = ""; outcome = .ready
            await refresh()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}
