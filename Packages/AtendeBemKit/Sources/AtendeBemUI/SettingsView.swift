import AtendeBemCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(WorkspacePreferences.self) private var preferences
    @State private var search = ""
    private var entries: [SettingEntry] {
        SettingEntry.allCases.filter { $0.allowed(app.user) && (search.isEmpty || $0.searchText.localizedStandardContains(search)) }
    }
    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    NavigationLink { AccountView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(Brand.accent).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.user?.nome ?? "Minha conta").font(.headline)
                                Text(app.clinicName).font(.subheadline).foregroundStyle(.secondary)
                                Text(app.user?.roleSummary ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
            ForEach(["Meu aplicativo", "Conta e clínica", "Documentos", "Ajuda e informações"], id: \.self) { group in
                let matches = entries.filter { $0.group == group }
                if !matches.isEmpty {
                    Section {
                        ForEach(matches) { entry in
                            NavigationLink { settingDestination(entry) } label: {
                                FeatureRow(title: entry.title, detail: entry == .appearance ? "\(preferences.appearance.title) · neste aparelho" : entry.detail, symbol: entry.symbol)
                            }.accessibilityIdentifier("settings.\(entry.rawValue)")
                        }
                    } header: { Text(group) } footer: {
                        if group == "Meu aplicativo" { Text("Preferências desta conta e clínica neste aparelho.") }
                        else if group == "Conta e clínica" { Text("Confira sua clínica ativa antes de atualizar informações compartilhadas.") }
                        else if group == "Documentos" { Text("Modelos e preferências usam os mesmos serviços da sua conta na web.") }
                    }
                }
            }
            if entries.isEmpty { ContentUnavailableView.search(text: search) }
        }
        .navigationTitle("Configurações")
        .inlineTitle()
        .searchable(text: $search, prompt: "Buscar ajuste ou informação")
    }
    @ViewBuilder private func settingDestination(_ entry: SettingEntry) -> some View {
        switch entry {
        case .workspace: WorkspaceCustomizationView()
        case .appearance: AppearanceSettingsView()
        case .account: AccountView()
        case .clinic: ClinicSettingsView()
        case .switchClinic: ClinicsView()
        case .certificate: ProfessionalCertificateView()
        case .prescription: PrescriptionSettingsView()
        case .templates: ClinicalTemplatesView()
        case .privacy: PrivacySupportView()
        case .aiConsent: AIConsentSettingsView()
        case .safety: ClinicalSafetyView()
        case .sync: SyncInfoView()
        case .updates: UpdatesView()
        }
    }
}

private enum SettingEntry: String, CaseIterable, Identifiable {
    case workspace, appearance, account, clinic, switchClinic, certificate, prescription, templates, privacy, aiConsent, safety, sync, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workspace: "Tela inicial e atalhos"; case .appearance: "Aparência e leitura"
        case .account: "Minha conta e acesso"; case .clinic: "Dados da clínica"; case .switchClinic: "Trocar clínica"
        case .certificate: "Certificado digital"; case .prescription: "Letra das receitas"; case .templates: "Modelos clínicos"
        case .privacy: "Privacidade e suporte"; case .safety: "Uso das informações"; case .sync: "Atualização dos dados"; case .updates: "Novidades"
        case .aiConsent: "Autorizações da LARI"
        }
    }
    var detail: String {
        switch self {
        case .workspace: "Escolha o que aparece primeiro"; case .appearance: "Sistema, claro ou escuro"
        case .account: "Seus dados, permissões e saída"; case .clinic: "Cadastro e contato da clínica ativa"; case .switchClinic: "Mude seu local de atendimento"
        case .certificate: "Situação e validade"; case .prescription: "Padrão compartilhado com a web"; case .templates: "Receitas, exames e orientações reutilizáveis"
        case .privacy: "Dados pessoais, políticas e ajuda"; case .safety: "Medicamentos e inteligência artificial"
        case .sync: "Conexão e atualizações"; case .updates: "O que mudou nesta versão"
        case .aiConsent: "Texto geral com IA · neste aparelho"
        }
    }
    var group: String {
        switch self {
        case .workspace, .appearance, .aiConsent: "Meu aplicativo"
        case .account, .clinic, .switchClinic: "Conta e clínica"
        case .certificate, .prescription, .templates: "Documentos"
        case .privacy, .safety, .sync, .updates: "Ajuda e informações"
        }
    }
    var symbol: String {
        switch self {
        case .workspace: "square.grid.2x2"; case .appearance: "textformat.size"; case .account: "person.crop.circle"
        case .clinic: "building.2"; case .switchClinic: "arrow.left.arrow.right"; case .certificate: "signature"
        case .prescription: "textformat"; case .templates: "doc.on.doc"; case .privacy: "hand.raised"
        case .safety: "cross.case"; case .sync: "arrow.triangle.2.circlepath"; case .updates: "sparkles"
        case .aiConsent: "hand.raised.square"
        }
    }
    var searchText: String {
        let synonyms: String
        switch self {
        case .appearance: synonyms = "tema escuro claro sistema visual contraste"
        case .prescription: synonyms = "fonte tamanho impressão imprimir papel receita receituário"
        case .certificate: synonyms = "assinar assinatura validade digital"
        case .workspace: synonyms = "início home ordenar ocultar personalizar abas"
        case .privacy: synonyms = "suporte contato termos políticas LGPD excluir dados ajuda"
        case .aiConsent: synonyms = "consentimento consentir revogar aceite autorização inteligencia artificial IA Anthropic Claude Google Gemini texto privacidade"
        case .account: synonyms = "perfil permissões sair logout"
        default: synonyms = ""
        }
        return title + " " + detail + " " + group + " " + synonyms
    }
    func allowed(_ user: User?) -> Bool {
        switch self { case .certificate, .prescription, .templates: user?.canPrescribe == true; default: true }
    }
}

private struct AIConsentSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    private var granted: Bool {
        app.aiConsent.hasGeneralTextConsent(userID: app.user?.id, clinicID: app.activeClinicID)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Conta", value: app.user?.nome ?? "Não identificada")
                LabeledContent("Clínica", value: app.clinicName)
                Label(granted ? "Texto geral autorizado neste aparelho" : "Texto geral não autorizado neste aparelho",
                      systemImage: granted ? "checkmark.circle" : "hand.raised")
                    .accessibilityIdentifier("settings.aiConsent.status")
                if granted {
                    Button("Revogar autorização de texto geral", role: .destructive) {
                        app.aiConsent.setGeneralTextConsent(false, userID: app.user?.id, clinicID: app.activeClinicID)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings.aiConsent.revoke")
                }
            } header: { Text("Conversa geral com a LARI") } footer: {
                Text("A escolha vale somente para esta conta e clínica neste aparelho. Depois de revogar, você precisará ler e autorizar novamente na LARI antes de enviar outro texto geral.")
            }
            Section("O que esta escolha abrange") {
                Text("Texto geral enviado ao serviço de IA do AtendeBem, com Anthropic (Claude) e Google (Gemini), conforme a solicitação. Mudanças no propósito ou nos provedores exigem nova autorização.")
                Text("Anotações de pacientes, consulta ao prontuário e gravações têm autorizações próprias. Elas não são lembradas por esta preferência.")
                Text("Revogar impede novos envios pelo aplicativo. Isso não apaga mensagens já recebidas nem interrompe um processamento que já começou no serviço.")
                NavigationLink { PrivacySupportView() } label: {
                    Label("Privacidade e canais de contato", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("Autorizações da LARI").inlineTitle()
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { app.aiConsent.reload() }
        }
    }
}

struct FeatureRow: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Brand.accent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 6).frame(minHeight: 44).accessibilityElement(children: .combine)
    }
}

struct AppearanceSettingsView: View {
    @Environment(WorkspacePreferences.self) private var preferences
    var body: some View {
        Form {
            Section {
                Picker("Aparência", selection: Binding(get: { preferences.appearance }, set: { preferences.setAppearance($0) })) {
                    ForEach(AppAppearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                }.pickerStyle(.inline)
            } footer: { Text("A escolha vale para esta conta e clínica neste aparelho. Não altera a aparência da web.") }
            Section("Leitura e acessibilidade") {
                Text("O aplicativo acompanha o tamanho de texto escolhido no sistema, inclusive os tamanhos de acessibilidade.")
                Text("VoiceOver, contraste e redução de movimento seguem os ajustes do aparelho.")
                Label("Prefira o tamanho de texto que for confortável para você.", systemImage: "textformat.size")
            }
        }.navigationTitle("Aparência e leitura").inlineTitle()
    }
}

struct PrescriptionSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<PrescriptionPreferences>()
    @State private var selection = PrescriptionFontSize.standard
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var saved = false
    @State private var loadedContext: UUID?
    @State private var confirmRestore = false
    private var current: PrescriptionPreferences? { loadedContext == app.contextID ? resource.value : nil }
    private var hasEdits: Bool { current.map { selection != $0.tamanhoFonte } ?? false }
    private var isBusy: Bool { outcome == .sending || resource.isLoading }
    private var canSave: Bool {
        app.user?.canPrescribe == true && current?.needsSave(selection) == true &&
        outcome.canSubmit && !isBusy && resource.error == nil
    }

    var body: some View {
        Form {
            if app.user?.canPrescribe == true {
                Section {
                    LabeledContent("Clínica", value: app.clinicName)
                    ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                }
                if let current {
                    Section {
                        Text(current.configurado ? "Seu padrão salvo: \(current.tamanhoFonte.title)." : "Você ainda não escolheu um padrão. Em uso: \(current.tamanhoFonte.title).")
                        Picker("Tamanho da letra", selection: $selection) {
                            ForEach(PrescriptionFontSize.allCases) { size in Text(size.title).tag(size) }
                        }.pickerStyle(.inline).disabled(isBusy || !outcome.canSubmit)
                            .accessibilityIdentifier("settings.prescription.fontSize")
                        if hasEdits { Label("Alteração ainda não salva", systemImage: "pencil").font(.footnote).foregroundStyle(.secondary) }
                    } header: { Text("Receitas legíveis") } footer: {
                        Text("Este padrão é usado também na web. Documentos já emitidos não são alterados. A composição final do PDF pode ajustar a letra para respeitar o formulário; confira antes de assinar.")
                    }
                }
                Section {
                    SettingsWriteStatus(outcome: outcome, error: error)
                    if saved && !hasEdits { Label("Preferência confirmada para suas receitas nesta clínica.", systemImage: "checkmark.circle").foregroundStyle(.green) }
                    if current != nil {
                        Button("Salvar preferência") { Task { await save() } }
                            .disabled(!canSave).accessibilityIdentifier("settings.prescription.save")
                    }
                    Button(resource.error != nil && current == nil ? "Tentar novamente" : "Conferir preferência do servidor") { Task { await load() } }
                        .disabled(isBusy).accessibilityIdentifier("settings.prescription.reload")
                    if hasEdits && outcome != .uncertain {
                        Button("Descartar alteração desta tela", role: .destructive) { confirmRestore = true }.disabled(isBusy)
                    }
                } footer: {
                    Text("Conferir o servidor mantém sua escolha nesta tela. Se o resultado de um salvamento estiver incerto, confira antes de tentar salvar novamente.")
                }
            } else { RestrictedState() }
        }
        .navigationTitle("Letra das receitas").inlineTitle()
        .modifier(SettingsEditorNavigation(hasEdits: hasEdits, isBusy: isBusy, uncertain: outcome == .uncertain))
        .task(id: app.contextID) {
            if loadedContext != app.contextID { clearDraft(); loadedContext = app.contextID }
            await load()
        }
        .onChange(of: app.user?.canPrescribe) { _, allowed in if allowed != true { clearDraft() } }
        .confirmationDialog("Descartar a escolha desta tela?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Usar o último padrão consultado", role: .destructive) {
                guard !isBusy, let current else { return }
                selection = current.tamanhoFonte; error = nil; saved = false
            }
            Button("Continuar editando", role: .cancel) {}
        }
    }

    private func clearDraft() {
        resource.clear(); selection = .standard; outcome = .ready; error = nil; saved = false; confirmRestore = false
    }

    private func load() async {
        guard app.user?.canPrescribe == true, !isBusy, loadedContext == app.contextID else { return }
        let context = app.contextID
        let preserveSelection = hasEdits || outcome == .uncertain
        let wasUncertain = outcome == .uncertain
        let previousUpdate = resource.updatedAt
        await resource.load(app: app) { try await app.api.get(["preferencias-receituario"]) }
        guard app.contextID == context, !Task.isCancelled else { return }
        guard app.user?.canPrescribe == true else { clearDraft(); return }
        guard let current = resource.value else {
            selection = .standard; outcome = .ready; error = nil; saved = false
            return
        }
        guard resource.error == nil, resource.updatedAt != previousUpdate else { return }
        if !preserveSelection { selection = current.tamanhoFonte }
        saved = wasUncertain && current.configurado && selection == current.tamanhoFonte
        outcome = .ready; error = nil
    }

    private func save() async {
        guard canSave else { return }
        let context = app.contextID
        let requested = selection
        outcome = .sending; saved = false; error = nil
        defer { if outcome == .sending { outcome = .ready } }
        do {
            let apiContext = await app.api.requestContextID()
            guard app.contextID == context, app.user?.canPrescribe == true else { return }
            let result: PrescriptionPreferences = try await app.api.put(["preferencias-receituario"], body: ["tamanhoFonte": requested.rawValue], expectedContext: apiContext)
            guard app.contextID == context, app.user?.canPrescribe == true else { return }
            guard result.configurado, result.tamanhoFonte == requested else { throw APIError.invalidResponse }
            resource.value = result; resource.updatedAt = .now; resource.error = nil
            selection = result.tamanhoFonte; outcome = .ready; saved = true
        } catch {
            guard app.contextID == context else { return }
            if SettingsWriteStatus.mustDiscard(after: error) { clearDraft() }
            else { outcome = WriteOutcome.afterFailure(error) }
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

struct ClinicSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<ClinicDetails>()
    @State private var name = ""
    @State private var phone = ""
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var saved = false
    @State private var loadedContext: UUID?
    @State private var confirmRestore = false
    private var canEdit: Bool { app.user?.hasAnyRole(["gestor", "admin"]) == true }
    private var current: ClinicDetails? { loadedContext == app.contextID ? resource.value : nil }
    private var isBusy: Bool { outcome == .sending || resource.isLoading }
    private var hasEdits: Bool {
        guard canEdit, let current else { return false }
        return name != current.nome || phone != (current.telefone ?? "")
    }
    private var validationError: String? {
        guard let current else { return nil }
        if name.trimmedOrNil == nil { return "Informe o nome da clínica para salvar." }
        if current.telefone != nil && phone.trimmedOrNil == nil { return "Informe um telefone. A remoção do contato ainda não está disponível." }
        return nil
    }
    private var changes: [String: String] {
        guard let current else { return [:] }
        var patch: [String: String] = [:]
        if let value = name.trimmedOrNil, value != current.nome { patch["nome"] = value }
        if let value = phone.trimmedOrNil, value != current.telefone { patch["telefone"] = value }
        return patch
    }
    private var canSave: Bool { canEdit && validationError == nil && !changes.isEmpty && outcome.canSubmit && !isBusy && resource.error == nil }

    var body: some View {
        Form {
            Section {
                LabeledContent("Clínica ativa", value: app.clinicName)
                ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
            }
            if let clinic = current {
                Section("Identificação e contato") {
                    if canEdit {
                        TextField("Nome da clínica", text: $name).accessibilityIdentifier("settings.clinic.name")
                        TextField("Telefone", text: $phone).textContentType(.telephoneNumber).accessibilityIdentifier("settings.clinic.phone")
                        if let validationError { Text(validationError).font(.footnote).foregroundStyle(.secondary) }
                        if hasEdits { Label("Alterações ainda não salvas", systemImage: "pencil").font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        LabeledContent("Nome", value: clinic.nome)
                        LabeledContent("Telefone", value: clinic.telefone ?? "Não informado")
                    }
                    LabeledContent("CNPJ", value: clinic.cnpj ?? "Não informado")
                    LabeledContent("CNES", value: clinic.cnes ?? "Não informado")
                }.disabled(isBusy || !outcome.canSubmit)
                Section("Endereço") {
                    Text([clinic.endereco.logradouro, clinic.endereco.cidade, clinic.endereco.uf, clinic.endereco.cep].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").trimmedOrNil ?? "Não informado")
                }
                if !clinic.especialidades.isEmpty { Section("Especialidades") { ForEach(clinic.especialidades, id: \.self) { Text($0) } } }
            }
            Section {
                SettingsWriteStatus(outcome: outcome, error: error)
                if saved && !hasEdits { Label("Dados confirmados na clínica.", systemImage: "checkmark.circle").foregroundStyle(.green) }
                if canEdit && current != nil {
                    Button("Salvar contato da clínica") { Task { await save() } }
                        .disabled(!canSave).accessibilityIdentifier("settings.clinic.save")
                }
                Button(resource.error != nil && current == nil ? "Tentar novamente" : "Conferir cadastro do servidor") { Task { await load() } }
                    .disabled(isBusy).accessibilityIdentifier("settings.clinic.reload")
                if hasEdits && outcome != .uncertain {
                    Button("Descartar alterações desta tela", role: .destructive) { confirmRestore = true }.disabled(isBusy)
                }
            } footer: {
                Text(canEdit
                     ? "Nome e telefone serão atualizados para toda a clínica, inclusive na web. Conferir o servidor mantém o que você está editando; os demais dados cadastrais são apenas consultados aqui."
                     : "Seu perfil pode consultar este cadastro. A alteração de nome e telefone é restrita à gestão da clínica.")
            }
        }
        .navigationTitle("Dados da clínica").inlineTitle()
        .modifier(SettingsEditorNavigation(hasEdits: hasEdits, isBusy: isBusy, uncertain: outcome == .uncertain))
        .task(id: app.contextID) {
            if loadedContext != app.contextID { clearDraft(); loadedContext = app.contextID }
            await load()
        }
        .onChange(of: canEdit) { _, allowed in
            if !allowed { applyCurrent(); outcome = .ready; error = nil; saved = false; confirmRestore = false }
        }
        .confirmationDialog("Descartar as alterações desta tela?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Usar o último cadastro consultado", role: .destructive) {
                guard !isBusy else { return }
                applyCurrent(); error = nil; saved = false
            }
            Button("Continuar editando", role: .cancel) {}
        }
    }

    private func applyCurrent() { name = current?.nome ?? ""; phone = current?.telefone ?? "" }
    private func clearDraft() {
        resource.clear(); name = ""; phone = ""; outcome = .ready; error = nil; saved = false; confirmRestore = false
    }

    private func load() async {
        guard let clinicID = app.activeClinicID, !isBusy, loadedContext == app.contextID else { return }
        let context = app.contextID
        // Preserve only fields the user edited. A refreshed contact from another
        // administrator must not become an unintended change in the next PATCH.
        let preserveName = canEdit && current.map { name != $0.nome } == true
        let preservePhone = canEdit && current.map { phone != ($0.telefone ?? "") } == true
        let wasUncertain = outcome == .uncertain
        let previousUpdate = resource.updatedAt
        await resource.load(app: app) {
            let result: ClinicDetails = try await app.api.get(["clinicas", clinicID])
            guard result.id == clinicID else { throw APIError.invalidResponse }
            return result
        }
        guard app.contextID == context, !Task.isCancelled else { return }
        guard resource.value != nil else {
            name = ""; phone = ""; outcome = .ready; error = nil; saved = false
            return
        }
        guard resource.error == nil, resource.updatedAt != previousUpdate else { return }
        if !canEdit || !preserveName { name = current?.nome ?? "" }
        if !canEdit || !preservePhone { phone = current?.telefone ?? "" }
        saved = wasUncertain && changes.isEmpty && validationError == nil
        outcome = .ready; error = nil
        if let clinic = current { app.clinics = app.clinics.map { $0.id == clinicID ? $0.renamed(clinic.nome) : $0 } }
    }

    private func save() async {
        guard canSave, let id = app.activeClinicID else { return }
        let context = app.contextID
        let patch = changes
        outcome = .sending; error = nil; saved = false
        defer { if outcome == .sending { outcome = .ready } }
        do {
            let apiContext = await app.api.requestContextID()
            guard app.contextID == context, canEdit else { return }
            let result: ClinicDetails = try await app.api.patch(["clinicas", id], body: patch, expectedContext: apiContext)
            guard app.contextID == context, canEdit else { return }
            guard result.id == id,
                  patch["nome"].map({ $0 == result.nome }) ?? true,
                  patch["telefone"].map({ $0 == result.telefone }) ?? true else { throw APIError.invalidResponse }
            resource.value = result; resource.updatedAt = .now; resource.error = nil
            applyCurrent(); outcome = .ready; saved = true
            app.clinics = app.clinics.map { $0.id == id ? $0.renamed(result.nome) : $0 }
        } catch {
            guard app.contextID == context else { return }
            if SettingsWriteStatus.mustDiscard(after: error) { clearDraft() }
            else { outcome = WriteOutcome.afterFailure(error) }
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

private struct SettingsWriteStatus: View {
    let outcome: WriteOutcome
    let error: String?
    var body: some View {
        if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("settings.write.error") }
        if outcome == .sending { ProgressView("Salvando…") }
        if outcome == .uncertain {
            Label("Não foi possível confirmar o salvamento. Confira o servidor antes de fazer outra alteração. Sua edição continua nesta tela.", systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("settings.write.uncertain")
        }
    }
    static func mustDiscard(after error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return [.http(401), .http(403), .http(404), .sessionExpired, .contextChanged].contains(api)
    }
}

private struct SettingsEditorNavigation: ViewModifier {
    let hasEdits: Bool
    let isBusy: Bool
    let uncertain: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLeave = false
    private var protectsExit: Bool { hasEdits || uncertain }
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(protectsExit || isBusy)
            .toolbar {
                if protectsExit || isBusy {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Voltar", systemImage: "chevron.backward") { confirmLeave = true }
                            .disabled(isBusy).accessibilityIdentifier("settings.back")
                    }
                }
            }
            .interactiveDismissDisabled(protectsExit || isBusy)
            .confirmationDialog(uncertain ? "Sair sem confirmar o salvamento?" : "Descartar as alterações desta tela?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Continuar nesta tela", role: .cancel) {}
                Button(uncertain ? "Sair e conferir depois" : "Descartar alterações e sair", role: .destructive) { if !isBusy { dismiss() } }
            } message: {
                Text(uncertain
                     ? "O servidor pode ter recebido a alteração. Ao voltar, confira o valor salvo antes de alterar novamente."
                     : "As alterações que você ainda não salvou serão perdidas. Os dados já salvos continuam disponíveis no sistema.")
            }
    }
}
