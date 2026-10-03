import AtendeBemCore
import SwiftUI

struct LARITaskContextSection: View {
    let command: String
    let explanation: String
    @Environment(AppState.self) private var app
    var body: some View {
        Section {
            LabeledContent("Clínica", value: app.clinicName)
            Text(explanation).font(.subheadline).foregroundStyle(.secondary)
            DisclosureGroup("Seu pedido") { Text(command).textSelection(.enabled) }
        }
    }
}

struct LARIPatientIdentity: View {
    let patient: Patient
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patient.nome).font(.headline)
            if let birth = patient.nascimento { Text("Nascimento: \(birth)") }
            if let cpf = patient.cpfMascarado { Text("CPF: \(cpf)") }
            if patient.nascimento == nil && patient.cpfMascarado == nil { Text("Confira a identidade com o cadastro antes de continuar.") }
        }.font(.caption).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LARIPatientTaskSection: View {
    @Bindable var lookup: LARIPatientLookup
    let editable: Bool
    let search: () async -> Void
    let select: (Patient) async -> Void
    let change: () -> Void
    @Environment(AppState.self) private var app
    var body: some View {
        Section {
            if let patient = lookup.patient {
                LARIPatientIdentity(patient: patient)
                Button("Escolher outro paciente", action: change).disabled(!editable)
            } else {
                TextField("Nome ou CPF do paciente", text: $lookup.query).disabled(!editable)
                Button("Buscar paciente") { Task { await search(); await recover() } }
                    .disabled(!editable || lookup.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                if lookup.searched && lookup.results.isEmpty { Text("Nenhum paciente foi retornado. Confira o nome e a clínica.").font(.footnote) }
                ForEach(lookup.results) { patient in
                    Button { Task { await select(patient); await recover() } } label: { LARIPatientIdentity(patient: patient) }.disabled(!editable)
                }
                if lookup.hasMore { Text("Existem mais resultados. Refine o nome para escolher a ficha correta.").font(.footnote) }
            }
            if lookup.busy { ProgressView("Consultando pacientes…") }
            if let error = lookup.error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: { Text("Paciente") } footer: { Text("A busca não seleciona ninguém automaticamente. Confirme a ficha mesmo quando houver apenas um resultado.") }
    }
    private func recover() async {
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }
}
