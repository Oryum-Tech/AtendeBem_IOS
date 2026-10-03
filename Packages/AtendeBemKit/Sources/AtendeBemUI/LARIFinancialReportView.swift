import AtendeBemCore
import SwiftUI

struct LARIFinancialReportView: View {
    let command: String
    @Environment(AppState.self) private var app
    @State private var period: ReportingPeriod?
    @State private var report: LARIFinancialReport?
    @State private var loading = false
    @State private var error: String?
    @State private var editing = false
    @State private var refreshID = UUID()
    @State private var requestID = UUID()
    @State private var initialContext: UUID?
    private struct LoadKey: Equatable {
        let period: String?
        let context: UUID
        let refresh: UUID
    }
    private var key: LoadKey { LoadKey(period: period?.id, context: app.contextID, refresh: refreshID) }

    init(command: String) {
        self.command = command
        if case .resolved(let period) = LARIFinancialPeriod.resolve(command: command) {
            _period = State(initialValue: period)
        }
    }

    var body: some View {
        Group {
            if app.user?.canReadFinancialReports == true {
                List {
                    Section {
                        LabeledContent("Clínica", value: app.clinicName)
                        if let period { Text(LARIFinancialPeriod.label(period)).font(.headline) }
                        else {
                            Text("Qual período você quer consultar?").font(.headline)
                            Text("Escolha as datas para evitar interpretar um mês ou ano diferente do que você pediu.").foregroundStyle(.secondary)
                        }
                        Button(period == nil ? "Escolher período" : "Alterar período") { editing = true }
                            .frame(minHeight: 44)
                    } footer: {
                        Text("Os dias inicial e final estão incluídos. A síntese é calculada no aplicativo a partir dos dados da clínica, sem enviar o financeiro aos provedores de IA.")
                    }
                    if loading { Section { ProgressView("Consultando o financeiro…") } }
                    if let error {
                        Section {
                            Text(error).foregroundStyle(.red)
                            if period != nil { Button("Consultar novamente") { refreshID = UUID() }.disabled(loading) }
                        }
                    }
                    if let report {
                        if report.isPartial {
                            Section {
                                Label("Relatório parcial", systemImage: "exclamationmark.circle").font(.headline)
                                Text("Não foi possível consultar: \(report.unavailableSources.joined(separator: ", ")). Os dados disponíveis aparecem abaixo; não substituímos os valores ausentes por zero.")
                                Button("Atualizar as fontes") { refreshID = UUID() }.disabled(loading)
                            }
                        }
                        if let summary = report.summary {
                            Section("Resumo financeiro") {
                                amount("Faturamento", summary.faturamento)
                                amount("Recebido", summary.recebido)
                                amount("A receber", summary.aReceber)
                                LabeledContent("Percentual a receber", value: LARIFinancialReport.percentage(summary.inadimplencia))
                                amount("Despesas", summary.despesas)
                                amount("Ticket médio recebido", summary.ticketMedio)
                            }
                            Section("Leitura do período") {
                                Text("O sistema registrou \(LARIFinancialReport.money(summary.faturamento)) em receitas não canceladas. Desse valor, \(LARIFinancialReport.money(summary.recebido)) consta como recebido e \(LARIFinancialReport.money(summary.aReceber)) como pendente.")
                                Text("O percentual a receber inclui valores pendentes e não identifica dívidas vencidas. As despesas podem incluir valores ainda não pagos.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if let ledger = report.ledger {
                            Section {
                                amount("Receitas do relatório", ledger.totais.receita)
                                amount("Despesas do relatório", ledger.totais.despesa)
                                amount("Saldo dos lançamentos", ledger.totais.saldo)
                                DisclosureGroup("Ver valores por dia") {
                                    if ledger.serie.isEmpty { Text("O relatório retornou uma série vazia para este período.").foregroundStyle(.secondary) }
                                    ForEach(ledger.serie.sorted { $0.data < $1.data }) { day in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(civilDay(day.data)).font(.headline)
                                            amount("Receitas", day.receita)
                                            amount("Despesas", day.despesa)
                                            amount("Saldo", day.saldo)
                                        }.padding(.vertical, 6)
                                    }
                                }
                            } header: { Text("Lançamentos no período") } footer: {
                                Text("Inclui lançamentos não cancelados, mesmo os pendentes. Esse saldo não representa caixa, saldo bancário ou lucro. O resumo e o relatório são consultados separadamente e podem refletir atualizações ocorridas entre as leituras.")
                            }
                        }
                        Section {
                            ShareLink(item: report.text(clinicName: app.clinicName)) {
                                Label("Compartilhar relatório em texto", systemImage: "square.and.arrow.up")
                            }.frame(minHeight: 44)
                            Text("Consultado em \(report.consultedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                        } footer: { Text("O compartilhamento abre as opções do sistema. Confira o destino antes de enviar os dados financeiros da clínica.") }
                    }
                }
                .refreshable { guard period != nil else { return }; await load(key: key) }
            } else { RestrictedState() }
        }
        .navigationTitle("Financeiro com a LARI").inlineTitle()
        .task(id: key) { await load(key: key) }
        .onDisappear { requestID = UUID(); report = nil; loading = false }
        .sheet(isPresented: $editing) {
            LARIFinancialPeriodEditor(current: period) { selected in
                report = nil; error = nil; period = selected; refreshID = UUID()
            }
        }
    }

    private func amount(_ label: String, _ value: Decimal) -> some View {
        LabeledContent(label, value: LARIFinancialReport.money(value)).monospacedDigit()
    }
    private func civilDay(_ text: String) -> String {
        let components = text.split(separator: "-")
        return components.count == 3 ? "\(components[2])/\(components[1])/\(components[0])" : text
    }
    private func load(key captured: LoadKey) async {
        let operation = UUID(); requestID = operation
        report = nil; error = nil; loading = false
        if let initialContext, initialContext != app.contextID {
            self.initialContext = app.contextID; period = nil
            error = "A clínica ou sessão mudou. Escolha o período para consultar o contexto atual."
            return
        }
        initialContext = app.contextID
        guard let period, let user = app.user, user.canReadFinancialReports else { return }
        loading = true
        defer { if requestID == operation { loading = false } }
        let apiContext = await app.api.requestContextID()
        guard captured == key, requestID == operation else { return }
        do {
            let value = try await LARIFinancialReportService(api: app.api).load(period: period, user: user, expectedContext: apiContext)
            try Task.checkCancellation()
            guard captured == key, requestID == operation else { return }
            report = value
        } catch is CancellationError {
            // Changing a date or leaving discards the old request without presenting it.
        } catch {
            guard captured == key, requestID == operation else { return }
            self.error = (error as? LARIFinancialReportError)?.localizedDescription ?? message(for: error)
            await app.checkSession(after: error)
        }
    }
}

private struct LARIFinancialPeriodEditor: View {
    let apply: (ReportingPeriod) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    private var selected: ReportingPeriod? { ReportingPeriod(start: start, end: end) }

    init(current: ReportingPeriod?, apply: @escaping (ReportingPeriod) -> Void) {
        self.apply = apply
        let initial = current ?? .preset(.month)
        _start = State(initialValue: initial.start); _end = State(initialValue: initial.end)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data inicial", selection: $start, displayedComponents: .date)
                    DatePicker("Data final", selection: $end, displayedComponents: .date)
                } footer: { Text("Confira o mês e o ano. A consulta só começa quando você tocar em Consultar.") }
                if let selected { Text(LARIFinancialPeriod.label(selected)) }
                else { Text("A data final deve ser igual ou posterior à data inicial.").foregroundStyle(.red) }
            }.navigationTitle("Período financeiro").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Consultar") { guard let selected else { return }; apply(selected); dismiss() }.disabled(selected == nil)
                    }
                }
        }.environment(\.timeZone, ClinicClock.timeZone)
    }
}
