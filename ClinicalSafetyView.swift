import SwiftUI

struct ClinicalSafetyView: View {
    var body: some View {
        List {
            Section("Uso das informações") {
                Text("Este aplicativo apresenta dados clínicos de forma responsável para apoiar decisões.")
                Text("As informações exibidas não substituem o julgamento profissional.")
            }
            Section("Boas práticas") {
                Label("Confirme a identidade do paciente", systemImage: "checkmark.shield")
                Label("Revise alergias e alertas", systemImage: "exclamationmark.triangle")
                Label("Mantenha dados atualizados", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .navigationTitle("Uso das informações")
        .inlineTitle()
    }
}
