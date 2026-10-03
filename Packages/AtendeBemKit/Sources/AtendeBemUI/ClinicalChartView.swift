import AtendeBemCore
import SwiftUI

/// Reads each clinical source independently: a failed service must never look like a negative history.
struct PatientClinicalChartView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var problems = RemoteResource<[ClinicalProblem]>()
    @State private var vitals = RemoteResource<[ClinicalVital]>()
    @State private var medications = RemoteResource<[ClinicalMedication]>()
    @State private var reported = RemoteResource<ReportedMedicationList>()

    var body: some View {
        Group {
            if app.user?.canReadClinicalData == true {
                List {
                    Section {
                        Text(patient.nome).font(.headline)
                        NavigationLink { PatientTriageView(patient: patient) } label: {
                            Label("Triagens e preparação da consulta", systemImage: "clipboard")
                        }
                    }
                    problemsSection
                    medicationsSection
                    reportedSection
                    vitalsSection
                    PatientHistorySection(patientID: patient.id)
                }
            } else { RestrictedState() }
        }.navigationTitle("Dados do prontuário").inlineTitle()
            .task(id: patient.id) { await load() }
            .refreshable { await load() }
    }

    private var problemsSection: some View {
        Section {
            ChartSourceState(resource: problems) { Task { await loadProblems() } }
            if let values = problems.value {
                if values.isEmpty { Text("Nenhum problema retornado nesta consulta. Isso não exclui condições registradas em outras fontes.").foregroundStyle(.secondary) }
                ForEach(values) { item in
                    DisclosureGroup {
                        if let code = item.cid10 { LabeledContent("CID-10", value: code) }
                        ClinicalTimestamp(label: "Início informado", value: item.inicioEm)
                        if let resolved = item.resolvidoEm { ClinicalTimestamp(label: "Resolução registrada", value: resolved) }
                        ClinicalTimestamp(label: "Registro no prontuário", value: item.criadoEm)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("#\(item.numero) · \(item.descricao)").font(.headline)
                            Text(["ativo": "Ativo", "resolvido": "Resolvido", "inativo": "Inativo"][item.status] ?? item.status)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: { Label("Problemas clínicos", systemImage: "list.clipboard") }
    }

    private var medicationsSection: some View {
        Section {
            ChartSourceState(resource: medications) { Task { await loadMedications() } }
            if let values = medications.value {
                if values.isEmpty { Text("Nenhuma medicação retornada desta lista do prontuário. Confira também receitas e relatos do paciente.").foregroundStyle(.secondary) }
                ForEach(values) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.nome).font(.headline)
                        Text(item.ativo ? "Ativa no prontuário" : "Inativa no prontuário").font(.subheadline)
                        Text(item.posologia?.trimmedOrNil ?? "Posologia não informada").textSelection(.enabled)
                        ClinicalTimestamp(label: "Registrada em", value: item.criadoEm)
                    }.padding(.vertical, 5)
                }
            }
        } header: { Label("Medicações do prontuário", systemImage: "pills") }
        footer: { Text("Esta lista clínica é distinta dos relatos do paciente e dos documentos de receita. A exibição não confirma adesão nem renova prescrições.") }
    }

    private var reportedSection: some View {
        Section {
            ChartSourceState(resource: reported) { Task { await loadReported() } }
            if let value = reported.value {
                Text("\(value.cobertura.ativos) relatos ativos; \(value.cobertura.comPrincipioAtivo) com princípio ativo identificado.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !value.cobertura.semPrincipioAtivo.isEmpty {
                    Label("Sem princípio ativo identificado: \(value.cobertura.semPrincipioAtivo.joined(separator: ", ")).", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
                if value.medicamentos.isEmpty { Text("Nenhum medicamento relatado retornado. Isso não significa que o paciente não use medicamentos.").foregroundStyle(.secondary) }
                ForEach(value.medicamentos) { item in ReportedMedicationRow(item: item) }
            }
        } header: { Label("Medicamentos relatados pelo paciente", systemImage: "person.text.rectangle") }
        footer: { Text("Conteúdo informado pelo paciente. Esta tela não executa checagem de interações e não atesta segurança, adesão ou validação profissional do relato.") }
    }

    private var vitalsSection: some View {
        Section {
            ChartSourceState(resource: vitals) { Task { await loadVitals() } }
            if let values = vitals.value {
                if values.isEmpty { Text("Nenhuma medição retornada. Ausência de registro não indica sinais vitais normais.").foregroundStyle(.secondary) }
                // The API returns measurements chronologically. Reverse only presentation, without combining different instants.
                ForEach(Array(values.reversed())) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.headline)
                        Text("\(item.valor.formatted(.number.precision(.fractionLength(0...6)))) \(item.unidade?.trimmedOrNil ?? "(unidade não informada)")")
                            .textSelection(.enabled)
                        ClinicalTimestamp(label: "Medido em", value: item.medidoEm)
                    }.padding(.vertical, 5)
                }
            }
        } header: { Label("Sinais vitais e medidas", systemImage: "waveform.path.ecg") }
        footer: { Text("Valores e unidades retornados pelo prontuário. Medições de momentos diferentes permanecem separadas; não há classificação automática de normalidade.") }
    }

    private func load() async {
        guard app.user?.canReadClinicalData == true else { return }
        async let p: Void = loadProblems()
        async let m: Void = loadMedications()
        async let r: Void = loadReported()
        async let v: Void = loadVitals()
        _ = await (p, m, r, v)
    }
    private func loadProblems() async {
        guard app.user?.canReadClinicalData == true else { return }
        await problems.load(app: app) {
            let values: [ClinicalProblem] = try await app.api.get(["pacientes", patient.id, "problemas"])
            return try validatedChartEntries(values, patientID: patient.id)
        }
    }
    private func loadVitals() async {
        guard app.user?.canReadClinicalData == true else { return }
        await vitals.load(app: app) {
            let values: [ClinicalVital] = try await app.api.get(["pacientes", patient.id, "sinais-vitais"])
            return try validatedChartEntries(values, patientID: patient.id)
        }
    }
    private func loadMedications() async {
        guard app.user?.canReadClinicalData == true else { return }
        await medications.load(app: app) {
            let values: [ClinicalMedication] = try await app.api.get(["pacientes", patient.id, "medicacoes"])
            return try validatedChartEntries(values, patientID: patient.id)
        }
    }
    private func loadReported() async {
        guard app.user?.canReadClinicalData == true else { return }
        await reported.load(app: app) {
            let value: ReportedMedicationList = try await app.api.get(["pacientes", patient.id, "medicamentos-em-uso"])
            _ = try validatedChartEntries(value.medicamentos, patientID: patient.id)
            guard value.medicamentos.allSatisfy({ $0.procedencia.relatadoPor == "paciente" }) else { throw APIError.invalidResponse }
            return value
        }
    }
}

private struct ChartSourceState<Value: Sendable>: View {
    let resource: RemoteResource<Value>
    let retry: () -> Void
    var body: some View {
        ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
        if resource.error != nil {
            Text("Esta fonte não pôde ser atualizada. Os registros disponíveis abaixo podem estar desatualizados.").font(.footnote).foregroundStyle(.secondary)
            Button("Atualizar esta fonte", action: retry)
        }
    }
}

struct ClinicalTimestamp: View {
    let label: String
    let value: String?
    var body: some View {
        if let value, let date = ClinicClock.parseInstant(value) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                Spacer()
                Text(date, format: .dateTime.day().month().year().hour().minute())
                    .environment(\.timeZone, ClinicClock.timeZone).multilineTextAlignment(.trailing)
            }.font(.caption).foregroundStyle(.secondary)
        } else if value?.trimmedOrNil != nil {
            Text("\(label): data inválida no registro retornado").font(.caption).foregroundStyle(.secondary)
        } else { Text("\(label): não informado").font(.caption).foregroundStyle(.secondary) }
    }
}

private struct ReportedMedicationRow: View {
    let item: ReportedMedication
    var body: some View {
        DisclosureGroup {
            Text("Relatado pelo paciente; não equivale a uma prescrição emitida pela clínica.").font(.footnote)
            chartField("Concentração", item.concentracao)
            chartField("Forma", item.forma)
            chartField("Via", item.via)
            LabeledContent("Uso relatado", value: item.scheduleLabel)
            LabeledContent("Unidades por tomada", value: item.unidadesPorTomada.map { $0.formatted() } ?? "Não informado")
            chartField("Princípio ativo", item.identificacao.principioAtivo)
            if !item.identificacao.entraNaChecagem { Text("O serviço não inclui este item na checagem por princípio ativo.").font(.footnote) }
            chartField("Origem informada", item.procedencia.origem)
            chartField("Canal do relato", item.procedencia.canal)
            chartField("Prescrito por (relato)", item.procedencia.prescritoPor)
            if item.procedencia.receitaId != nil { Text("Relato vinculado a uma receita da clínica.").font(.footnote) }
            chartField("Observação", item.observacao)
            ClinicalTimestamp(label: "Início relatado", value: item.inicioEm)
            if !item.ativo {
                ClinicalTimestamp(label: "Suspenso em", value: item.suspensoEm)
                chartField("Motivo da suspensão", item.motivoSuspensao)
            }
            ClinicalTimestamp(label: "Relato atualizado em", value: item.atualizadoEm)
            if let seen = item.vistoEm {
                ClinicalTimestamp(label: "Leitura registrada em", value: seen)
                Text("Leitura registrada não confirma validação do uso.").font(.footnote)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.nome).font(.headline)
                Text(item.ativo ? "Uso ativo relatado" : "Uso suspenso relatado").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

@ViewBuilder
private func chartField(_ title: String, _ value: String?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value?.trimmedOrNil ?? "Não informado na resposta").textSelection(.enabled)
    }
}

struct PatientAdditionalDetails: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    var body: some View {
        Section("Contato de emergência") {
            if let contact = patient.contatoEmergencia {
                chartField("Nome", contact.nome)
                chartField("Parentesco", contact.parentesco)
                chartField("Celular", contact.celular)
            } else { Text("Não informado no cadastro.").foregroundStyle(.secondary) }
        }
        Section {
            DisclosureGroup("Dados cadastrais e convênio") {
                chartField("Sexo registrado", patient.sexo)
                chartField("Profissão", patient.profissao)
                chartField("Estado civil", patient.estadoCivil)
                chartField("Telefone fixo", patient.telefoneFixo)
                chartField("Preferência de contato", patient.preferenciaContato)
                if let address = patient.endereco {
                    chartField("Logradouro", address.logradouro)
                    chartField("Número", address.numero)
                    chartField("Complemento", address.complemento)
                    chartField("Bairro", address.bairro)
                    chartField("Cidade", address.cidade)
                    chartField("UF", address.uf)
                    chartField("CEP", address.cep)
                } else { Text("Endereço não informado.").foregroundStyle(.secondary) }
                if let insurance = patient.convenio {
                    chartField("Operadora", insurance.operadora)
                    chartField("Plano", insurance.plano)
                    chartField("Carteirinha", insurance.carteirinha)
                    chartField("Validade da carteirinha", insurance.validade)
                } else { Text("Convênio não informado.").foregroundStyle(.secondary) }
                if patient.particular == true { Text("Atendimento particular informado no cadastro.") }
            }
        }
        if app.user?.canReadClinicalData == true {
            Section("Informações clínicas do cadastro") {
                chartField("Tipo sanguíneo registrado", patient.tipoSanguineo)
                if let tags = patient.tags, !tags.isEmpty { chartField("Marcadores", tags.joined(separator: " · ")) }
                chartField("Observações", patient.observacao)
            }
        }
    }
}
