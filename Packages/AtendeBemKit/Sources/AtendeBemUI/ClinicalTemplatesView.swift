import AtendeBemCore
import SwiftUI

struct ClinicalTemplatesView: View {
    var applyingType: ClinicalTemplateType?
    var onApply: ((ClinicalTemplate) -> Void)?
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var resource = RemoteResource<[ClinicalTemplate]>()
    @State private var search = ""
    @State private var selectedType: ClinicalTemplateType?
    @State private var onlyMine = false
    @State private var selected: ClinicalTemplate?
    private var queryKey: String { "\(search)|\(selectedType?.rawValue ?? applyingType?.rawValue ?? "")|\(onlyMine)" }
    var body: some View {
        Group {
            if app.user?.canPrescribe == true {
                List {
                    Section {
                        if applyingType == nil {
                            Picker("Tipo", selection: $selectedType) {
                                Text("Todos").tag(Optional<ClinicalTemplateType>.none)
                                ForEach(ClinicalTemplateType.allCases) { Text($0.title).tag(Optional($0)) }
                            }
                        }
                        Toggle("Apenas meus modelos", isOn: $onlyMine)
                    } footer: { Text("Modelos ajudam a preencher o documento. A indicação, o conteúdo e a assinatura continuam sob sua revisão.") }
                    Section {
                        ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                        if resource.error != nil { Button("Tentar novamente") { Task { await load() } } }
                    }
                    if let models = resource.value {
                        Section("Biblioteca") {
                            if models.count >= 200 { Label("A biblioteca retornou o limite de 200 modelos. Use a busca e o tipo para encontrar outros itens.", systemImage: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary) }
                            if models.isEmpty { ContentUnavailableView("Nenhum modelo retornado", systemImage: "doc.on.doc", description: Text("Você pode salvar seus itens como modelo ao preparar uma receita ou um pedido de exames.")) }
                            ForEach(models) { model in
                                Button { selected = model } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(model.nome).font(.headline).foregroundStyle(.primary)
                                        Text("\(model.tipo.title) · \(model.meu ? "Meu modelo" : "Compartilhado por colega")").font(.caption).foregroundStyle(.secondary)
                                        if let condition = model.condicao { Text(condition).font(.subheadline).foregroundStyle(.secondary) }
                                    }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }.searchable(text: $search, prompt: "Buscar nome ou condição")
            } else { RestrictedState() }
        }.navigationTitle(applyingType == nil ? "Modelos clínicos" : "Escolher modelo").inlineTitle()
        .task(id: queryKey) {
            do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() } catch { return }
            await load()
        }
        .refreshable { await load() }
        .toolbar { if onApply != nil { Button("Fechar") { dismiss() } } }
        .sheet(item: $selected) { model in
            NavigationStack {
                ClinicalTemplateDetail(model: model, applyingType: applyingType, onApply: onApply == nil ? nil : { value in
                    onApply?(value); dismiss()
                }, onChanged: { Task { await load() } })
            }
        }
    }
    private func load() async {
        guard app.user?.canPrescribe == true else { return }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count <= 120 else { resource.clear(); resource.error = "Use até 120 caracteres na busca."; return }
        var items: [URLQueryItem] = [.init(name: "incluirCompartilhados", value: onlyMine ? "false" : "true")]
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        if let type = applyingType ?? selectedType { items.append(.init(name: "tipo", value: type.rawValue)) }
        await resource.load(reset: true, app: app) { try await app.api.get(["templates-clinicos"], query: items) }
    }
}

private struct ClinicalTemplateDetail: View {
    @State var model: ClinicalTemplate
    let applyingType: ClinicalTemplateType?
    let onApply: ((ClinicalTemplate) -> Void)?
    let onChanged: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var copied = false
    var body: some View {
        List {
            Section {
                Text(model.nome).font(.title2.bold())
                Text(model.meu ? "Modelo da sua biblioteca" : "Modelo compartilhado por colega").foregroundStyle(.secondary)
                if copied { Label("Cópia privada criada na sua biblioteca", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                if let condition = model.condicao { Text(condition) }
                if !model.cid10.isEmpty { LabeledContent("CID-10 do modelo", value: model.cid10.joined(separator: ", ")) }
            }
            if !model.medicamentos.isEmpty {
                Section("Medicamentos") {
                    ForEach(Array(model.medicamentos.enumerated()), id: \.offset) { _, item in PrescriptionItemSummary(item: item) }
                }
            }
            if !model.exames.isEmpty {
                Section("Exames") {
                    ForEach(Array(model.exames.enumerated()), id: \.offset) { _, exam in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(exam.descricao).font(.headline)
                            if let code = exam.tuss { Text("TUSS: \(code)") }
                            if let reason = exam.justificativa { Text(reason) }
                        }
                    }
                }
            }
            if let guidance = model.orientacoes { Section("Orientações") { Text(guidance) } }
            if let applyingType, onApply != nil {
                Section {
                    WriteStatus(outcome: outcome, error: error)
                    Button("Adicionar ao formulário") { Task { await apply() } }
                        .disabled(!model.canApply(to: applyingType) || !outcome.canSubmit)
                        .accessibilityIdentifier("template.apply")
                } footer: { Text("Os itens serão acrescentados ao formulário aberto. Revise o conteúdo para este paciente antes de salvar e assinar. O CID do modelo não altera o diagnóstico da consulta.") }
            } else {
                Section { Text("Para usar um modelo, abra Receita ou Exames no paciente e toque em Escolher modelo. Protocolos com conteúdos mistos e modelos de orientações estão disponíveis para consulta nesta versão.").foregroundStyle(.secondary) }
            }
            Section {
                if applyingType == nil { WriteStatus(outcome: outcome, error: error) }
                Button { Task { await duplicate() } } label: { Label("Criar cópia privada", systemImage: "doc.on.doc") }
                    .disabled(!outcome.canSubmit)
                if model.meu {
                    Button { showEditor = true } label: { Label("Editar modelo", systemImage: "pencil") }
                        .disabled(!outcome.canSubmit)
                    Button("Excluir modelo", role: .destructive) { confirmDelete = true }
                        .disabled(!outcome.canSubmit)
                }
            } header: { Text("Minha biblioteca") } footer: {
                Text(model.meu ? "Editar ou excluir um modelo não modifica documentos já criados a partir dele." : "Para adaptar o conteúdo de um colega, crie uma cópia privada. O modelo original será preservado.")
            }
        }.navigationTitle("Revisar modelo").inlineTitle()
        .toolbar { Button("Fechar") { dismiss() }.disabled(outcome == .sending) }
        .interactiveDismissDisabled(outcome == .sending)
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                ClinicalTemplateEditor(model: model) { updated in model = updated; onChanged() }
            }
        }
        .confirmationDialog("Excluir \(model.nome)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir modelo", role: .destructive) { Task { await delete() } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("O modelo será removido da sua biblioteca e deixará de estar disponível aos colegas, se compartilhado. Receitas, exames e documentos já criados não serão excluídos.") }
    }
    private func apply() async {
        guard outcome.canSubmit, let type = applyingType, model.canApply(to: type), app.user?.canPrescribe == true else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let current: ClinicalTemplate = try await app.api.post(["templates-clinicos", model.id, "usar"], body: [String: String]())
            guard app.contextID == context else { return }
            guard current.id == model.id, current.canApply(to: type) else { throw APIError.invalidResponse }
            guard model.hasSameContent(as: current) else {
                model = current; outcome = .ready; onChanged()
                error = "Este modelo foi alterado desde que você o abriu. Confira o conteúdo atualizado antes de usar. Nada foi aplicado ao documento."
                return
            }
            outcome = .succeeded
            onApply?(current); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error); await app.checkSession(after: error)
        }
    }

    private func duplicate() async {
        guard outcome.canSubmit, app.user?.canPrescribe == true else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let copy: ClinicalTemplate = try await app.api.post(["templates-clinicos", model.id, "duplicar"])
            guard context == app.contextID else { return }
            guard copy.id != model.id, copy.meu, !copy.compartilhado else { throw APIError.invalidResponse }
            model = copy; copied = true; outcome = .ready; onChanged()
        } catch {
            guard context == app.contextID else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error); await app.checkSession(after: error)
        }
    }

    private func delete() async {
        guard model.meu, outcome.canSubmit, app.user?.canPrescribe == true else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        var writeStarted = false
        defer { if outcome == .sending { outcome = .ready } }
        do {
            let apiContext = await app.api.requestContextID()
            guard app.contextID == context else { return }
            let models: [ClinicalTemplate] = try await app.api.get(["templates-clinicos"], query: [
                .init(name: "incluirCompartilhados", value: "false"),
                .init(name: "q", value: model.nome), .init(name: "tipo", value: model.tipo.rawValue)
            ])
            try Task.checkCancellation()
            guard context == app.contextID else { return }
            guard let current = models.first(where: { $0.id == model.id && $0.meu }) else {
                error = "Não foi possível localizar esta versão do modelo na busca. Nenhuma exclusão foi solicitada. Atualize a biblioteca e localize o modelo novamente."; return
            }
            guard current.atualizadoEm == model.atualizadoEm else {
                model = current; error = "O modelo mudou desde que você o abriu. Revise a versão atual antes de confirmar a exclusão novamente."; return
            }
            writeStarted = true
            let _: EmptyResponse = try await app.api.delete(["templates-clinicos", model.id], expectedContext: apiContext)
            guard context == app.contextID else { return }
            outcome = .succeeded; onChanged(); dismiss()
        } catch {
            guard context == app.contextID else { return }
            outcome = writeStarted ? WriteOutcome.afterFailure(error) : .ready
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

struct PrescriptionItemSummary: View {
    let item: PrescriptionItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.medicamento).font(.headline)
            Text(item.posologia)
            if let quantity = item.quantidade { Text("Quantidade: \(quantity)") }
            if let dose = item.dose { Text("Dose: \(dose)") }
            if let frequency = item.frequencia { Text("Frequência: \(frequency)") }
            if let duration = item.duracao { Text("Duração: \(duration)") }
            if let instructions = item.instrucoes { Text(instructions) }
            if item.usoContinuo == true { Text("Uso contínuo").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct SaveClinicalTemplateView: View {
    let type: ClinicalTemplateType
    var medicines: [PrescriptionItem] = []
    var exams: [TemplateExam] = []
    var guidance: String?
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmed = false
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("Nome do modelo", text: $name)
                LabeledContent("Tipo", value: type.title)
                Text("O modelo será salvo na sua biblioteca, sem compartilhar com colegas.").foregroundStyle(.secondary)
            }
            if !medicines.isEmpty { Section("Medicamentos") { ForEach(Array(medicines.enumerated()), id: \.offset) { _, item in PrescriptionItemSummary(item: item) } } }
            if !exams.isEmpty { Section("Exames") { ForEach(Array(exams.enumerated()), id: \.offset) { _, item in Text(item.descricao) } } }
            if let guidance { Section("Orientações do modelo") { Text(guidance) } }
            Section {
                Toggle("Revisei e não há nome, diagnóstico individual ou outros dados que identifiquem o paciente neste modelo", isOn: $confirmed)
                WriteStatus(outcome: outcome, error: error)
                if outcome == .succeeded { Label("Modelo salvo na sua biblioteca.", systemImage: "checkmark.circle") }
                Button("Salvar modelo") { Task { await save() } }
                    .disabled(name.trimmedOrNil == nil || name.count > 120 || !confirmed || !outcome.canSubmit)
            }
        }.navigationTitle("Salvar como modelo").inlineTitle()
        .toolbar { Button("Fechar") { dismiss() }.disabled(outcome == .sending) }
        .interactiveDismissDisabled(outcome == .sending)
    }
    private func save() async {
        guard let name = name.trimmedOrNil, name.count <= 120, confirmed, outcome.canSubmit, app.user?.canPrescribe == true else { return }
        let context = app.contextID
        outcome = .sending; error = nil
        do {
            let _: ClinicalTemplate = try await app.api.post(["templates-clinicos"], body: CreateClinicalTemplate(type: type, name: name, medicines: medicines, exams: exams, guidance: guidance))
            guard app.contextID == context else { return }
            outcome = .succeeded
        } catch {
            guard app.contextID == context else { return }
            outcome = WriteOutcome.afterFailure(error); self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}
