import AtendeBemCore
import Charts
import SwiftUI

struct ReportsView: View {
    @Environment(AppState.self) private var app
    @State private var period = ReportingPeriod.preset(.month)
    @State private var preset: ReportingPeriod.Preset? = .month
    @State private var editingPeriod: ReportingPeriod?

    private var requestIdentity: String {
        "\(app.contextID)-\(app.user?.papeis.sorted().joined(separator: ",") ?? "")-\(period.id)"
    }

    var body: some View {
        Group {
            if app.user?.canReadReports == true {
                ReportsContentView(period: period, preset: preset, choosePreset: select,
                                   customize: { editingPeriod = period })
                    // A period or access-context change creates fresh resources immediately,
                    // before a new request can leave old numbers under a new date heading.
                    .id(requestIdentity)
            } else {
                RestrictedState()
            }
        }
        .navigationTitle("Relatórios").inlineTitle()
        .environment(\.timeZone, ClinicClock.timeZone)
        .sheet(item: $editingPeriod) { current in
            ReportPeriodEditor(period: current) { next in
                period = next
                preset = nil
            }
        }
    }

    private func select(_ next: ReportingPeriod.Preset) {
        period = .preset(next)
        preset = next
    }
}

private struct ReportsContentView: View {
    let period: ReportingPeriod
    let preset: ReportingPeriod.Preset?
    let choosePreset: (ReportingPeriod.Preset) -> Void
    let customize: () -> Void
    @Environment(AppState.self) private var app
    @State private var agenda = RemoteResource<AgendaStatistics>()
    @State private var prescriptions = RemoteResource<PrescriptionStatistics>()

    var body: some View {
        List {
            Section {
                LabeledContent("Clínica", value: app.clinicName)
                Picker("Período", selection: Binding(
                    get: { preset?.rawValue ?? "custom" },
                    set: { value in
                        if let choice = ReportingPeriod.Preset(rawValue: value) { choosePreset(choice) }
                        else { customize() }
                    }
                )) {
                    ForEach(ReportingPeriod.Preset.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                    Text("Personalizado…").tag("custom")
                }
                .pickerStyle(.menu).accessibilityIdentifier("reports.period")
                if preset == nil { Button("Editar intervalo personalizado", action: customize) }
                Text(period.longDescription).font(.subheadline)
                    .accessibilityLabel("Intervalo: \(period.longDescription). Dias inicial e final incluídos.")
            } footer: {
                Text("Os dias inicial e final estão incluídos. Os resultados respeitam suas permissões na clínica atual.")
            }

            if app.user?.canReadAgenda == true {
                Section {
                    if let value = agenda.value {
                        ReportTotalRow(title: "Agendados", total: value.total, symbol: "calendar")
                        ReportAgendaDistribution(period: period, statistics: value)
                        if [.unavailable, .inconsistent].contains(AgendaReportDistribution(value).state) {
                            Button("Atualizar distribuição") { Task { await refreshAgenda() } }
                                .disabled(agenda.isLoading)
                                .accessibilityIdentifier("reports.retryDistribution")
                        }
                        LabeledContent("Concluídos", value: value.concluidas.formatted())
                        LabeledContent("Faltas", value: value.faltas.formatted())
                        LabeledContent("Taxa de faltas", value: value.taxaFaltas.formatted(.percent.precision(.fractionLength(1))))
                        if value.total == 0 { Text("Nenhum agendamento neste período.").foregroundStyle(.secondary) }
                    }
                    ConnectionState(updatedAt: agenda.updatedAt, error: agenda.error, isLoading: agenda.isLoading)
                    if agenda.error != nil {
                        Button("Atualizar atendimentos") { Task { await refreshAgenda() } }
                            .disabled(agenda.isLoading)
                    }
                } header: { Text("Atendimentos") } footer: {
                    Text("Contagem da agenda em horário de Brasília (UTC−03). Agendados inclui todos os status. A taxa de faltas é a informada pela agenda.")
                }
            }

            if app.user?.canReadPrescriptionStatistics == true {
                Section {
                    if let value = prescriptions.value {
                        ReportTotalRow(title: "Receitas", total: value.total, symbol: "pills")
                        LabeledContent("Emitidas", value: value.emitidas.formatted())
                        LabeledContent("Rascunhos", value: value.rascunhos.formatted())
                        LabeledContent("Canceladas", value: value.canceladas.formatted())
                        if value.total == 0 { Text("Nenhuma receita neste período.").foregroundStyle(.secondary) }
                    }
                    ConnectionState(updatedAt: prescriptions.updatedAt, error: prescriptions.error, isLoading: prescriptions.isLoading)
                    if prescriptions.error != nil {
                        Button("Atualizar receitas") { Task { await refreshPrescriptions() } }
                            .disabled(prescriptions.isLoading)
                    }
                } header: { Text("Receitas") } footer: {
                    Text("As receitas usam o calendário da clínica, conforme sua localização. Os indicadores são carregados separadamente da agenda.")
                }
            }

            if app.user?.canReadFinancialReports == true {
                Section {
                    NavigationLink { FinancialDashboardView() } label: {
                        Label("Consultar financeiro", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } footer: { Text("O financeiro tem seu próprio filtro de período.") }
            }
        }
        .task { await refreshAgenda() }
        .task { await refreshPrescriptions() }
        .refreshable {
            await refreshAgenda()
            guard !Task.isCancelled else { return }
            await refreshPrescriptions()
        }
    }

    private func refreshAgenda() async {
        guard app.user?.canReadAgenda == true else { return }
        await agenda.load(app: app) { try await ReportService(api: app.api).agenda(period: period) }
    }

    private func refreshPrescriptions() async {
        guard app.user?.canReadPrescriptionStatistics == true else { return }
        await prescriptions.load(app: app) { try await ReportService(api: app.api).prescriptions(period: period) }
    }
}

private struct ReportTotalRow: View {
    let title: String
    let total: Int
    let symbol: String
    var body: some View {
        LabeledContent {
            Text(total.formatted()).font(.title2.weight(.semibold)).monospacedDigit()
        } label: { Label(title, systemImage: symbol).font(.headline) }
        .padding(.vertical, 4)
    }
}

private struct ReportAgendaDistribution: View {
    let period: ReportingPeriod
    let statistics: AgendaStatistics
    @State private var page = 0
    private let pageSize = 8
    private var distribution: AgendaReportDistribution { .init(statistics) }
    private var buckets: [Bucket] {
        distribution.values.enumerated().map { index, value in
            Bucket(id: index, label: period.weeklyBucket(label: value.rotulo)?.shortDescription ?? value.rotulo,
                   total: value.total)
        }
    }
    private var pageCount: Int { max(1, (buckets.count + pageSize - 1) / pageSize) }
    private var safePage: Int { min(page, pageCount - 1) }
    private var visibleBuckets: [Bucket] { Array(buckets.dropFirst(safePage * pageSize).prefix(pageSize)) }
    private struct Bucket: Identifiable {
        let id: Int
        let label: String
        let total: Int
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribuição dos agendamentos").font(.subheadline.weight(.semibold))
            switch distribution.state {
            case .unavailable:
                Label("Distribuição não retornada", systemImage: "chart.bar.xaxis")
                Text("O serviço informou os indicadores acima, mas não trouxe os intervalos do gráfico. Atualize o relatório para tentar novamente.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .inconsistent:
                Label("Distribuição precisa de conferência", systemImage: "exclamationmark.circle")
                Text("Os intervalos recebidos não correspondem ao total informado. O gráfico não será estimado. Atualize o relatório para conferir.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .available, .empty:
                if distribution.state == .empty {
                    Text("Todos os intervalos retornados têm zero agendamentos.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Chart(visibleBuckets) { bucket in
                        BarMark(x: .value("Agendamentos", bucket.total), y: .value("Intervalo", bucket.label))
                            .foregroundStyle(Color.accentColor)
                            .annotation(position: .trailing) { Text(bucket.total.formatted()).font(.caption).monospacedDigit() }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: CGFloat(max(visibleBuckets.count, 2) * 38))
                    .padding(.trailing, 24)
                    .accessibilityHidden(true)
                }
                // Exact values remain available with VoiceOver and larger text,
                // without a second vertical scroll area inside this List row.
                DisclosureGroup("Ver números destes intervalos") {
                    ForEach(visibleBuckets) { bucket in
                        LabeledContent(bucket.label, value: bucket.total.formatted())
                            .accessibilityElement(children: .combine)
                    }
                }
                if pageCount > 1 {
                    Text("Intervalos \(safePage * pageSize + 1)–\(min((safePage + 1) * pageSize, buckets.count)) de \(buckets.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Anteriores") { page = max(0, safePage - 1) }.disabled(safePage == 0)
                        Spacer()
                        Button("Próximos") { page = min(pageCount - 1, safePage + 1) }.disabled(safePage == pageCount - 1)
                    }.buttonStyle(.borderless).frame(minHeight: 44)
                }
                Text("Intervalos informados pela agenda: blocos de 7 dias; em períodos maiores, por mês.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("reports.agendaDistribution")
    }
}

private struct ReportPeriodEditor: View {
    let apply: (ReportingPeriod) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    private var selection: ReportingPeriod? { ReportingPeriod(start: start, end: end) }

    init(period: ReportingPeriod, apply: @escaping (ReportingPeriod) -> Void) {
        self.apply = apply
        _start = State(initialValue: period.start)
        _end = State(initialValue: period.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data inicial", selection: $start, displayedComponents: .date)
                    DatePicker("Data final", selection: $end, displayedComponents: .date)
                } footer: {
                    Text("Escolha as datas e toque em Aplicar. Os relatórios só serão consultados depois da sua confirmação.")
                }
                if let selection {
                    Section("Intervalo selecionado") { Text(selection.longDescription) }
                } else {
                    Text("A data final precisa ser igual ou posterior à data inicial.")
                        .foregroundStyle(.red).accessibilityLabel("Período inválido. A data final precisa ser igual ou posterior à data inicial.")
                }
            }
            .navigationTitle("Personalizar período").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        guard let selection else { return }
                        apply(selection)
                        dismiss()
                    }.disabled(selection == nil)
                }
            }
        }
        .environment(\.timeZone, ClinicClock.timeZone)
    }
}

private extension ReportingPeriod {
    var longDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = ClinicClock.timeZone
        formatter.dateStyle = .long
        let first = formatter.string(from: start)
        return start == end ? first : "\(first) a \(formatter.string(from: end))"
    }
    var shortDescription: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = ClinicClock.timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        let first = formatter.string(from: start)
        return start == end ? first : "\(first)–\(formatter.string(from: end))"
    }
}
