import AtendeBemCore
import SwiftUI

struct CommunityPeopleView: View {
    @Environment(AppState.self) private var app
    @State private var people = RemoteResource<[CommunitySuggestion]>()
    @State private var search = ""
    var body: some View {
        List {
            ConnectionState(updatedAt: people.updatedAt, error: people.error, isLoading: people.isLoading)
            if people.error != nil { Button("Tentar novamente") { Task { await load() } } }
            ForEach((people.value ?? []).filter { search.isEmpty || $0.nome.localizedCaseInsensitiveContains(search) || ($0.especialidade?.localizedCaseInsensitiveContains(search) ?? false) }) { person in
                NavigationLink { CommunityProfileView(userID: person.id) } label: {
                    HStack(spacing: 12) {
                    ProfileAvatarView(name: person.nome, mediaID: person.avatarMidiaId)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.nome).font(.headline)
                        if let specialty = person.especialidade { Text(specialty).font(.subheadline).foregroundStyle(.secondary) }
                        Text("\(person.seguidores) seguidores").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                    }
                }
            }
            if people.value?.isEmpty == true { ContentUnavailableView("Sem sugestões no momento", systemImage: "person.2") }
        }.navigationTitle("Encontrar colegas").inlineTitle()
            .searchable(text: $search, prompt: "Nome ou especialidade nas sugestões")
            .task { await load() }.refreshable { await load() }
    }
    private func load() async { await people.load(app: app) { try await app.api.get(["comunidade", "sugestoes"]) } }
}

struct CommunityProfileView: View {
    var userID: String? = nil
    @Environment(AppState.self) private var app
    @State private var profile = RemoteResource<CommunityProfile?>()
    @State private var posts = RemoteResource<[CommunityPost]>()
    @State private var editing = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var conversation: CommunityConversation?
    private var current: CommunityProfile? { profile.value ?? nil }
    private var mine: Bool { userID == nil || userID == app.user?.id }
    var body: some View {
        List {
            Section {
                ConnectionState(updatedAt: profile.updatedAt, error: profile.error, isLoading: profile.isLoading)
                if let value = current {
                    HStack(alignment: .top, spacing: 14) {
                        ProfileAvatarView(name: value.nome, mediaID: value.avatarMidiaId, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(value.nome).font(.title2.bold())
                            if let specialty = value.especialidade, !specialty.isEmpty { Text(specialty).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 4)
                    if let crm = value.crm, !crm.isEmpty { LabeledContent("Registro informado", value: crm) }
                    if let bio = value.bio, !bio.isEmpty { Text(bio).textSelection(.enabled) }
                    LabeledContent("Publicações", value: String(value.posts))
                    LabeledContent("Seguidores", value: String(value.seguidores))
                    LabeledContent("Seguindo", value: String(value.seguindo))
                    ForEach(value.redes.keys.sorted(), id: \.self) { key in
                        if let raw = value.redes[key], let url = URL(string: raw),
                           url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
                            Link(key.capitalized, destination: url)
                        }
                    }
                    if !mine {
                        Button(value.seguidoPorMim ? "Deixar de seguir" : "Seguir profissional") { Task { await follow(value) } }
                            .disabled(!outcome.canSubmit || profile.isLoading || profile.error != nil)
                        Button { Task { await openChat(value) } } label: { Label("Enviar mensagem", systemImage: "bubble.left") }
                            .disabled(!outcome.canSubmit)
                    }
                } else if profile.updatedAt != nil && mine {
                    ContentUnavailableView("Apresente-se à comunidade", systemImage: "person.crop.circle",
                        description: Text("Adicione uma descrição profissional e seus canais públicos."))
                }
                if let error { Text(error).foregroundStyle(.red) }
                if profile.error != nil || outcome == .uncertain {
                    Button("Conferir perfil no serviço") { Task { await load() } }
                }
                if outcome == .sending { ProgressView("Atualizando…") }
            }
            if mine && profile.updatedAt != nil && profile.error == nil {
                Section { Button("Editar meu perfil") { editing = true } }
            }
            Section("Publicações") {
                ConnectionState(updatedAt: posts.updatedAt, error: posts.error, isLoading: posts.isLoading)
                if posts.error != nil { Button("Atualizar publicações") { Task { await load() } } }
                if posts.value?.isEmpty == true { Text("Nenhuma publicação retornada.").foregroundStyle(.secondary) }
                ForEach(posts.value ?? []) { post in CommunityPostCard(initial: post) { Task { await load() } } }
            }
        }.navigationTitle(mine ? "Meu perfil público" : "Perfil profissional").inlineTitle()
            .task(id: userID) { await load() }.refreshable { await load() }
            .sheet(isPresented: $editing) {
                NavigationStack { CommunityProfileEditor(profile: current) { Task { await load() } } }
            }
            .navigationDestination(item: $conversation) { item in
                TeamConversationView(conversationID: item.id, name: item.outro?.nome ?? current?.nome ?? "Profissional", pathPrefix: ["comunidade", "dm"])
            }
    }
    private func load() async {
        await profile.load(app: app) { try await app.api.get(["comunidade", "perfis", mine ? "me" : (userID ?? "me")]) }
        if profile.error == nil && outcome != .sending { outcome = .ready; error = nil }
        if let id = current?.id {
            await posts.load(app: app) { try await app.api.get(["comunidade", "perfis", id, "posts"]) }
        } else { posts.clear() }
    }
    private func follow(_ value: CommunityProfile) async {
        guard outcome.canSubmit else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: EmptyResponse = try await app.api.post(["comunidade", "perfis", value.id, "seguir"])
            guard context == app.contextID else { return }
            await load()
            outcome = profile.error == nil ? .ready : .uncertain
        } catch {
            guard context == app.contextID else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
    private func openChat(_ value: CommunityProfile) async {
        guard outcome.canSubmit else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let item: CommunityConversation = try await app.api.post(["comunidade", "dm", "conversas"], body: ["paraId": value.id])
            guard context == app.contextID else { return }
            conversation = item; outcome = .ready
        } catch {
            guard context == app.contextID else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

private struct CommunityProfileEditor: View {
    let profile: CommunityProfile?
    let onSave: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var crm = ""
    @State private var specialty = ""
    @State private var bio = ""
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var initialized = false
    var body: some View {
        Form {
            Section("Informações públicas") {
                TextField("Nome profissional", text: $name)
                TextField("Registro profissional", text: $crm)
                TextField("Especialidade", text: $specialty)
                TextField("Sobre você", text: $bio, axis: .vertical).lineLimit(4...10)
                Text("Seu perfil é visível na comunidade. Não inclua informações de pacientes.").font(.footnote).foregroundStyle(.secondary)
            }.disabled(outcome == .sending)
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button("Salvar perfil público") { Task { await save() } }
                    .disabled(!outcome.canSubmit || name.trimmedOrNil == nil || name.count > 200 || crm.count > 30 || specialty.count > 120 || bio.count > 1_000)
            }
        }.navigationTitle("Editar perfil").inlineTitle()
            .toolbar { Button("Fechar") { dismiss() }.disabled(outcome == .sending) }
            .interactiveDismissDisabled(outcome == .sending)
            .onAppear {
                guard !initialized else { return }; initialized = true
                name = profile?.nome ?? app.user?.nome ?? ""; crm = profile?.crm ?? ""
                specialty = profile?.especialidade ?? ""; bio = profile?.bio ?? ""
            }
    }
    private struct Update: Encodable, Sendable {
        let nome: String; let crm: String; let especialidade: String; let bio: String
        let redes: [String: String]; let avatarMidiaId: String?
    }
    private func save() async {
        guard outcome.canSubmit, let name = name.trimmedOrNil else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: CommunityProfile = try await app.api.put(["comunidade", "perfis", "me"],
                body: Update(nome: name, crm: crm, especialidade: specialty, bio: bio,
                    redes: profile?.redes ?? [:], avatarMidiaId: profile?.avatarMidiaId))
            guard app.contextID == context else { return }
            outcome = .succeeded; onSave(); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

struct CommunityInboxView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var conversations = RemoteResource<[CommunityConversation]>()
    var body: some View {
        List {
            Section {
                Text("Mensagens entre profissionais da comunidade. O chat da equipe da clínica fica em Mais.").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink { CommunityPeopleView() } label: { Label("Encontrar colegas", systemImage: "person.badge.plus") }
                ConnectionState(updatedAt: conversations.updatedAt, error: conversations.error, isLoading: conversations.isLoading)
                if conversations.error != nil { Button("Tentar novamente") { Task { await load() } } }
            }
            ForEach(conversations.value ?? []) { item in
                NavigationLink {
                    TeamConversationView(conversationID: item.id, name: item.outro?.nome ?? "Profissional", pathPrefix: ["comunidade", "dm"])
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                    ProfileAvatarView(name: item.outro?.nome ?? "", mediaID: item.outro?.avatarMidiaId)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.outro?.nome ?? "Perfil indisponível").font(.headline)
                        Text(item.ultimaMensagem?.conteudo ?? "Conversa iniciada").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        if item.naoLidas > 0 { Text("\(item.naoLidas) não lidas").font(.caption.bold()).foregroundStyle(Brand.accent) }
                    }.padding(.vertical, 6)
                    }
                }
            }
            if conversations.value?.isEmpty == true { ContentUnavailableView("Suas conversas aparecerão aqui", systemImage: "bubble.left.and.bubble.right") }
        }.navigationTitle("Mensagens da comunidade").inlineTitle().refreshable { await load() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await load()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await load()
                }
            }
    }
    private func load() async { await conversations.load(app: app) { try await app.api.get(["comunidade", "dm", "conversas"]) } }
}
