import AtendeBemCore
import SwiftUI

struct ClinicalTimelineView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<ClinicalTimeline>()
    @State private var filter = ""
    private let types = ["consulta", "internacao", "evolucao", "diagnostico", "exame", "receita", "atestado", "anexo", "procedimento"]
    var body: some View {
        List {
            Section {
                Text(patient.nome).font(.headline)
                Picker("Tipo de registro", selection: $filter) {
                    Text("Todos").tag("")
                    ForEach(types, id: \.self) { Text(typeLabel($0)).tag($0) }
                }.disabled(resource.isLoading)
                ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                if resource.error != nil { Button("Atualizar histórico") { Task { await load() } } }
            }
            if let value = resource.value {
                if !value.avisos.isEmpty {
                    Section("Histórico parcial") {
                        Label("Uma ou mais fontes não responderam. Os registros ausentes podem aparecer ao atualizar.", systemImage: "exclamationmark.triangle")
                        ForEach(Array(value.avisos.enumerated()), id: \.offset) { _, warning in
                            Text("\(sourceLabel(warning.servico)): \(warning.mensagem)").font(.footnote)
                        }
                    }
                }
                if let summary = value.resumo {
                    Section {
                        LabeledContent("Consultas realizadas", value: String(summary.totalConsultas))
                        LabeledContent("Diagnósticos ativos", value: String(summary.diagnosticosAtivos))
                        LabeledContent("Internações registradas", value: String(summary.totalInternacoes))
                        LabeledContent("Internações em curso", value: String(summary.internacoesEmCurso))
                        LabeledContent("Dias em internações com alta", value: String(summary.diasInternado))
                        ClinicalTimestamp(label: "Primeira interação", value: summary.primeiraInteracao)
                        ClinicalTimestamp(label: "Última interação", value: summary.ultimaInteracao)
                    } header: { Text(value.avisos.isEmpty ? "Resumo das fontes consultadas" : "Resumo parcial das fontes consultadas") }
                    footer: { Text("Contagens calculadas pelo serviço sobre o histórico consultado, antes da paginação. Fontes indisponíveis não entram nestes números.") }
                }
                Section("Registros retornados") {
                    if value.eventos.isEmpty {
                        ContentUnavailableView("Nenhum registro retornado", systemImage: "clock.badge.questionmark",
                            description: Text("Confira o filtro e a ficha selecionada. Uma lista vazia não comprova ausência de histórico clínico."))
                    }
                    ForEach(value.eventos) { item in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.descricao ?? "Esta fonte não forneceu um resumo textual.").textSelection(.enabled)
                                Text("Resumo retornado pelo serviço. Consulte o documento original para o conteúdo completo.").font(.footnote).foregroundStyle(.secondary)
                                if ["exame", "receita", "atestado"].contains(item.tipo) {
                                    NavigationLink { PatientDocumentsView(patient: patient) } label: { Label("Documentos deste paciente", systemImage: "doc.richtext") }
                                }
                                Text("Origem: \(sourceLabel(item.origemServico))").font(.footnote).foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.titulo).font(.headline)
                                Text(typeLabel(item.tipo)).font(.subheadline).foregroundStyle(.secondary)
                                if let status = item.metadados?.status, !status.isEmpty {
                                    Text("Situação: \(statusLabel(status, type: item.tipo))").font(.caption)
                                }
                                if let date = ClinicClock.parseInstant(item.data) {
                                    Text(date, format: .dateTime.day().month().year().hour().minute())
                                        .font(.caption).environment(\.timeZone, ClinicClock.timeZone)
                                } else { Text("Data não informada").font(.caption) }
                                if item.approximateDate { Text("Data aproximada de registro").font(.caption).foregroundStyle(.secondary) }
                                if item.tipo == "internacao" && item.dataFim == nil { Text("Internação em curso").font(.caption) }
                                if item.tipo == "internacao", let end = item.dataFim { ClinicalTimestamp(label: "Alta registrada", value: end) }
                            }.padding(.vertical, 5)
                        }
                    }
                }
                Section {
                    Text("\(value.eventos.count) registros carregados de \(value.paginacao.total) retornados pelo serviço").font(.footnote).foregroundStyle(.secondary)
                    if value.paginacao.page < value.paginacao.totalPaginas {
                        Button("Carregar registros anteriores") { Task { await load(more: true) } }.disabled(resource.isLoading)
                    }
                }
            }
        }.navigationTitle("Histórico do paciente").inlineTitle()
            .task(id: filter) { await load(reset: true) }
            .refreshable { await load() }
    }
    private func load(more: Bool = false, reset: Bool = false) async {
        let previous = more ? resource.value : nil
        let page = (previous?.paginacao.page ?? 0) + 1
        let selection = filter
        await resource.load(reset: reset, app: app) {
            var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: "25")]
            if !selection.isEmpty { query.append(URLQueryItem(name: "tipos", value: selection)) }
            let next: ClinicalTimeline = try await app.api.get(["pacientes", patient.id, "ficha"], query: query)
            guard next.pacienteId == patient.id, next.paginacao.page == page else { throw APIError.invalidResponse }
            return try previous?.appending(next) ?? next
        }
    }
    private func typeLabel(_ value: String) -> String {
        ["consulta": "Consulta", "internacao": "Internação", "evolucao": "Evolução", "diagnostico": "Diagnóstico", "exame": "Exame", "receita": "Receita", "atestado": "Atestado", "anexo": "Anexo", "procedimento": "Procedimento"][value] ?? value
    }
    private func sourceLabel(_ value: String) -> String {
        ["svc-prontuario": "Prontuário", "svc-agenda": "Agenda", "svc-hospital": "Internações", "svc-exames": "Exames", "svc-receituario": "Receituário"][value] ?? value
    }
    private func statusLabel(_ value: String, type: String) -> String {
        if type == "evolucao", ["rascunho", "registrada"].contains(value) { return "Registrada, não assinada" }
        return ["scheduled": "Agendada", "pending": "Aguardando confirmação", "confirmed": "Confirmada",
                "in-progress": "Em andamento", "completed": "Realizada", "cancelled": "Cancelada", "no-show": "Faltou",
                "rascunho": "Rascunho", "rascunho-automatico": "Rascunho automático", "assinada": "Assinada",
                "assinado": "Assinado", "emitida": "Emitida", "emitido": "Emitido", "solicitado": "Solicitado",
                "cancelado": "Cancelado", "cancelada": "Cancelada", "resultado-disponivel": "Resultado disponível",
                "aguardando-coleta": "Aguardando coleta", "alterado": "Alterado", "alta": "Com alta",
                "resolvido": "Resolvido", "ativo": "Ativo"][value] ?? value
    }
}
