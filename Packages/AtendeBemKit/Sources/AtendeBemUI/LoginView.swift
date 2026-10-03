import AtendeBemCore
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var ticket: String?
    @State private var isWorking = false
    @State private var error: String?
    @State private var sheet: LoginSheet?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password, code }
    private enum LoginSheet: String, Identifiable { case reset; var id: String { rawValue } }
    private var isValid: Bool {
        if ticket != nil { return code.utf8.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) } }
        return email.contains("@") && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 900 && !typeSize.isAccessibilitySize
                HStack(spacing: 24) {
                    if wide {
                        ScrollView {
                            WelcomeBrandPanel().padding(28)
                        }
                        .frame(maxWidth: 500)
                    }
                    signInForm(showsArtwork: !wide)
                        .frame(maxWidth: wide ? 520 : .infinity)
                }
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("AtendeBem")
            .inlineTitle()
            .sheet(item: $sheet) { _ in PasswordResetView(email: email) }
        }
        .tint(Brand.accent)
    }

    private func signInForm(showsArtwork: Bool) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if showsArtwork {
                        BrandLogoView().frame(maxWidth: 170, maxHeight: 36).accessibilityHidden(true)
                    }
                    Text(ticket == nil ? "Entre na sua clínica" : "Confirme seu acesso")
                        .font(.title2.weight(.semibold))
                    Text(ticket == nil ? "Sua agenda, seus pacientes e sua equipe, sempre por perto."
                         : "Uma etapa a mais para proteger as informações da sua conta.")
                        .foregroundStyle(.secondary)
                    if showsArtwork && ticket == nil && !typeSize.isAccessibilitySize {
                        WelcomeCareImage().frame(maxHeight: 140)
                            .frame(maxWidth: .infinity)
                    }
                }.padding(.vertical, 16)
            }
            if ticket != nil {
                Section {
                    TextField("Código de 6 dígitos", text: $code).otpInput().focused($focus, equals: .code)
                        .accessibilityIdentifier("login.mfa")
                } header: { Text("Verificação em duas etapas") }
                footer: { Text("Use o código do seu aplicativo autenticador.") }
            } else {
                Section("Sua conta") {
                    FormField(title: "E-mail") {
                        TextField("E-mail", text: $email).emailInput().focused($focus, equals: .email)
                            .submitLabel(.next).onSubmit { focus = .password }
                            .accessibilityIdentifier("login.email")
                    }
                    FormField(title: "Senha") {
                        SecureField("Senha", text: $password).textContentType(.password).focused($focus, equals: .password)
                            .submitLabel(.go).onSubmit { if isValid && !isWorking { Task { await submit() } } }
                            .accessibilityIdentifier("login.password")
                    }
                }
            }
            Section {
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                Button { Task { await submit() } } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView() }
                        Text(ticket == nil ? "Entrar" : "Verificar e entrar").fontWeight(.semibold)
                        Spacer()
                    }.frame(minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!isValid || isWorking)
                    .accessibilityIdentifier("login.submit")
                if ticket == nil {
                    Button("Esqueci minha senha") { sheet = .reset }.frame(minHeight: 44)
                } else {
                    Button("Usar outra conta") { ticket = nil; code = ""; error = nil; focus = .email }
                        .frame(minHeight: 44).disabled(isWorking)
                }
            }
            if ticket == nil {
                Section {
                    NavigationLink { WelcomeView() } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Não tem conta? Conheça o AtendeBem")
                                .font(.subheadline.weight(.semibold))
                            RegistrationOfferLabel()
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("login.discoverAtendeBem")
                }
            }
            Section {
                NavigationLink { PrivacySupportView() } label: {
                    Label("Privacidade e suporte", systemImage: "hand.raised")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func submit() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            if let ticket {
                try await app.verifyMFA(ticket: ticket, code: code)
                code = ""
            } else {
                ticket = try await app.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                password = ""
                if ticket != nil { focus = .code }
            }
        } catch {
            if error as? APIError == .http(401) {
                self.error = ticket == nil ? "Confira seu e-mail e sua senha." : "Código inválido ou expirado. Tente novamente."
            } else { self.error = message(for: error) }
        }
    }
}

struct PasswordResetView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var isWorking = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Confira seu e-mail", systemImage: "envelope")
                        Text("Se este e-mail estiver cadastrado, você receberá um link para redefinir sua senha.")
                        Button("Concluir") { dismiss() }.frame(minHeight: 44)
                    }
                } else {
                    Section {
                        FormField(title: "E-mail") { TextField("E-mail", text: $email).emailInput() }
                    }
                    Section {
                        if let error { Text(error).foregroundStyle(.red) }
                        Button("Enviar link") { Task { await send() } }
                            .disabled(!email.contains("@") || isWorking).frame(minHeight: 44)
                        if isWorking { ProgressView("Enviando…") }
                    }
                }
            }.formStyle(.grouped).navigationTitle("Recuperar acesso").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }

    private func send() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await app.api.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            sent = true
        } catch { self.error = message(for: error) }
    }
}

struct PasswordChangeView: View {
    @Environment(AppState.self) private var app
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var error: String?

    private var isValid: Bool {
        !current.isEmpty && new.count >= 12 && new != current && new == confirmation &&
        new.range(of: "[A-Za-z]", options: .regularExpression) != nil &&
        new.range(of: "[0-9]", options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Defina uma nova senha para continuar com segurança.") }
                Section {
                    FormField(title: "Senha atual") { SecureField("Senha atual", text: $current).textContentType(.password) }
                    FormField(title: "Nova senha") { SecureField("Nova senha", text: $new).textContentType(.newPassword) }
                    FormField(title: "Confirme a nova senha") { SecureField("Confirme a nova senha", text: $confirmation).textContentType(.newPassword) }
                } footer: { Text("Use pelo menos 12 caracteres, incluindo uma letra e um número.") }
                Section {
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Salvar nova senha") { Task { await save() } }
                        .disabled(!isValid || isWorking).frame(minHeight: 44)
                    if isWorking { ProgressView("Salvando…") }
                }
                Button("Sair", role: .destructive) { Task { await app.signOut() } }.disabled(isWorking)
            }.formStyle(.grouped).navigationTitle("Atualizar senha")
        }
    }

    private func save() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            _ = try await app.api.changePassword(current: current, new: new)
            current = ""; new = ""; confirmation = ""
            await app.loadContext()
        } catch { self.error = message(for: error); await app.checkSession(after: error) }
    }
}
