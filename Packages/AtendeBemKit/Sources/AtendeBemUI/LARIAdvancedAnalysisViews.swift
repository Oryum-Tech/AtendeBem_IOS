import AtendeBemCore
import SwiftUI

struct LARIAnalyticsTaskView: View {
    let command: String
    @Environment(AppState.self) private var app
    @State private var kind = AnalysisKind.seasonality
    @State private var report: String?
    @State private var error: String?
    @State private var busy = false
    @State private var loadedContext: UUID?
    private enum AnalysisKind: String, CaseIterable, Identifiable {
        case seasonality, geography
        var id: Self { self }
        var title: String { self == .seasonality ? "Sazonalidade da agenda" : "Carteira por município" }
    }
    private var allowed: Bool { app.user.map(LARIAdvancedAccess.analytics) == true }
    var body: some View {
        Form {
            if allowed {
                Section {
                    LabeledContent("Clínica", value: app.clinicName)
                    if !command.isEmpty { Text(command).font(.footnote).foregroundStyle(.secondary) }
                    Picker("Análise", selection: $kind) {
                        ForEach(AnalysisKind.allCases) { item in Text(item.title).tag(item) }
                    }.disabled(busy)
                } footer: {
                    Text(kind == .seasonality
                         ? "Analisa o histórico disponível de toda a clínica. O período será informado pela fonte; este serviço não oferece um filtro por mês nem pesquisa científica externa."
                         : "Consulta o cadastro agregado da clínica e os indicadores municipais disponíveis no IBGE. O perfil do município não é o perfil individual dos pacientes.")
                }
                Section {
                    if busy { ProgressView("Consultando as fontes…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(report == nil ? "Consultar e gerar análise" : "Atualizar análise") { Task { await load() } }
                        .disabled(busy).accessibilityIdentifier("lari.analytics.load")
                }
                if let report, loadedContext == app.contextID {
                    Section("Relatório das fontes consultadas") {
                        Text(report).textSelection(.enabled)
                        ShareLink(item: report) { Label("Compartilhar relatório", systemImage: "square.and.arrow.up") }
                    }
                }
            } else { RestrictedState() }
        }
        .navigationTitle("Análises da clínica").inlineTitle()
        .task { kind = command.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).contains("sazon") ? .seasonality : .geography }
        .onChange(of: kind) { _, _ in report = nil; error = nil }
        .onChange(of: app.contextID) { _, _ in report = nil; error = nil }
        .onChange(of: allowed) { _, permitted in if !permitted { report = nil; error = nil } }
    }
    private func load() async {
        guard allowed, !busy, let user = app.user else { return }
        let context = app.contextID
        let requestedKind = kind
        busy = true; error = nil; report = nil; loadedContext = context
        defer { busy = false }
        do {
            let apiContext = await app.api.requestContextID()
            guard context == app.contextID, allowed else { return }
            let service = LARIAnalyticsService(api: app.api)
            let text: String
            switch requestedKind {
            case .seasonality: text = try await service.seasonality(user: user, context: apiContext).text(clinic: app.clinicName)
            case .geography: text = try await service.geography(user: user, context: apiContext).text(clinic: app.clinicName)
            }
            guard context == app.contextID, allowed, app.user?.id == user.id, requestedKind == kind else { return }
            report = text
        } catch {
            guard context == app.contextID, allowed else { return }
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

struct LARIInteractionsTaskView: View {
    let command: String
    @Environment(AppState.self) private var app
    @State private var principles = ""
    @State private var result: CuratedInteractionReport?
    @State private var error: String?
    @State private var busy = false
    @State private var showCatalog = false
    @State private var reviewed = false
    @State private var loadedContext: UUID?
    private var allowed: Bool { app.user.map(LARIAdvancedAccess.clinical) == true }
    private var validInput: Bool { (try? CuratedInteractionService.principles(from: principles)) != nil }
    var body: some View {
        Form {
            if allowed {
                Section {
                    if !command.isEmpty { Text(command).font(.footnote).foregroundStyle(.secondary) }
                    TextEditor(text: $principles).frame(minHeight: 120)
                        .accessibilityLabel("Princípios ativos, um por linha")
                        .accessibilityIdentifier("lari.interactions.principles")
                    Button("Adicionar princípio pelo catálogo") { showCatalog = true }
                    Toggle("Conferi os princípios ativos a consultar", isOn: $reviewed)
                } header: { Text("Princípios ativos") } footer: {
                    Text("Informe de 2 a 50 princípios, um por linha. A marca comercial não é convertida automaticamente. Confira produtos com mais de um princípio ativo; nenhum medicamento do paciente é incluído sem sua escolha.")
                }.disabled(busy)
                Section {
                    Text(CuratedInteractionReport.limitation).font(.footnote)
                    if busy { ProgressView("Consultando a base de interações…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Consultar interações") { Task { await check() } }
                        .disabled(!reviewed || !validInput || busy).accessibilityIdentifier("lari.interactions.check")
                }
                if let result, loadedContext == app.contextID {
                    Section("Resultado da consulta") {
                        if result.alerts.isEmpty {
                            Label("Nenhum alerta encontrado na base consultada", systemImage: "info.circle")
                            Text("Isso não confirma a segurança da combinação. Confira também as bulas, as condições clínicas e outras fontes farmacológicas.").font(.footnote)
                        }
                        ForEach(result.alerts) { alert in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(alert.gravidade == "grave" ? "Interação grave" : "Interação moderada", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(alert.gravidade == "grave" ? .red : .orange)
                                Text("\(alert.a) × \(alert.b)").font(.headline)
                                Text(alert.descricao)
                                Text("Fonte: \(alert.fonte)").font(.footnote)
                                Text("Revisão: \(alert.revisadoEm)").font(.footnote).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        ShareLink(item: result.text()) { Label("Compartilhar consulta", systemImage: "square.and.arrow.up") }
                    }
                }
            } else { RestrictedState() }
        }
        .navigationTitle("Interações medicamentosas").inlineTitle()
        .navigationBarBackButtonHidden(busy).interactiveDismissDisabled(busy)
        .onChange(of: principles) { _, _ in result = nil; reviewed = false; error = nil }
        .onChange(of: app.contextID) { _, _ in clear() }
        .onChange(of: allowed) { _, permitted in if !permitted { clear() } }
        .sheet(isPresented: $showCatalog) {
            NavigationStack {
                InteractionMedicinePicker { active in
                    guard allowed, !busy else { return }
                    principles += (principles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n") + active
                }
            }
        }
    }
    private func clear() { result = nil; principles = ""; error = nil; reviewed = false; showCatalog = false }
    private func check() async {
        guard allowed, reviewed, validInput, !busy, let user = app.user else { return }
        let context = app.contextID
        let text = principles
        busy = true; result = nil; error = nil; loadedContext = context
        defer { busy = false }
        do {
            let apiContext = await app.api.requestContextID()
            guard context == app.contextID, allowed else { return }
            let value = try await CuratedInteractionService(api: app.api).check(text: text, user: user, context: apiContext)
            guard context == app.contextID, allowed, app.user?.id == user.id, principles == text else { return }
            result = value
        } catch {
            guard context == app.contextID, allowed else { return }
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

private struct InteractionMedicinePicker: View {
    let select: (String) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var resource = RemoteResource<MedicineSearch>()
    var body: some View {
        List {
            ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
            ForEach(resource.value?.itens ?? []) { item in
                Button {
                    guard let active = item.principioAtivo?.trimmedOrNil else { return }
                    select(active); dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.nomeProduto)
                        Text(item.principioAtivo ?? "Princípio ativo não informado").font(.footnote).foregroundStyle(.secondary)
                        if let concentration = item.concentracao { Text(concentration).font(.caption) }
                    }
                }.disabled(item.principioAtivo?.trimmedOrNil == nil)
            }
        }
        .navigationTitle("Buscar medicamento").inlineTitle()
        .searchable(text: $search, prompt: "Produto ou princípio ativo")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        .task(id: search) {
            resource.clear()
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= 2, app.user.map(LARIAdvancedAccess.clinical) == true else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await resource.load(app: app) { try await app.api.get(["medicamentos"], query: [.init(name: "busca", value: query), .init(name: "perPage", value: "20")]) }
        }
        .onChange(of: app.contextID) { _, _ in resource.clear(); dismiss() }
    }
}
