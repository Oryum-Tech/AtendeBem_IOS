import AtendeBemCore
import SwiftUI

struct CommunityView: View {
    @Environment(AppState.self) private var app
    @State private var feed = "recentes"
    @State private var posts = RemoteResource<[CommunityPost]>()
    @State private var compose = false
    var body: some View {
        List {
            Section {
                NavigationLink { CommunityPeopleView() } label: { Label("Encontrar colegas", systemImage: "person.badge.plus") }
                NavigationLink { CommunityInboxView() } label: { Label("Mensagens da comunidade", systemImage: "bubble.left.and.bubble.right") }
                NavigationLink { CommunityProfileView() } label: { Label("Meu perfil público", systemImage: "person.crop.circle") }
            }
            Section {
                Picker("Publicações", selection: $feed) {
                    Text("Recentes").tag("recentes")
                    Text("Seguindo").tag("seguindo")
                    Text("Especialidade").tag("especialidade")
                    Text("Salvos").tag("salvos")
                }
                ConnectionState(updatedAt: posts.updatedAt, error: posts.error, isLoading: posts.isLoading)
                if posts.error != nil { Button("Tentar novamente") { Task { await refresh() } } }
            }
            if let values = posts.value {
                if values.isEmpty {
                    ContentUnavailableView("Nenhuma publicação por aqui", systemImage: "person.3.sequence",
                        description: Text("Escolha outro filtro ou compartilhe uma experiência com a comunidade."))
                }
                ForEach(values) { post in
                    Section {
                        CommunityPostCard(initial: post) { Task { await refresh() } }
                    }
                }
            }
        }.navigationTitle("Comunidade médica").inlineTitle()
            .toolbar { Button { compose = true } label: { Label("Nova publicação", systemImage: "square.and.pencil") } }
            .sheet(isPresented: $compose) { NavigationStack { CommunityComposer { Task { await refresh() } } } }
            .onChange(of: feed) { _, _ in posts.clear() }
            .task(id: feed) { await refresh() }
            .refreshable { await refresh() }
    }
    private func refresh() async {
        let requested = feed
        await posts.load(app: app) {
            if requested == "salvos" { return try await app.api.get(["comunidade", "salvos"]) }
            return try await app.api.get(["comunidade", "posts"], query: [.init(name: "feed", value: requested)])
        }
    }
}

struct CommunityPostCard: View {
    let initial: CommunityPost
    var onChange: () -> Void = {}
    @Environment(AppState.self) private var app
    @State private var updated: CommunityPost?
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var removed = false
    @State private var editing = false
    @State private var sharing = false
    @State private var confirmRemove = false
    private var post: CommunityPost { updated ?? initial }
    var body: some View {
        if !removed { VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ProfileAvatarView(name: post.autorNome, mediaID: post.autorAvatarMidiaId, anonymous: post.anonimo)
                VStack(alignment: .leading, spacing: 4) {
                if let id = post.autorId, !post.anonimo {
                    NavigationLink { CommunityProfileView(userID: id) } label: { Text(post.autorNome).font(.headline) }
                } else { Text(post.anonimo ? "Anônimo" : post.autorNome).font(.headline) }
                if let specialty = post.especialidade { Text(specialty).font(.subheadline).foregroundStyle(.secondary) }
                if let date = ClinicClock.parseInstant(post.criadoEm) { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let title = post.titulo { Text(title).font(.title3.bold()) }
            Text(post.conteudo).textSelection(.enabled)
            if let original = post.original {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compartilhado de \(original.autorNome)").font(.subheadline.bold())
                    if let title = original.titulo { Text(title).bold() }
                    Text(original.conteudo)
                }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            if let media = post.midia {
                if media.tipo == "imagem" { CommunityImageView(mediaID: media.id) }
                else { Label("Vídeo disponível na versão web.", systemImage: "video").font(.footnote).foregroundStyle(.secondary) }
            }
            HStack(spacing: 20) {
                Button { Task { await toggle("curtir") } } label: {
                    Label("\(post.curtidas)", systemImage: post.curtiu ? "heart.fill" : "heart")
                }.accessibilityLabel(post.curtiu ? "Remover curtida, \(post.curtidas) curtidas" : "Curtir, \(post.curtidas) curtidas")
                Button { Task { await toggle("salvar") } } label: {
                    Label(post.salvou ? "Salvo" : "Salvar", systemImage: post.salvou ? "bookmark.fill" : "bookmark")
                }
                Menu {
                    Button("Compartilhar com comentário") { sharing = true }
                    if post.ehAutor == true {
                        Button("Editar publicação") { editing = true }
                        Button("Excluir publicação", role: .destructive) { confirmRemove = true }
                    }
                } label: { Label("Mais ações", systemImage: "ellipsis.circle") }.labelStyle(.iconOnly)
            }.buttonStyle(.borderless).disabled(!outcome.canSubmit).frame(minHeight: 44)
            if outcome == .sending { ProgressView("Atualizando publicação…") }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            if outcome == .uncertain { Button("Conferir estado da publicação") { Task { await reload() } } }
        }.padding(.vertical, 8)
        .onChange(of: initial.curtiu) { _, _ in updated = nil }
        .onChange(of: initial.salvou) { _, _ in updated = nil }
        .onChange(of: initial.conteudo) { _, _ in updated = nil }
        .onChange(of: initial.editadoEm) { _, _ in updated = nil }
        .sheet(isPresented: $editing) { NavigationStack { CommunityPostEditor(post: post) { onChange(); Task { await reload() } } } }
        .sheet(isPresented: $sharing) { NavigationStack { CommunityShareComposer(post: post, onSave: onChange) } }
        .confirmationDialog("Excluir esta publicação?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Excluir minha publicação", role: .destructive) { Task { await remove() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("A exclusão será enviada à comunidade e não poderá ser desfeita pelo aplicativo.") }
        }
    }
    private func remove() async {
        guard post.ehAutor == true, outcome.canSubmit else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: EmptyResponse = try await app.api.delete(["comunidade", "posts", post.id])
            guard app.contextID == context else { return }
            removed = true; onChange()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
    private func toggle(_ action: String) async {
        guard outcome.canSubmit else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: EmptyResponse = try await app.api.post(["comunidade", "posts", post.id, action])
            guard app.contextID == context else { return }
            // Re-read authoritative state: a timeout must not flip a toggle twice.
            await reload()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
    private func reload() async {
        let context = app.contextID
        do {
            let value: CommunityPost = try await app.api.get(["comunidade", "posts", post.id])
            guard app.contextID == context else { return }
            updated = value; outcome = .ready; error = nil
        } catch {
            guard app.contextID == context else { return }
            outcome = .uncertain; self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

private struct CommunityComposer: View {
    let onSave: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var visibility = "publico"
    @State private var reviewed = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("Compartilhe uma experiência profissional", text: $content, axis: .vertical).lineLimit(8...18)
                Picker("Quem pode ver", selection: $visibility) {
                    Text("Comunidade").tag("publico")
                    Text("Minha especialidade").tag("especialidade")
                }
                Text("\(content.count)/10.000 caracteres").font(.caption).foregroundStyle(.secondary)
            }.disabled(outcome == .sending)
            Section {
                Toggle("Revisei o texto e removi informações que identificam pacientes", isOn: $reviewed)
                Text("Publicações ficam visíveis aos profissionais conforme a opção escolhida. Não publique prontuários, nomes, documentos ou imagens identificáveis de pacientes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(outcome == .sending)
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button("Publicar na comunidade") { Task { await publish() } }
                    .disabled(!reviewed || content.trimmedOrNil == nil || content.count > 10_000 || !outcome.canSubmit)
            }
        }.navigationTitle("Nova publicação").inlineTitle()
            .toolbar { Button("Fechar") { dismiss() }.disabled(outcome == .sending) }
            .interactiveDismissDisabled(outcome == .sending)
    }
    private func publish() async {
        guard outcome.canSubmit, let content = content.trimmedOrNil, let user = app.user, reviewed else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: CommunityPost = try await app.api.post(["comunidade", "posts"], body: ["conteudo": content, "autorNome": user.nome, "tipo": "post", "visibilidade": visibility])
            guard app.contextID == context else { return }
            outcome = .succeeded; onSave(); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}
