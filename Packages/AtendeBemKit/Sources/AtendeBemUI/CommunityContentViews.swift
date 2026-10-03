import AtendeBemCore
import ImageIO
import SwiftUI

struct CommunityImageView: View {
    let mediaID: String
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<Data>()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = resource.value, let thumbnail = Self.thumbnail(data) {
                Image(decorative: thumbnail, scale: 1).resizable().scaledToFit()
                    .frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Imagem anexada à publicação; descrição não fornecida pelo autor")
            } else {
                Button { Task { await load() } } label: { Label("Carregar imagem da publicação", systemImage: "photo") }
                    .disabled(resource.isLoading)
            }
            if resource.isLoading { ProgressView("Carregando imagem…") }
            if let error = resource.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000, height <= 16_000, width * height <= 32_000_000 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1_600] as CFDictionary)
    }
    private func load() async {
        await resource.load(app: app) {
            let data = try await app.api.communityImage(id: mediaID)
            guard Self.thumbnail(data) != nil else { throw APIError.invalidResponse }
            return data
        }
    }
}

struct CommunityPostEditor: View {
    let post: CommunityPost
    let onSave: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var title: String
    @State private var visibility: String
    @State private var reviewed = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    init(post: CommunityPost, onSave: @escaping () -> Void) {
        self.post = post; self.onSave = onSave
        _text = State(initialValue: post.conteudo); _title = State(initialValue: post.titulo ?? "")
        _visibility = State(initialValue: post.visibilidade ?? "publico")
    }
    var body: some View {
        Form {
            Section {
                if post.titulo != nil { TextField("Título", text: $title) }
                TextField("Publicação", text: $text, axis: .vertical).lineLimit(6...16)
                Picker("Quem pode ver", selection: $visibility) {
                    Text("Comunidade").tag("publico"); Text("Minha especialidade").tag("especialidade")
                }
                Toggle("Revisei e removi informações que identificam pacientes", isOn: $reviewed)
            }.disabled(outcome == .sending)
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button("Salvar alterações") { Task { await save() } }
                    .disabled(!reviewed || !outcome.canSubmit || text.trimmedOrNil == nil || text.count > 10_000 ||
                              (post.titulo != nil && (title.count < 3 || title.count > 200)))
            }
        }.navigationTitle("Editar publicação").inlineTitle()
            .toolbar { Button("Fechar") { dismiss() }.disabled(outcome == .sending) }
            .interactiveDismissDisabled(outcome == .sending)
    }
    private func save() async {
        guard post.ehAutor == true, reviewed, outcome.canSubmit else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        var body = ["conteudo": text, "visibilidade": visibility]
        if post.titulo != nil { body["titulo"] = title }
        do {
            let _: CommunityPost = try await app.api.patch(["comunidade", "posts", post.id], body: body)
            guard app.contextID == context else { return }
            outcome = .succeeded; onSave(); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

struct CommunityShareComposer: View {
    let post: CommunityPost
    let onSave: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @State private var reviewed = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    var body: some View {
        Form {
            Section("Publicação original") { Text(post.autorNome).font(.headline); Text(post.conteudo).lineLimit(5) }
            Section {
                TextField("Seu comentário (opcional)", text: $comment, axis: .vertical).lineLimit(3...8)
                Text("\(comment.count)/2.000 caracteres").font(.caption).foregroundStyle(.secondary)
                Toggle("Conferi que não há dados identificáveis de pacientes", isOn: $reviewed)
            }.disabled(outcome == .sending)
            Section {
                WriteStatus(outcome: outcome, error: error)
                Button("Compartilhar na comunidade") { Task { await share() } }
                    .disabled(!reviewed || comment.count > 2_000 || !outcome.canSubmit)
            }
        }.navigationTitle("Compartilhar publicação").inlineTitle()
            .toolbar { Button("Fechar") { dismiss() }.disabled(outcome == .sending) }
            .interactiveDismissDisabled(outcome == .sending)
    }
    private func share() async {
        guard reviewed, outcome.canSubmit else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: CommunityPost = try await app.api.post(["comunidade", "posts", post.id, "compartilhar"], body: ["comentario": comment])
            guard app.contextID == context else { return }
            outcome = .succeeded; onSave(); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}
