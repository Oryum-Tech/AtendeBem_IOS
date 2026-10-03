import AtendeBemCore
import SwiftUI

struct ProfessionalCertificateView: View {
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<ProfessionalCertificate>()
    var body: some View {
        List {
            Section {
                ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                if resource.error != nil { Button("Tentar novamente") { Task { await load() } } }
            }
            if let certificate = resource.value {
                if certificate.cadastrado {
                    Section("Certificado vinculado à sua conta") {
                        Label(certificate.readyForSignature ? "Disponível para solicitar assinatura" : "Certificado requer atenção",
                              systemImage: certificate.readyForSignature ? "checkmark.seal" : "exclamationmark.triangle")
                        if let value = certificate.titular { LabeledContent("Titular", value: value) }
                        if let value = certificate.emissor { LabeledContent("Emissor", value: value) }
                        if let value = certificate.crm { LabeledContent("Registro informado", value: value) }
                        if let value = certificate.tipo { LabeledContent("Tipo", value: value) }
                        if let value = certificate.status { LabeledContent("Situação", value: statusLabel(value)) }
                        if let raw = certificate.validadeFim, let date = ClinicClock.parseInstant(raw) {
                            LabeledContent("Validade") { Text(date, format: .dateTime.day().month().year()).environment(\.timeZone, ClinicClock.timeZone) }
                        }
                        if let days = certificate.diasRestantes { LabeledContent("Dias restantes", value: String(days)) }
                        if certificate.isTeste == true { Text("Certificado de teste: não deve ser usado para emitir documentos reais.").foregroundStyle(.orange) }
                    }
                } else {
                    Section { ContentUnavailableView("Nenhum certificado cadastrado", systemImage: "signature",
                        description: Text("Vincule seu certificado pelo AtendeBem web para solicitar a assinatura de documentos.")) }
                }
            }
            Section("Como funciona") {
                Text("A situação é consultada no mesmo serviço usado pela web. A assinatura é feita pelo serviço após sua confirmação; o certificado e sua senha não são baixados pelo app.")
                Text("Para cadastrar ou renovar seu certificado, use a área de certificado digital do AtendeBem web. Depois, atualize esta tela.")
                Text("Confira o documento final e os dados de verificação da assinatura antes de utilizá-lo.")
            }
        }.navigationTitle("Meu certificado digital").inlineTitle()
            .task { await load() }.refreshable { await load() }
    }
    private func load() async { await resource.load(app: app) { try await app.api.get(["certificados-medico"]) } }
    private func statusLabel(_ value: String) -> String {
        ["valido": "Válido", "expirando": "Próximo do vencimento", "expirado": "Vencido", "inativo": "Inativo"][value] ?? "Situação não reconhecida"
    }
}
