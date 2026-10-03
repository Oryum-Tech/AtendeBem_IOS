import AtendeBemCore
import SwiftUI

struct ClinicalTemplateEditor: View {
    let onSaved: (ClinicalTemplate) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var original: ClinicalTemplate
    @State private var draft: ClinicalTemplateDraft
    @State private var outcome = WriteOutcome.ready
    @State private var error: String?
    @State private var latest: ClinicalTemplate?
    @State private var confirmed = false
    @State private var discard = false

    init(model: ClinicalTemplate, onSaved: @escaping (ClinicalTemplate) -> Void) {
        self.onSaved = onSaved
        _original = State(initialValue: model)
        _draft = State(initialValue: ClinicalTemplateDraft(model))
    }

    private var patch: ClinicalTemplatePatch { ClinicalTemplatePatch(original: original, draft: draft) }
    var body: some View {
        Form {
            Section("Identificação") {
                TextField("Nome do modelo", text: $draft.name)
                TextField("Condição (opcional)", text: $draft.condition)
                TextField("CID-10 separados por vírgula (opcional)", text: $draft.codes)
                    .autocorrectionDisabled()
                LabeledContent("Tipo", value: draft.type.title)
            }
            if draft.type == .prescription || draft.type == .protocolPlan {
                Section("Medicamentos") {
                    ForEach($draft.medicines) { $item in
                        DisclosureGroup(item.name.trimmedOrNil ?? "Novo medicamento") {
                            TemplateMedicineFields(item: $item)
                            Button("Remover medicamento", role: .destructive) {
                                let id = item.id
                                draft.medicines.removeAll { $0.id == id }
                            }
                        }
                    }
                    Button { draft.medicines.append(TemplateMedicineDraft()) } label: { Label("Adicionar medicamento", systemImage: "plus") }
                        .disabled(draft.medicines.count >= 50)
                }
            }
            if draft.type == .exams || draft.type == .protocolPlan {
                Section("Exames") {
                    ForEach($draft.exams) { $item in
                        DisclosureGroup(item.description.trimmedOrNil ?? "Novo exame") {
                            TextField("Descrição", text: $item.description, axis: .vertical)
                            TextField("Código TUSS (opcional)", text: $item.code)
                            TextField("Justificativa (opcional)", text: $item.reason, axis: .vertical)
                            Button("Remover exame", role: .destructive) {
                                let id = item.id
                                draft.exams.removeAll { $0.id == id }
                            }
                        }
                    }
                    Button { draft.exams.append(TemplateExamDraft()) } label: { Label("Adicionar exame", systemImage: "plus") }
                        .disabled(draft.exams.count >= 50)
                }
            }
            Section("Orientações") { TextField("Orientações do modelo", text: $draft.guidance, axis: .vertical).lineLimit(4...12) }
            Section {
                Toggle("Revisei o conteúdo e não há dados que identifiquem um paciente", isOn: $confirmed)
            } footer: {
                Text(original.compartilhado
                     ? "Este modelo já é compartilhado. As alterações também ficarão visíveis aos colegas que têm acesso. Documentos já criados permanecem como foram emitidos."
                     : "O modelo permanece privado na sua biblioteca. Documentos já criados permanecem como foram emitidos.")
            }
            Section {
                if let validation = draft.validationError { Text(validation).font(.footnote).foregroundStyle(.secondary) }
                WriteStatus(outcome: outcome, error: error)
                if latest != nil {
                    Button("Carregar versão atual e descartar esta edição") {
                        if let latest { original = latest; draft = ClinicalTemplateDraft(latest) }
                        latest = nil; error = nil; confirmed = false
                    }
                }
                if outcome == .uncertain {
                    Text("Feche e atualize a biblioteca para conferir o modelo antes de fazer outra alteração.").font(.footnote)
                }
            }
        }
        .disabled(!outcome.canSubmit)
        .navigationTitle("Editar modelo").inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { if patch.hasChanges { discard = true } else { dismiss() } }.disabled(outcome == .sending)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { Task { await save() } }
                    .disabled(!original.meu || !patch.hasChanges || draft.validationError != nil || !confirmed || !outcome.canSubmit || latest != nil)
            }
        }
        .interactiveDismissDisabled(patch.hasChanges || outcome == .sending)
        .confirmationDialog("Descartar as alterações deste modelo?", isPresented: $discard, titleVisibility: .visible) {
            Button("Descartar alterações", role: .destructive) { dismiss() }
            Button("Continuar editando", role: .cancel) {}
        }
    }

    private func save() async {
        guard original.meu, app.user?.canPrescribe == true, outcome.canSubmit, patch.hasChanges, draft.validationError == nil, confirmed else { return }
        let context = app.contextID
        let body = patch
        outcome = .sending; error = nil
        var writeStarted = false
        defer { if outcome == .sending { outcome = .ready } }
        do {
            let apiContext = await app.api.requestContextID()
            guard app.contextID == context else { return }
            // The service has no conditional revision header. Check its current version before a partial PATCH.
            let models: [ClinicalTemplate] = try await app.api.get(["templates-clinicos"], query: [
                .init(name: "incluirCompartilhados", value: "false"),
                .init(name: "q", value: original.nome), .init(name: "tipo", value: original.tipo.rawValue)
            ])
            try Task.checkCancellation()
            guard app.contextID == context else { return }
            guard let current = models.first(where: { $0.id == original.id && $0.meu }) else {
                error = "Não foi possível localizar esta versão do modelo na busca. Ele pode ter sido renomeado. Feche e atualize a biblioteca antes de tentar novamente."; return
            }
            guard current.atualizadoEm == original.atualizadoEm else {
                latest = current; error = "O modelo foi alterado desde que você abriu esta tela. Carregue a versão atual para revisar antes de salvar."; return
            }
            writeStarted = true
            let saved: ClinicalTemplate = try await app.api.patch(["templates-clinicos", original.id], body: body, expectedContext: apiContext)
            guard app.contextID == context else { return }
            guard saved.id == original.id, saved.meu else { throw APIError.invalidResponse }
            outcome = .succeeded; onSaved(saved); dismiss()
        } catch {
            guard app.contextID == context else { return }
            outcome = writeStarted ? WriteOutcome.afterFailure(error) : .ready
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

private struct TemplateMedicineFields: View {
    @Binding var item: TemplateMedicineDraft
    var body: some View {
        TextField("Medicamento", text: $item.name)
        TextField("Posologia e via de administração", text: $item.dosage, axis: .vertical)
        TextField("Dose (opcional)", text: $item.dose)
        TextField("Frequência (opcional)", text: $item.frequency)
        TextField("Duração (opcional)", text: $item.duration)
        TextField("Quantidade (opcional)", text: $item.quantity)
        TextField("Instruções (opcional)", text: $item.instructions, axis: .vertical)
        Toggle("Uso contínuo", isOn: Binding(get: { item.continuous == true }, set: { item.continuous = $0 }))
    }
}
