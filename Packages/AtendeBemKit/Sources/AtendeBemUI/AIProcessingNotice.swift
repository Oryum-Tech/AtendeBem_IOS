import AtendeBemCore
import SwiftUI

struct AIProcessingNotice: View {
    let includesPatient: Bool
    @Binding var agreed: Bool
    /// Explicit opt-in by the general chat. SOAP can omit pacienteId while still
    /// handling clinical notes, so includesPatient == false alone is insufficient.
    var rememberGeneralTextConsent = false
    @Environment(AppState.self) private var app

    private var remembersConsent: Bool { !includesPatient && rememberGeneralTextConsent }
    private var storedConsent: Bool {
        app.aiConsent.hasGeneralTextConsent(userID: app.user?.id, clinicID: app.activeClinicID)
    }
    private var permission: Binding<Bool> {
        Binding(get: { remembersConsent ? storedConsent : agreed }, set: { value in
            if remembersConsent {
                app.aiConsent.setGeneralTextConsent(value, userID: app.user?.id, clinicID: app.activeClinicID)
                agreed = storedConsent
            } else { agreed = value }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Antes de usar a LARI").font(.headline)
            Text("O texto digitado será enviado ao serviço de inteligência artificial do AtendeBem para gerar uma resposta. O serviço utiliza Anthropic (Claude) e Google (Gemini), conforme a configuração da solicitação. Esses provedores podem receber o texto para processá-lo. Confira as condições de privacidade da sua clínica antes de continuar.")
            if includesPatient {
                Text("Nesta tela, o identificador do paciente selecionado também será enviado para contextualizar a solicitação. Use apenas informações que você está autorizado a compartilhar.")
            }
            Text("As respostas podem conter erros. Revise as informações antes de qualquer uso clínico.")
            NavigationLink { PrivacySupportView() } label: {
                Label("Privacidade e canais de contato", systemImage: "hand.raised")
            }
            Toggle(remembersConsent ? "Autorizar texto geral e lembrar neste aparelho" : "Autorizo o envio do texto para este processamento",
                   isOn: permission)
                .disabled(remembersConsent && (app.user?.id == nil || app.activeClinicID == nil))
                .accessibilityIdentifier(remembersConsent ? "aiConsent.generalText" : "aiConsent.thisProcessing")
            if remembersConsent {
                Text("A escolha vale para sua conta nesta clínica e neste aparelho. Revogue quando quiser em Configurações → Autorizações da LARI. Dados de pacientes e gravações continuam pedindo autorização própria.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote).padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: storedConsent, initial: true) { _, value in
            if remembersConsent { agreed = value }
        }
        .onChange(of: app.contextID) { _, _ in
            agreed = remembersConsent ? storedConsent : false
        }
        .onChange(of: includesPatient) { _, _ in agreed = remembersConsent ? storedConsent : false }
        .onChange(of: rememberGeneralTextConsent) { _, _ in agreed = remembersConsent ? storedConsent : false }
    }
}
