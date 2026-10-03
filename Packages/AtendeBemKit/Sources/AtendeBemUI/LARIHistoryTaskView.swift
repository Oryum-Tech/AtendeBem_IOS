import AtendeBemCore
import SwiftUI

struct LARIHistoryTaskView: View {
    let command: String
    var task: LARIHistoryTask? = nil
    var onTaskReady: ((LARIHistoryTask) -> Void)? = nil
    @Environment(AppState.self) private var app
    @State private var model: LARIHistoryTask?
    var body: some View {
        Group {
            if app.user?.canReadClinicalData != true { RestrictedState() }
            else if let model { content(model) }
            else { ProgressView("Preparando consulta ao histórico…") }
        }.navigationTitle("Histórico com LARI").inlineTitle()
            .task { [app] in
                guard model == nil, let user = app.user, user.canReadClinicalData else { return }
                if let task { model = task; return }
                let context = app.contextID, apiContext = await app.api.requestContextID()
                guard context == app.contextID else { return }
                let created = LARIHistoryTask(command: command, api: app.api, context: apiContext, user: user,
                    isContextCurrent: { [weak app] in app?.contextID == context && app?.user?.id == user.id && app?.user?.canReadClinicalData == true })
                model = created; onTaskReady?(created); await created.searchPatients(); await recover()
            }
    }
    private func content(_ model: LARIHistoryTask) -> some View {
        List {
            LARITaskContextSection(command: command, explanation: "Vou consultar as fontes do prontuário deste paciente na clínica atual. Esta leitura não envia o conteúdo aos provedores de IA.")
            LARIPatientTaskSection(lookup: model.lookup, editable: model.available, search: model.searchPatients, select: model.selectPatient, change: model.changePatient)
            if let patient = model.lookup.patient {
                Section {
                    LariSummaryButton(patient: patient)
                    NavigationLink("Abrir prontuário estruturado") { PatientClinicalChartView(patient: patient) }
                    NavigationLink("Consultar documentos e resultados") { PatientDocumentsView(patient: patient) }
                } footer: { Text("O resumo por IA é opcional e pede autorização antes de processar os dados. Os registros abaixo preservam o conteúdo retornado pelas fontes.") }
                if !model.sourceWarnings.isEmpty || model.timeline?.avisos.isEmpty == false {
                    Section("Consulta parcial") {
                        ForEach(model.sourceWarnings, id: \.self) { Text($0).font(.footnote) }
                        ForEach(Array((model.timeline?.avisos ?? []).enumerated()), id: \.offset) { _, warning in
                            Text("\(warning.servico): \(warning.mensagem)").font(.footnote)
                        }
                    }
                }
                if let allergies = model.allergies {
                    Section("Alergias retornadas") {
                        if allergies.isEmpty { Text("Nenhuma alergia foi retornada pelo serviço nesta consulta.").font(.footnote) }
                        ForEach(Array(allergies.enumerated()), id: \.offset) { _, value in
                            Label("\(value.substancia) · \(value.severidade)", systemImage: "exclamationmark.triangle")
                            if let reaction = value.reacao { Text(reaction).font(.footnote) }
                        }
                    }
                }
                if let history = model.antecedents {
                    Section("Antecedentes do prontuário") {
                        LabeledContent("História familiar", value: history.familiar ?? "Não informada")
                        LabeledContent("História social", value: history.social ?? "Não informada")
                        DisclosureGroup("Outros antecedentes") {
                            LabeledContent("Ocupacional", value: history.ocupacional ?? "Não informado")
                            LabeledContent("Esportiva", value: history.esportiva ?? "Não informada")
                            LabeledContent("Quedas em 12 meses", value: history.fallsLabel)
                            LabeledContent("Detalhes das quedas", value: history.quedasDetalhe ?? "Não informados")
                            LabeledContent("Cirurgias na região", value: history.cirurgiasRegiao ?? "Não informadas")
                            LabeledContent("Fisioterapia prévia", value: history.fisioterapiaPrevia ?? "Não informada")
                            LabeledContent("Dominância", value: history.dominancia ?? "Não informada")
                        }
                        ClinicalTimestamp(label: "Atualização deste registro", value: history.atualizadoEm)
                    }
                }
                if let timeline = model.timeline {
                    if let summary = timeline.resumo {
                        Section {
                            LabeledContent("Consultas realizadas", value: String(summary.totalConsultas))
                            LabeledContent("Diagnósticos ativos", value: String(summary.diagnosticosAtivos))
                            LabeledContent("Internações", value: String(summary.totalInternacoes))
                            ClinicalTimestamp(label: "Última interação registrada", value: summary.ultimaInteracao)
                        } header: { Text(timeline.avisos.isEmpty ? "Resumo das fontes" : "Resumo parcial das fontes") }
                        footer: { Text("Contagens fornecidas pelo serviço antes da paginação. Não incluem fontes que não responderam.") }
                    }
                    Section("Histórico retornado") {
                        if timeline.eventos.isEmpty { Text("Nenhum registro foi retornado. Isso não comprova ausência de histórico.").font(.footnote) }
                        ForEach(timeline.eventos) { event in
                            DisclosureGroup {
                                Text(event.descricao ?? "A fonte não forneceu texto para este registro.").textSelection(.enabled)
                                Text("Fonte: \(event.origemServico). Abra o prontuário ou documento para o conteúdo completo.").font(.caption).foregroundStyle(.secondary)
                                if event.approximateDate { Text("A data é aproximada de registro, não necessariamente da ocorrência clínica.").font(.caption) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(event.titulo).font(.headline)
                                    ClinicalTimestamp(label: "Registro", value: event.data)
                                }
                            }
                        }
                        Text("\(timeline.eventos.count) registros carregados de \(timeline.paginacao.total)").font(.footnote)
                        if timeline.paginacao.page < timeline.paginacao.totalPaginas {
                            Button("Carregar registros anteriores") { Task { await model.load(more: true); await recover() } }.disabled(model.isWorking)
                        }
                    }
                }
                Section {
                    ConnectionState(updatedAt: model.updatedAt, error: model.error, isLoading: model.busy)
                    Button("Atualizar fontes do histórico") { Task { await model.load(); await recover() } }.disabled(model.isWorking)
                }
            } else if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
        }
    }
    private func recover() async { if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) } }
}
