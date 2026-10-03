import AtendeBemCore
import SwiftUI

struct PatientTriageView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var triages = RemoteResource<[ClinicalTriage]>()

    var body: some View {
        Group {
            if app.user?.canReadClinicalData == true {
                List {
                    Section {
                        Text(patient.nome).font(.headline)
                        Text("Triagens registradas pela equipe, da mais recente para a mais antiga.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section {
                        ConnectionState(updatedAt: triages.updatedAt, error: triages.error, isLoading: triages.isLoading)
                        if triages.error != nil {
                            Text("Não foi possível atualizar as triagens. Os registros abaixo, se disponíveis, podem estar desatualizados.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Atualizar triagens") { Task { await load() } }
                        }
                        if let values = triages.value {
                            if values.isEmpty {
                                Text("Nenhuma triagem foi retornada. Consulte também as evoluções e os demais dados do prontuário.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(values) { triage in
                                NavigationLink {
                                    ClinicalTriageDetailView(patientName: patient.nome, triage: triage)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(triage.queixaPrincipal).font(.headline)
                                        Label("Risco registrado: \(triage.recordedRiskLabel)", systemImage: "tag")
                                            .font(.subheadline)
                                        ClinicalTimestamp(label: "Triada em", value: triage.triadaEm)
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                    } header: { Text("Histórico de triagens") }
                    footer: { Text("A classificação pertence ao momento da triagem. Esta consulta não reavalia o risco atual nem gera uma nova classificação.") }
                }
            } else { RestrictedState() }
        }
        .navigationTitle("Triagens").inlineTitle()
        .task(id: patient.id) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard app.user?.canReadClinicalData == true else { return }
        await triages.load(app: app) {
            let values: [ClinicalTriage] = try await app.api.get(["pacientes", patient.id, "triagens"])
            return try validatedTriages(values, patientID: patient.id)
        }
    }
}

private struct ClinicalTriageDetailView: View {
    let patientName: String
    let triage: ClinicalTriage

    var body: some View {
        List {
            Section {
                Text(patientName).font(.headline)
                ClinicalTimestamp(label: "Triada em", value: triage.triadaEm)
                ClinicalTimestamp(label: "Registrada em", value: triage.criadoEm)
            }
            Section("Queixa principal") {
                Text(triage.queixaPrincipal).textSelection(.enabled)
            }
            Section {
                LabeledContent("Classificação registrada", value: triage.recordedRiskLabel)
                if let observations = triage.observacoes?.trimmedOrNil {
                    Text(observations).textSelection(.enabled)
                } else { Text("Sem observações retornadas.").foregroundStyle(.secondary) }
            } header: { Text("Registro da equipe") }
            footer: { Text("Classificação informada na triagem, sem reavaliação automática do risco atual.") }
            Section {
                if triage.sinaisVitais.isEmpty {
                    Text("Nenhuma medida vinculada a esta triagem foi retornada.").foregroundStyle(.secondary)
                }
                ForEach(triage.sinaisVitais) { vital in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(vital.title).font(.headline)
                        Text("\(vital.valor.formatted(.number.precision(.fractionLength(0...6)))) \(vital.unidade?.trimmedOrNil ?? "(unidade não informada)")")
                            .textSelection(.enabled)
                        ClinicalTimestamp(label: "Medido em", value: vital.medidoEm)
                    }.padding(.vertical, 5)
                }
                if let imc = triage.imc {
                    LabeledContent("IMC registrado na triagem", value: imc.formatted(.number.precision(.fractionLength(0...6))))
                }
            } header: { Text("Medidas desta triagem") }
            footer: { Text("Somente medidas vinculadas a este registro. O IMC, quando disponível, é o valor calculado pelo serviço no momento da triagem.") }
            Section("Identificação do registro") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Identificador do profissional responsável").font(.caption).foregroundStyle(.secondary)
                    Text(triage.triadoPor).textSelection(.enabled)
                }
                if let encounterID = triage.atendimentoId {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Atendimento vinculado").font(.caption).foregroundStyle(.secondary)
                        Text(encounterID).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("Triagem registrada").inlineTitle()
    }
}
