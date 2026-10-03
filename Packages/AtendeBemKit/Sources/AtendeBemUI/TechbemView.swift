import SwiftUI

/// Patient-app discovery. Opening or sharing these public links does not connect accounts.
struct TechbemView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    private let appStoreURL = URL(string: "https://apps.apple.com/br/app/meu-prontu%C3%A1rio-rem%C3%A9dios/id6777473301")!
    private let websiteURL = URL(string: "https://meuprontuarioapp.com")!

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850 && !typeSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    introduction
                    if wide {
                        HStack(alignment: .top, spacing: 28) {
                            productCard.frame(maxWidth: 430)
                            patientBenefits.frame(maxWidth: .infinity)
                        }
                    } else {
                        productCard
                        patientBenefits
                    }
                    shareCard
                }
                .padding(wide ? 32 : 20)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Brand.background)
        .tint(Brand.accent)
        .navigationTitle("Techbem")
        .inlineTitle()
        .accessibilityIdentifier("techbem.overview")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("O cuidado também faz parte da rotina.")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Conheça o Meu Prontuário, da Techbem: um aplicativo para o paciente organizar suas informações de saúde.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var productCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "heart.text.clipboard")
                .font(.largeTitle)
                .foregroundStyle(Brand.accent)
                .padding(16)
                .background(Brand.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Meu Prontuário: Remédios")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Receitas, exames e lembretes, por perto no dia a dia.")
                    .foregroundStyle(.secondary)
            }
            Link(destination: appStoreURL) {
                Label("Conhecer na App Store", systemImage: "arrow.up.right.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Abre a página do Meu Prontuário na App Store.")
            .accessibilityIdentifier("techbem.meuProntuario.appStore")

            Link(destination: websiteURL) {
                Label("Visitar o site", systemImage: "globe")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Abre meuprontuarioapp.com no navegador.")
            .accessibilityIdentifier("techbem.meuProntuario.website")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
    }

    private var patientBenefits: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Para levar à próxima consulta")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            TechbemBenefit(symbol: "doc.text", title: "Receitas organizadas",
                           detail: "O paciente pode guardar fotos e PDFs de suas receitas para consultar depois.")
            TechbemBenefit(symbol: "folder", title: "Exames à mão",
                           detail: "Exames, laudos e atestados reunidos para encontrar quando precisar.")
            TechbemBenefit(symbol: "bell.badge", title: "Lembretes de medicamentos",
                           detail: "Apoio para organizar horários de uso conforme a prescrição recebida.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apresente ao seu paciente")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Compartilhe a página do aplicativo para que ele conheça os recursos e escolha como organizar suas informações.")
                .foregroundStyle(.secondary)
            ShareLink(item: appStoreURL,
                      subject: Text("Conheça o Meu Prontuário"),
                      message: Text("Meu Prontuário: um aplicativo para organizar receitas, exames e lembretes de medicamentos.")) {
                Label("Compartilhar o aplicativo", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Abre as opções de compartilhamento com o link da App Store. Não inclui dados de pacientes.")
            .accessibilityIdentifier("techbem.meuProntuario.share")
            Text("O paciente mantém a escolha sobre quais informações compartilhar com sua equipe de cuidado.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct TechbemBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Brand.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
