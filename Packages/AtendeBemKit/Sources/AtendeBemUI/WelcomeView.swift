import SwiftUI

/// Product introduction stays native; registration is a separate, explicit action.
struct WelcomeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900 && !typeSize.isAccessibilitySize
            ScrollView {
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 40) {
                            WelcomeBrandPanel().frame(maxWidth: 500)
                            details.frame(maxWidth: 460)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 28) {
                            WelcomeBrandPanel()
                            details
                        }
                    }
                }
                .padding(wide ? 32 : 20)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Brand.background)
        .navigationTitle("Conheça o AtendeBem")
        .inlineTitle()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                RegistrationOfferLabel()
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink { RegistrationView() } label: {
                    Text("Criar conta grátis")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("welcome.createAccount")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .accessibilityIdentifier("welcome.introduction")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Da agenda ao prontuário, com a sua equipe.")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Para profissionais e clínicas que querem acompanhar o atendimento com as informações no lugar certo.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                WelcomeBenefit(symbol: "calendar", title: "Seu dia à mão",
                               detail: "Consulte horários, acompanhe a sala de espera e retome as consultas da sessão.")
                WelcomeBenefit(symbol: "heart.text.clipboard", title: "O contexto de cada paciente",
                               detail: "Acesse os registros disponíveis e prepare receitas, exames e anotações.")
                WelcomeBenefit(symbol: "sparkles", title: "A LARI no seu trabalho",
                               detail: "Abra tarefas e receba apoio para organizar informações, sempre com sua revisão.")
                WelcomeBenefit(symbol: "person.2", title: "Uma clínica, vários papéis",
                               detail: "Cada pessoa usa os acessos permitidos para seu perfil e sua clínica.")
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("Comece a conhecer o AtendeBem", systemImage: "gift")
                    .font(.headline)
                Text("Crie sua conta para conhecer o AtendeBem. Quem já faz parte de uma clínica deve entrar com a conta ou o convite da equipe.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Já tenho conta · Entrar") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("welcome.signIn")
            }
            .padding(20)
            .background(Brand.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))

            NavigationLink { PrivacySupportView() } label: {
                Label("Privacidade e suporte", systemImage: "hand.raised")
                    .frame(minHeight: 44)
            }
        }
    }
}

struct WelcomeBrandPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BrandLogoView().frame(maxWidth: 180, maxHeight: 38)
            Text("O cuidado continua aqui.")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("O AtendeBem da sua clínica, também no iPhone e no iPad.")
                .font(.title3).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            WelcomeCareImage()
            Text("A mesma conta. Os dados dos serviços da clínica. Os acessos do seu perfil.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WelcomeCareImage: View {
    var body: some View {
        Image("WelcomeCareHero", bundle: .module)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
    }
}

private struct WelcomeBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2).foregroundStyle(Brand.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
