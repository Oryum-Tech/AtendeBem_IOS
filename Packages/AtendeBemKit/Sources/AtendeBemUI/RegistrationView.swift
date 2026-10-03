import AtendeBemCore
import SwiftUI

/// The shared client retains uncertain/completed outcomes when this view closes.
/// Passwords remain local to this screen and are cleared when leaving it.
struct RegistrationView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var clinicName = ""
    @State private var responsibleName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var profession: RegistrationProfession = .medico
    @State private var professionalRegistration = ""
    @State private var specialty = ""
    @State private var acceptedTerms = false
    @State private var plans: [RegistrationPlan] = []
    @State private var selectedPlanID: String?
    @State private var loadingPlans = false
    @State private var planError: String?
    @State private var submissionState: RegistrationSubmissionState?
    @State private var error: String?
    @State private var sheet: AccessSheet?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case clinic, name, email, password, confirmation }
    private enum AccessSheet: String, Identifiable {
        case login, recovery
        var id: String { rawValue }
    }

    private var trialPlans: [RegistrationPlan] { plans.filter { $0.trialDias >= 14 && $0.semCartao } }
    private var selectedPlan: RegistrationPlan? { trialPlans.first { $0.id == selectedPlanID } }
    private var canSubmit: Bool {
        submissionState == .ready && selectedPlan != nil && acceptedTerms && !loadingPlans
            && !clinicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !responsibleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty && password == confirmation
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900 && !typeSize.isAccessibilitySize
            HStack(alignment: .top, spacing: 24) {
                if wide {
                    ScrollView { RegistrationContextPanel().padding(28) }
                        .frame(maxWidth: 340)
                }
                registrationForm
                    .frame(maxWidth: wide ? 620 : .infinity)
            }
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Criar conta")
        .inlineTitle()
        .tint(Brand.accent)
        .accessibilityIdentifier("registration.screen")
        .task {
            await updateSubmissionState()
            if submissionState == .ready { await loadPlans() }
        }
        .onDisappear { clearPasswords() }
        .onChange(of: profession) { _, _ in professionalRegistration = "" }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .login: RegistrationSignInSheet()
            case .recovery: PasswordResetView(email: email)
            }
        }
    }

    private var registrationForm: some View {
        Form {
            switch submissionState {
            case nil:
                Section { ProgressView("Preparando cadastro…") }
            case .completed:
                resultSection(completed: true)
            case .outcomeUnknown:
                resultSection(completed: false)
            case .submitting:
                Section {
                    ProgressView("Confirmando seu cadastro…")
                    Text("O pedido já foi enviado. Vamos confirmar o resultado antes de qualquer nova tentativa.")
                        .foregroundStyle(.secondary)
                    Button("Verificar resultado") { Task { await updateSubmissionState() } }
                        .frame(minHeight: 44)
                }
            case .ready:
                introductionSection
                identitySection
                professionalSection
                passwordSection
                trialSection
                termsSection
                submitSection
            }
            Section {
                NavigationLink { PrivacySupportView() } label: {
                    Label("Privacidade e suporte", systemImage: "hand.raised")
                        .frame(minHeight: 44)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var introductionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Um novo espaço para seu atendimento")
                    .font(.title2.weight(.semibold))
                Text("Cadastre a clínica ou o consultório pelo qual você é responsável. Se sua equipe já usa o AtendeBem, entre com sua conta ou siga o convite recebido.")
                    .foregroundStyle(.secondary)
            }.padding(.vertical, 8)
            Button("Já tenho conta · Entrar") { openAccess(.login) }.frame(minHeight: 44)
                .accessibilityIdentifier("registration.existingAccount")
        }
    }

    private var identitySection: some View {
        Section("Você e seu espaço") {
            FormField(title: "Clínica ou consultório") {
                TextField("Nome da clínica ou consultório", text: $clinicName)
                    .focused($focusedField, equals: .clinic)
                    .submitLabel(.next).onSubmit { focusedField = .name }
                    .accessibilityIdentifier("registration.clinicName")
            }
            FormField(title: "Seu nome") {
                TextField("Nome completo", text: $responsibleName).textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next).onSubmit { focusedField = .email }
                    .accessibilityIdentifier("registration.name")
            }
            FormField(title: "E-mail") {
                TextField("E-mail de acesso", text: $email).emailInput()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next).onSubmit { focusedField = .password }
                    .accessibilityIdentifier("registration.email")
            }
        }
    }

    private var professionalSection: some View {
        Section {
            Picker("Área de atuação", selection: $profession) {
                ForEach(RegistrationProfession.allCases) { value in Text(value.title).tag(value) }
            }.accessibilityIdentifier("registration.profession")
            if let council = profession.registrationLabel {
                FormField(title: "\(council) · opcional") {
                    TextField("Registro no conselho", text: $professionalRegistration)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("registration.professionalRegistration")
                }
            }
            FormField(title: "Especialidade · opcional") {
                TextField("Sua especialidade", text: $specialty)
                    .accessibilityIdentifier("registration.specialty")
            }
        } header: { Text("Sua atuação") }
        footer: {
            if profession == .residente {
                Text("O perfil de residência é acadêmico. Permissões assistenciais dependem do vínculo e do perfil atribuído pela instituição.")
            } else {
                Text("Informe apenas registros que pertençam a você. É possível concluir o cadastro sem preencher o conselho agora.")
            }
        }
    }

    private var passwordSection: some View {
        Section {
            FormField(title: "Senha") {
                SecureField("Crie uma senha", text: $password).textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next).onSubmit { focusedField = .confirmation }
                    .accessibilityIdentifier("registration.password")
            }
            FormField(title: "Confirme a senha") {
                SecureField("Repita sua senha", text: $confirmation).textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmation)
                    .submitLabel(.done).onSubmit { focusedField = nil }
                    .accessibilityIdentifier("registration.passwordConfirmation")
            }
            if !confirmation.isEmpty && password != confirmation {
                Label("As senhas precisam ser iguais.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.red)
            }
        } header: { Text("Proteja seu acesso") }
        footer: { Text("Use ao menos 8 caracteres, incluindo uma letra e um número. Sua senha será usada somente para o cadastro e apagada desta tela ao sair.") }
    }

    private var trialSection: some View {
        Section("Seu período para experimentar") {
            if loadingPlans {
                ProgressView("Consultando as condições disponíveis…")
            } else if let planError {
                Label(planError, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Button("Consultar novamente") { Task { await loadPlans() } }.frame(minHeight: 44)
            } else if trialPlans.isEmpty {
                Text("Não foi possível confirmar uma oferta de pelo menos 14 dias sem cartão. O cadastro gratuito fica disponível quando essa condição for confirmada pelo serviço.")
                    .foregroundStyle(.secondary)
                Button("Atualizar condições") { Task { await loadPlans() } }.frame(minHeight: 44)
            } else {
                Picker("Plano", selection: $selectedPlanID) {
                    Text("Selecione um plano").tag(String?.none)
                    ForEach(trialPlans) { plan in Text(plan.nome).tag(Optional(plan.id)) }
                }.accessibilityIdentifier("registration.plan")
                if let plan = selectedPlan {
                    Label(plan.trialDescription, systemImage: "gift")
                        .font(.headline).foregroundStyle(Brand.accent)
                    Text("Este cadastro inicia o período de experiência do plano escolhido. Não há cobrança ou contratação de plano pago nesta tela.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var termsSection: some View {
        Section {
            Button { acceptedTerms.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.title3).foregroundStyle(Brand.accent).accessibilityHidden(true)
                    Text("Li e aceito os Termos de Uso e estou ciente da Política de Privacidade.")
                        .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aceitar os Termos de Uso e ciência da Política de Privacidade")
            .accessibilityValue(acceptedTerms ? "Marcado" : "Não marcado")
            .accessibilityIdentifier("registration.terms")
            Link("Ler Termos de Uso", destination: URL(string: "https://www.atendebem.io/legal/termos/")!)
                .frame(minHeight: 44)
            NavigationLink { PrivacySupportView() } label: {
                Text("Ler sobre privacidade").frame(minHeight: 44)
            }
        }
    }

    private var submitSection: some View {
        Section {
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red).accessibilityIdentifier("registration.error")
            }
            Button { Task { await submit() } } label: {
                Text(selectedPlan == nil ? "Criar conta" : "Criar conta grátis")
                    .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .accessibilityIdentifier("registration.submit")
        } footer: { Text("Ao concluir, entre com seu e-mail e sua senha. Se sua conta usa verificação em duas etapas, ela continuará sendo solicitada.") }
    }

    private func resultSection(completed: Bool) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label(completed ? "Sua conta está pronta para entrar" : "Vamos conferir seu acesso",
                      systemImage: completed ? "checkmark.circle" : "questionmark.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(completed ? Brand.accent : .primary)
                Text(completed
                     ? "O serviço confirmou o cadastro. Entre com seu e-mail e sua senha para acessar a clínica."
                     : "O cadastro pode ter sido concluído, mas a confirmação não chegou. Entre na sua conta ou recupere o acesso antes de tentar criar outra clínica.")
                    .foregroundStyle(.secondary)
            }.padding(.vertical, 12)
            Button(completed ? "Entrar na minha conta" : "Conferir meu acesso") { openAccess(.login) }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
            Button("Recuperar acesso") { openAccess(.recovery) }.frame(minHeight: 44)
        }
        .accessibilityIdentifier(completed ? "registration.completed" : "registration.uncertain")
    }

    private func loadPlans() async {
        guard !loadingPlans else { return }
        loadingPlans = true
        planError = nil
        defer { loadingPlans = false }
        do {
            let values = try await app.registration.plans()
            try Task.checkCancellation()
            plans = values
            if !trialPlans.contains(where: { $0.id == selectedPlanID }) {
                selectedPlanID = trialPlans.count == 1 ? trialPlans.first?.id : nil
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                plans = []
                selectedPlanID = nil
                planError = "Não foi possível consultar as condições do período gratuito. Tente novamente quando estiver conectado."
            }
        }
    }

    private func submit() async {
        guard canSubmit, let plan = selectedPlan else { return }
        focusedField = nil
        error = nil
        do {
            let request = try RegistrationRequest(clinicName: clinicName, responsibleName: responsibleName,
                email: email, password: password, profession: profession,
                professionalRegistration: professionalRegistration, specialty: specialty, planID: plan.id)
            submissionState = .submitting
            defer { clearPasswords() }
            _ = try await app.registration.register(request)
            await updateSubmissionState()
        } catch {
            await updateSubmissionState()
            self.error = (error as? RegistrationError)?.localizedDescription
                ?? "Não foi possível confirmar o cadastro. Confira seu acesso antes de tentar novamente."
        }
    }

    private func updateSubmissionState() async { submissionState = await app.registration.state }
    private func clearPasswords() { password = ""; confirmation = "" }
    private func openAccess(_ destination: AccessSheet) {
        clearPasswords()
        focusedField = nil
        sheet = destination
    }
}

private struct RegistrationContextPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BrandLogoView().frame(maxWidth: 190, maxHeight: 44)
            Text("Mais tempo para cuidar.").font(.largeTitle.weight(.semibold))
            Text("Comece pelo seu espaço de atendimento. Depois, organize os acessos da equipe conforme cada função.")
                .font(.title3).foregroundStyle(.secondary)
            Label("Clínica e consultório", systemImage: "building.2")
            Label("Acesso por perfil profissional", systemImage: "person.badge.key")
            Label("Condições consultadas no cadastro", systemImage: "checkmark.shield")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 32)
    }
}

private struct RegistrationSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Fechar") { dismiss() }.frame(minHeight: 44)
            }.padding(.horizontal)
            LoginView()
        }
    }
}
