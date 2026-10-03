import AtendeBemCore
import SwiftUI

struct FinancialDashboardView: View {
    @Environment(AppState.self) private var app
    @State private var month = Date.now
    @State private var summary = RemoteResource<FinancialSummary>()
    @State private var entries = RemoteResource<[FinancialEntry]>()

    private var monthKey: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = ClinicClock.timeZone
        return formatter.string(from: month)
    }

    var body: some View {
        Group {
            if app.user?.canReadFinancialReports == true { financialContent }
            else { RestrictedState() }
        }
        .navigationTitle("Financeiro")
        .task(id: monthKey + app.contextID.uuidString) { await load(reset: true) }
    }

    private var financialContent: some View {
        List {
            Section {
                DatePicker("Competência", selection: $month, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                ConnectionState(
                    updatedAt: summary.updatedAt ?? entries.updatedAt,
                    error: summary.error ?? entries.error,
                    isLoading: summary.isLoading || entries.isLoading
                )
            }
            if let value = summary.value {
                Section("Resumo") {
                    FinancialMetric(label: "Faturamento", value: value.faturamento, icon: "chart.line.uptrend.xyaxis")
                    FinancialMetric(label: "Recebido", value: value.recebido, icon: "checkmark.circle")
                    FinancialMetric(label: "A receber", value: value.aReceber, icon: "clock")
                    FinancialMetric(label: "Despesas", value: value.despesas, icon: "arrow.down.circle")
                    FinancialMetric(label: "Ticket médio", value: value.ticketMedio, icon: "banknote")
                    LabeledContent("Percentual a receber", value: value.inadimplencia.formatted(.percent.precision(.fractionLength(1))))
                    Text("Proporção do faturamento ainda a receber; não indica, por si só, pagamentos em atraso.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let values = entries.value {
                Section("Lançamentos") {
                    if values.isEmpty {
                        ContentUnavailableView(
                            "Nenhum lançamento",
                            systemImage: "tray",
                            description: Text("Não há movimentações nesta competência.")
                        )
                    }
                    ForEach(values) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.descricao ?? categoryLabel(entry.categoria)).font(.headline)
                                Spacer()
                                Text(entry.valor, format: .currency(code: "BRL"))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(entry.tipo == "despesa" ? .red : .primary)
                            }
                            Text("\(entry.data) · \(statusLabel(entry.status))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .refreshable { await load() }
    }

    private func load(reset: Bool = false) async {
        guard app.user?.canReadFinancialReports == true else {
            summary = RemoteResource<FinancialSummary>(); entries = RemoteResource<[FinancialEntry]>()
            return
        }
        let key = monthKey
        async let summaryLoad: Void = summary.load(reset: reset, app: app) {
            try await app.api.get(["resumo"], query: [.init(name: "mes", value: key)])
        }
        async let entriesLoad: Void = entries.load(reset: reset, app: app) {
            try await app.api.get(["lancamentos"], query: [.init(name: "mes", value: key)])
        }
        _ = await (summaryLoad, entriesLoad)
    }

    private func categoryLabel(_ value: String) -> String {
        [
            "consulta_particular": "Consulta particular",
            "procedimento": "Procedimento",
            "convenio": "Convênio",
            "insumos": "Insumos",
            "folha": "Folha",
            "aluguel": "Aluguel",
            "outros": "Outros"
        ][value] ?? value
    }

    private func statusLabel(_ value: String) -> String {
        ["pendente": "A receber", "recebido": "Recebido", "pago": "Pago", "cancelado": "Cancelado"][value] ?? value
    }
}

private struct FinancialMetric: View {
    let label: String
    let value: Double
    let icon: String

    var body: some View {
        LabeledContent {
            Text(value, format: .currency(code: "BRL"))
        } label: {
            Label(label, systemImage: icon)
        }
    }
}

struct LARIAssistantView: View {
    let patient: Patient?
    @Environment(AppState.self) private var app
    @State private var transcription = ""
    @State private var suggestion: SOAPSuggestion?
    @State private var isWorking = false
    @State private var error: String?
    @State private var agreedToProcessing = false

    var body: some View {
        Form {
            Section {
                if let patient { LabeledContent("Paciente", value: patient.nome) }
                TextEditor(text: $transcription)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Texto clínico para organizar")
            } header: {
                Text("Anotações ou transcrição")
            } footer: {
                Text("A LARI organiza o conteúdo como rascunho. O profissional deve revisar e assumir o registro.")
            }
            Section {
                if let error { Text(error).foregroundStyle(.red) }
                AIProcessingNotice(includesPatient: patient != nil, agreed: $agreedToProcessing)
                Button { Task { await generate() } } label: {
                    if isWorking { ProgressView() } else { Label("Organizar em SOAP", systemImage: "sparkles") }
                }
                .disabled(!agreedToProcessing || transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
            if let suggestion {
                Section("Rascunho SOAP") {
                    SOAPResult(label: "S — Subjetivo", value: suggestion.soap.s)
                    SOAPResult(label: "O — Objetivo", value: suggestion.soap.o)
                    SOAPResult(label: "A — Avaliação", value: suggestion.soap.a)
                    SOAPResult(label: "P — Plano", value: suggestion.soap.p)
                }
                if !suggestion.cid10Candidatos.isEmpty {
                    Section("CIDs candidatos para revisão") {
                        ForEach(suggestion.cid10Candidatos) { item in
                            VStack(alignment: .leading) {
                                Text("\(item.codigo) · \(item.descricao)")
                                Text(item.confianca, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Responsabilidade profissional") {
                    Text(suggestion.disclaimer).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("LARI")
        .inlineTitle()
    }

    private func generate() async {
        guard agreedToProcessing, !isWorking, transcription.trimmedOrNil != nil, app.user?.canReadClinicalData == true else { return }
        let context = app.contextID
        let apiContext = await app.api.requestContextID()
        guard context == app.contextID, !isWorking else { return }
        isWorking = true
        error = nil
        suggestion = nil
        defer { isWorking = false }
        do {
            let result: SOAPSuggestion = try await app.api.post(
                ["sugestoes", "soap"],
                body: SOAPSuggestionRequest(transcricao: transcription, pacienteId: patient?.id), expectedContext: apiContext
            )
            guard app.contextID == context else { return }
            suggestion = result
        } catch {
            guard app.contextID == context else { return }
            self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

private struct SOAPResult: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "Não informado")
                .textSelection(.enabled)
        }
    }
}

struct MedicalRecordView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<[Evolution]>()

    var body: some View {
        List {
            Section {
                NavigationLink { ClinicalTimelineView(patient: patient) } label: {
                    Label("Histórico de atendimentos e documentos", systemImage: "clock.arrow.circlepath")
                }
            } footer: { Text("Veja também consultas, exames, receitas e outros registros retornados pelas fontes da clínica.") }
            Section {
                ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                if resource.error != nil { Button("Tentar novamente") { Task { await load() } } }
            }
            if let notes = resource.value {
                Section("Evoluções") {
                    if notes.isEmpty {
                        ContentUnavailableView(
                            "Nenhuma evolução retornada",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("O serviço não retornou evoluções para esta ficha. Isso não confirma ausência de histórico; confira o paciente selecionado e atualize a consulta.")
                        )
                    }
                    ForEach(notes) { note in
                        NavigationLink {
                            EvolutionDetailView(evolution: note)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if let date = ClinicClock.parseInstant(note.data) {
                                    Text(date, format: .dateTime.day().month().year().hour().minute()).font(.headline).environment(\.timeZone, ClinicClock.timeZone)
                                } else { Text("Data não disponível").font(.headline) }
                                Text(note.cid10.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Label(note.assinado ? "Assinada no prontuário" : (note.rascunhoAutomatico == true ? "Rascunho em aberto" : "Não assinada"), systemImage: note.assinado ? "checkmark.seal" : "pencil")
                                    .font(.caption)
                                if let complaint = note.queixaPrincipal?.trimmedOrNil {
                                    Text(complaint).font(.subheadline).lineLimit(2)
                                }
                                if let days = note.escritaDiasDepois {
                                    Label("Registro tardio · \(days) dias após o atendimento", systemImage: "clock.badge.exclamationmark").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Prontuário")
        .inlineTitle()
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard app.user?.canReadClinicalData == true else { return }
        await resource.load(app: app) {
            let values: [Evolution] = try await app.api.get(["pacientes", patient.id, "evolucoes"])
            return try validatedChartEntries(values, patientID: patient.id)
        }
    }
}

private struct EvolutionDetailView: View {
    let evolution: Evolution

    var body: some View {
        List {
            Section("Identificação do registro") {
                ClinicalTimestamp(label: "Atendimento", value: evolution.data)
                ClinicalTimestamp(label: "Escrito em", value: evolution.criadoEm)
                Label(evolution.assinado ? "Assinada no prontuário" : (evolution.rascunhoAutomatico == true ? "Rascunho automático em aberto" : "Registro não assinado"), systemImage: evolution.assinado ? "checkmark.seal" : "pencil")
                if evolution.tipo == "adendo" { Text("Adendo ao prontuário").font(.headline) }
                if let days = evolution.escritaDiasDepois {
                    Label("Registro tardio: escrito \(days) dias após o atendimento.", systemImage: "clock.badge.exclamationmark")
                }
                if evolution.rascunhoAutomatico == true {
                    Text("Conteúdo de rascunho em andamento; pode estar incompleto.").font(.footnote).foregroundStyle(.secondary)
                    ClinicalTimestamp(label: "Rascunho salvo em", value: evolution.rascunhoSalvoEm)
                }
            }
            if let complaint = evolution.queixaPrincipal?.trimmedOrNil {
                Section("Queixa principal") { Text(complaint).textSelection(.enabled) }
            }
            ForEach(evolution.displaySections) { section in
                Section { SOAPResult(label: section.title, value: section.text) }
            }
            if evolution.displaySections.isEmpty {
                Section { Text("Nenhum texto clínico retornado nesta evolução.").foregroundStyle(.secondary) }
            }
            if !evolution.cid10.isEmpty {
                Section("CID-10") { Text(evolution.cid10.joined(separator: ", ")) }
            }
        }
        .navigationTitle("Evolução")
        .inlineTitle()
    }
}
