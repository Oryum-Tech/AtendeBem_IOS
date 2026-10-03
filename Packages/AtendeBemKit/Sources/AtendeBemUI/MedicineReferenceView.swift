import AtendeBemCore
import SwiftUI

struct LARIMedicineReferenceTaskView: View {
    let command: String
    @Environment(AppState.self) private var app
    @State private var browser: MedicineReferenceBrowser?
    @State private var browserContext: UUID?
    @State private var browserUserID: String?
    @State private var term = ""
    @State private var field = MedicineReferenceQuery.Field.all
    @State private var includeInactive = false
    @State private var selectedID: String?
    @State private var didApplyCommand = false
    private var allowed: Bool { app.user?.canReadClinicalData == true }
    private var accessKey: String { "\(app.contextID)|\(app.user?.id ?? "")|\(allowed)" }
    private var query: MedicineReferenceQuery? { try? .init(term: term, field: field, includeInactive: includeInactive) }

    var body: some View {
        Group {
            if allowed { searchableContent }
            else { Form { RestrictedState() } }
        }
        .navigationTitle("Medicamentos e bulas").inlineTitle()
        .task(id: accessKey) { await prepare() }
        .onChange(of: allowed) { _, value in if !value { clear() } }
        .onChange(of: term) { _, _ in resetResults() }
        .onChange(of: field) { _, _ in resetResults() }
        .onChange(of: includeInactive) { _, _ in resetResults() }
        .navigationDestination(item: $selectedID) { id in
            if let browser, browserContext == app.contextID, browserUserID == app.user?.id, allowed {
                MedicineReferenceDetailView(id: id, browser: browser)
            } else { RestrictedState() }
        }
    }

    private var searchableContent: some View {
        referenceForm
        #if os(iOS)
            .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nome ou princípio ativo")
            .textInputAutocapitalization(.never)
        #else
            .searchable(text: $term, prompt: "Nome ou princípio ativo")
        #endif
            .autocorrectionDisabled()
            .onSubmit(of: .search) { submitSearch() }
    }

    private var referenceForm: some View {
        Form {
            if allowed, browserContext == app.contextID, browserUserID == app.user?.id, let browser {
                if browser.expired {
                    Section {
                        Text("O acesso ou a clínica mudou. Os resultados anteriores foram descartados.")
                        Button("Conferir acesso e reabrir busca") { Task { await prepare(force: true) } }
                    }
                } else {
                    searchSection(browser)
                    resultsSection(browser)
                    Section {
                        Text(MedicineReference.coverageDescription).font(.footnote).foregroundStyle(.secondary)
                    } header: { Text("Cobertura do catálogo") }
                }
            } else if !allowed {
                RestrictedState()
            } else {
                ProgressView("Preparando a busca…")
            }
        }
    }

    private func searchSection(_ browser: MedicineReferenceBrowser) -> some View {
        Section {
            Text("Revise o nome no campo de busca e toque em Buscar. Você escolherá o registro nos resultados.")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("Buscar em", selection: $field) {
                ForEach(MedicineReferenceQuery.Field.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Incluir registros inativos", isOn: $includeInactive)
            Button(action: submitSearch) { Label("Buscar no catálogo", systemImage: "magnifyingglass") }
                .disabled(query == nil).accessibilityIdentifier("lari.medicines.search")
                .accessibilityHint("Busca o termo revisado com os filtros selecionados, sem escolher um medicamento")
            if !term.isEmpty, query == nil {
                Text("Use entre 2 e 200 caracteres para buscar.").font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("Sua busca") } footer: {
            Text("Confirme produto, empresa e registro antes de abrir a bula. A busca considera apenas registros ativos, salvo quando você inclui os inativos.")
        }.disabled(browser.isSearching)
    }

    @ViewBuilder private func resultsSection(_ browser: MedicineReferenceBrowser) -> some View {
        if browser.isSearching { Section { ProgressView("Buscando no catálogo…").accessibilityIdentifier("lari.medicines.loading") } }
        if let error = browser.failure {
            Section {
                Text(message(for: error)).foregroundStyle(.red)
                if let attempted = browser.query {
                    Button("Tentar esta busca novamente") { Task { await load(attempted, browser: browser) } }
                        .disabled(browser.isSearching)
                        .accessibilityHint("Repete o mesmo termo, filtros e página")
                        .accessibilityIdentifier("lari.medicines.retry")
                }
            } header: { Text("Não foi possível carregar") }
        }
        if let page = browser.page, let searched = browser.query {
            Section {
                Text("Busca por “\(searched.term)” • \(searched.field.title)").font(.footnote).foregroundStyle(.secondary)
                Text(searched.includeInactive ? "Inclui registros inativos" : "Somente registros ativos").font(.caption)
                if page.itens.isEmpty {
                    Text("Nenhum registro encontrado nesta busca.")
                    Text("Confira o nome ou tente o princípio ativo. A ausência no catálogo não comprova que o medicamento não tenha registro ou bula.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(page.itens) { item in
                    Button { selectedID = item.id } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.nomeProduto).font(.headline).foregroundStyle(.primary)
                                Text(item.principioAtivo?.trimmedOrNil ?? "Princípio ativo não informado").font(.subheadline).foregroundStyle(.secondary)
                                Text(item.empresa?.trimmedOrNil ?? "Empresa não informada").font(.caption).foregroundStyle(.secondary)
                                Text("Situação no catálogo: \(item.situacao)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityHint("Abrir a ficha e conferir o registro antes de acessar o Bulário")
                }
            } header: { Text("\(page.total) registros na busca") }
            if page.hasPrevious || page.hasNext {
                Section {
                    Text("Página \(page.page) • Registros \(page.firstItemNumber) a \(page.lastItemNumber)").font(.footnote)
                    if page.hasPrevious {
                        Button("Página anterior") {
                            guard let query = try? searched.moving(to: page.page - 1) else { return }
                            Task { await load(query, browser: browser) }
                        }.accessibilityLabel("Página anterior, página \(page.page - 1)")
                    }
                    if page.hasNext {
                        Button("Próxima página") {
                            guard let query = try? searched.moving(to: page.page + 1) else { return }
                            Task { await load(query, browser: browser) }
                        }.accessibilityLabel("Próxima página, página \(page.page + 1)")
                    }
                }.disabled(browser.isSearching)
            }
        }
    }

    private func prepare(force: Bool = false) async {
        if !force, browser != nil, browserContext == app.contextID, browserUserID == app.user?.id, allowed { return }
        clear()
        guard allowed, let user = app.user else { return }
        let context = app.contextID
        let apiContext = await app.api.requestContextID()
        guard !Task.isCancelled, context == app.contextID, allowed, app.user?.id == user.id else { return }
        browserContext = context
        browserUserID = user.id
        browser = MedicineReferenceBrowser(api: app.api, context: apiContext) { [weak app] in
            app?.contextID == context && app?.user?.id == user.id && app?.user?.canReadClinicalData == true
        }
        if !didApplyCommand {
            didApplyCommand = true
            term = MedicineReferenceIntent.searchTerm(from: command) ?? ""
        }
    }
    private func clear() {
        browser?.invalidate(); browser = nil; browserContext = nil; browserUserID = nil; selectedID = nil
        term = ""; field = .all; includeInactive = false
    }
    private func resetResults() { browser?.clearSearch(); selectedID = nil }
    private func submitSearch() {
        guard let browser, !browser.isSearching, !browser.expired, let query else { return }
        Task { await load(query, browser: browser) }
    }
    private func load(_ query: MedicineReferenceQuery, browser: MedicineReferenceBrowser) async {
        guard allowed, browserContext == app.contextID, browserUserID == app.user?.id, let user = app.user else { clear(); return }
        guard query.term == self.query?.term, query.field == field, query.includeInactive == includeInactive else { return }
        await browser.search(query, user: user)
        if let error = browser.failure { await app.checkSession(after: error) }
    }
}

private struct MedicineReferenceDetailView: View {
    let id: String
    let browser: MedicineReferenceBrowser
    @Environment(AppState.self) private var app
    private var allowed: Bool { app.user?.canReadClinicalData == true }
    var body: some View {
        Form {
            if !allowed || browser.expired {
                RestrictedState()
            } else if browser.isLoadingDetail {
                ProgressView("Conferindo a ficha do medicamento…")
            } else if let item = browser.detail, item.id == id {
                identitySection(item)
                Section("Bula oficial") {
                    Text(MedicineReference.leafletLimitation)
                    if let url = item.officialLeafletSearchURL {
                        Link(destination: url) { Label("Consultar registro no Bulário da ANVISA", systemImage: "arrow.up.right.square") }
                            .accessibilityIdentifier("lari.medicines.officialLeaflet")
                        Text("Abre o site oficial para buscar este registro. Confira o produto e escolha a bula do profissional. O link não confirma a existência de uma bula, sua versão ou que ela foi lida pela LARI.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Esta ficha não tem registro no formato de 9 dígitos suportado pelo link de busca. O valor original, quando informado, permanece na identificação. O número do processo e o identificador do catálogo não substituem o registro.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if item.concentracao?.trimmedOrNil != nil || item.formaFarmaceutica?.trimmedOrNil != nil {
                    Section {
                        referenceField("Concentração", item.concentracao)
                        referenceField("Forma", item.formaFarmaceutica)
                    } header: { Text("Informações extraídas do nome") } footer: {
                        Text("O serviço deriva estes campos do nome do produto. Não equivalem à apresentação oficial da ANVISA nem confirmam dose, via ou posologia.")
                    }
                }
                Section("Origem e cobertura") {
                    Text(MedicineReference.sourceDescription)
                    if let date = item.ingestionDate {
                        LabeledContent("Atualização no catálogo", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Text("A data é da atualização do registro no serviço AtendeBem. Não informa quando a ANVISA revisou o registro nem quando a bula foi publicada ou atualizada.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(MedicineReference.coverageDescription).font(.footnote).foregroundStyle(.secondary)
                    referenceField("Identificador do catálogo", item.id)
                }
            } else {
                Section {
                    Text(browser.detailFailure.map { message(for: $0) } ?? "Não foi possível exibir a ficha deste medicamento.")
                        .foregroundStyle(.red)
                    Button("Consultar ficha novamente") { Task { await load() } }
                }
            }
        }
        .navigationTitle("Ficha do medicamento").inlineTitle()
        .task(id: id) { await load() }
        .onDisappear { browser.clearDetail() }
        .onChange(of: allowed) { _, value in if !value { browser.invalidate() } }
        .onChange(of: app.contextID) { _, _ in browser.invalidate() }
    }
    private func identitySection(_ item: MedicineReference) -> some View {
        Section {
            Text(item.nomeProduto).font(.title3.bold()).textSelection(.enabled)
            referenceField("Princípio ativo", item.principioAtivo)
            referenceField("Empresa", item.empresa)
            referenceField("CNPJ", item.empresaCnpj)
            referenceField("Registro", item.numeroRegistro)
            referenceField("Processo", item.numeroProcesso)
            referenceField("Situação no catálogo", item.situacao)
            referenceField("Vencimento informado", item.vencimentoRegistro)
            referenceField("Categoria regulatória", item.categoriaRegulatoria)
            referenceField("Classe terapêutica", item.classeTerapeutica)
        } header: { Text("Identificação") } footer: {
            Text("A situação é a registrada no catálogo; confirme a regularidade atual na fonte oficial. Classe terapêutica não determina a indicação para um paciente.")
        }
    }
    private func referenceField(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value?.trimmedOrNil ?? "Não informado").textSelection(.enabled)
        }
    }
    private func load() async {
        guard allowed, let user = app.user else { browser.invalidate(); return }
        await browser.open(id: id, user: user)
        if let error = browser.detailFailure { await app.checkSession(after: error) }
    }
}
