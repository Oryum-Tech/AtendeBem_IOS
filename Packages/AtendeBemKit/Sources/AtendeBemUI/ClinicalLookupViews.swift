import AtendeBemCore
import SwiftUI

struct MedicineLookup: View {
    @Binding var medicine: String
    @Environment(AppState.self) private var app
    @State private var result = RemoteResource<MedicineSearch>()
    @State private var selectedName: String?
    private var query: String { medicine.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Medicamento", text: $medicine)
            if query.count >= 2 && selectedName != medicine {
                if result.isLoading { ProgressView("Buscando no catálogo…") }
                if let error = result.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                ForEach(result.value?.itens ?? []) { item in
                    Button {
                        selectedName = item.nomeProduto; medicine = item.nomeProduto; result.clear()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.nomeProduto).font(.subheadline.bold())
                            if let active = item.principioAtivo { Text(active).font(.caption) }
                            if let company = item.empresa { Text(company).font(.caption).foregroundStyle(.secondary) }
                            Text("Situação: \(item.situacao)").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.borderless)
                }
                if result.value?.itens.isEmpty == true { Text("Nenhum resultado. Confira a grafia ou informe o medicamento manualmente.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: medicine) { _, _ in result.clear() }
        .task(id: query) {
            guard query.count >= 2, selectedName != medicine else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let requested = query
            await result.load(reset: true, app: app) {
                try await app.api.get(["medicamentos"], query: [.init(name: "busca", value: requested), .init(name: "perPage", value: "8")])
            }
        }
    }
}

struct ClinicalCodePicker: View {
    let onSelect: (ClinicalCode) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var result = RemoteResource<[ClinicalCode]>()
    @State private var resultContext: UUID?
    @State private var resultQuery: String?
    @State private var retryID = UUID()
    @FocusState private var searchFocused: Bool
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var allowed: Bool { app.user?.canReadClinicalData == true }
    private var searchKey: String { "\(app.contextID)|\(allowed)|\(query)|\(retryID)" }
    var body: some View {
        Group {
            if allowed {
                VStack(spacing: 0) {
                    searchField
                    resultList
                }
            } else {
                RestrictedState()
            }
        }
        .navigationTitle("Buscar CID-10").inlineTitle()
        .toolbar { Button("Fechar") { dismiss() } }
        .onChange(of: query) { _, _ in clearResults() }
        .onChange(of: app.contextID) { _, _ in clearResults() }
        .onChange(of: allowed) { _, _ in clearResults() }
        .task(id: searchKey) { await loadResults() }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Código ou descrição").font(.subheadline.bold())
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Ex.: J00 ou rinite", text: $search)
                    .autocorrectionDisabled().submitLabel(.search).focused($searchFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Buscar CID-10 por código ou descrição")
                    .accessibilityIdentifier("clinical.cid.search")
                    .onSubmit { retryID = UUID(); searchFocused = false }
                if !search.isEmpty {
                    Button { search = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Limpar busca de CID-10")
                    .accessibilityIdentifier("clinical.cid.clear")
                }
            }
            .frame(minHeight: 44).padding(.horizontal, 12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            Text("Digite pelo menos 2 caracteres. Depois, selecione o CID nos resultados.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding().background(Brand.background)
    }

    private var resultList: some View {
        List {
            if query.count < 2 {
                ContentUnavailableView("Encontre o CID-10", systemImage: "magnifyingglass",
                    description: Text("Busque pelo código completo, pelo início do código ou por uma palavra da descrição."))
            } else if resultContext == app.contextID, resultQuery == query {
                ConnectionState(updatedAt: result.updatedAt, error: nil, isLoading: result.isLoading)
                if let error = result.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Tentar a busca novamente") { retryID = UUID() }
                            .disabled(result.isLoading).accessibilityIdentifier("clinical.cid.retry")
                    } header: { Text("Não foi possível buscar") }
                }
                if let codes = result.value {
                    if codes.isEmpty {
                        ContentUnavailableView("Nenhum CID encontrado", systemImage: "magnifyingglass",
                            description: Text("Confira “\(query)” ou tente outra palavra da descrição. A ausência de resultados não confirma que o código não exista."))
                    } else {
                        Section("Selecione o CID-10") {
                            ForEach(codes) { item in
                                Button {
                                    guard allowed, resultContext == app.contextID, resultQuery == query else { return }
                                    onSelect(item); dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.codigo).font(.headline)
                                        Text(item.descricao).foregroundStyle(.primary)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .accessibilityHint("Seleciona este CID e retorna à consulta")
                            }
                        }
                    }
                }
            } else {
                ProgressView("Preparando busca…")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func clearResults() {
        result.clear(); resultContext = nil; resultQuery = nil
    }

    private func loadResults() async {
        let requested = query, context = app.contextID
        guard allowed, requested.count >= 2 else { return }
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        guard !Task.isCancelled, allowed, app.contextID == context, query == requested else { return }
        resultContext = context; resultQuery = requested
        await result.load(reset: true, app: app) {
            try await app.api.get(["sugestoes", "cid"], query: [.init(name: "q", value: requested)])
        }
    }
}

struct PatientHistorySection: View {
    let patientID: String
    @Environment(AppState.self) private var app
    @State private var history = RemoteResource<PatientHistory>()
    @State private var expanded = false
    var body: some View {
        Section("História médica pregressa") {
            if let value = history.value {
                Text(value.social?.trimmedOrNil ?? "História social não informada").lineLimit(expanded ? nil : 2)
                DisclosureGroup(expanded ? "Menos dados" : "Mais dados", isExpanded: $expanded) {
                    field("Familiar", value.familiar)
                    field("Ocupacional", value.ocupacional)
                    field("Esportiva", value.esportiva)
                    LabeledContent("Quedas nos últimos 12 meses", value: value.fallsLabel)
                    field("Detalhes das quedas", value.quedasDetalhe)
                    field("Cirurgias na região", value.cirurgiasRegiao)
                    field("Fisioterapia prévia", value.fisioterapiaPrevia)
                    field("Dominância", value.dominancia)
                    if let raw = value.atualizadoEm, let date = ClinicClock.parseInstant(raw) {
                        Text("Registro atualizado em \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ConnectionState(updatedAt: history.updatedAt, error: history.error, isLoading: history.isLoading)
            if history.error != nil { Button("Tentar novamente") { Task { await load() } } }
        }.task(id: patientID) { await load() }
    }
    private func field(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text?.trimmedOrNil ?? "Não informado").textSelection(.enabled)
        }.padding(.vertical, 3)
    }
    private func load() async {
        guard app.user?.canReadClinicalData == true else { return }
        await history.load(app: app) { try await app.api.get(["pacientes", patientID, "antecedentes"]) }
    }
}
