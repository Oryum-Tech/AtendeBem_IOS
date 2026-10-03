import AtendeBemCore
import SwiftUI

/// A review workspace for one captured consultation. It never saves or confirms an evolution.
struct ConsultationAssistantView: View {
    let patient: Patient
    let workflow: ConsultationWorkflow
    @Bindable var assistant: ConsultationAssistant
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sendingTask: Task<Void, Never>?
    @State private var applying = false
    @State private var applicationError: String?
    @State private var showLeave = false
    @State private var confirmCopy = false
    @State private var confirmNewSuggestion = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Consulta de", value: patient.nome)
                LabeledContent("Clínica", value: app.clinicName)
                Text("Organize suas anotações em Subjetivo, Objetivo, Avaliação e Plano. Você escolhe o texto a enviar e revisa cada trecho antes de acrescentá-lo à consulta.")
                Text("O prontuário não será consultado automaticamente. Envie apenas informações necessárias e remova nomes, documentos e outros identificadores do texto abaixo.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if app.user?.canWriteClinicalDraft != true {
                Section { Text("Seu perfil nesta clínica não permite usar a assistência nesta consulta.").foregroundStyle(.red) }
            }
            if !assistant.isCurrent(workflow.content) {
                Section {
                    Label("A consulta foi alterada", systemImage: "exclamationmark.triangle")
                    Text("A resposta não poderá ser aplicada a esta versão. Suas anotações da consulta foram preservadas. Feche a assistência e abra-a novamente para partir da versão atual.")
                }
            }
            inputSection
            Section {
                AIProcessingNotice(includesPatient: false, agreed: $assistant.agreedToProcessing)
            }.disabled(assistant.phase == .generating || applying)
            generationSection
            if let suggestion = assistant.suggestion {
                reviewSection(suggestion)
                ForEach(assistant.availableSectionIDs, id: \.self) { key in sectionReview(key) }
                if !suggestion.cid10Candidatos.isEmpty {
                    Section {
                        ForEach(Array(suggestion.cid10Candidatos.enumerated()), id: \.offset) { _, candidate in
                            Text("\(candidate.codigo) — \(candidate.descricao)")
                        }
                    } header: { Text("Códigos sugeridos para conferência") } footer: {
                        Text("Esses códigos não serão acrescentados à consulta. Se forem pertinentes após avaliação clínica, selecione-os no campo CID-10 da consulta.")
                    }
                }
                if !suggestion.citacoes.isEmpty { citationsSection(suggestion) }
                Section {
                    Button {
                        Task { await applySelection() }
                    } label: {
                        if applying { ProgressView("Acrescentando à consulta…") }
                        else { Label("Acrescentar seções selecionadas", systemImage: "text.badge.plus") }
                    }
                    .disabled(applying || assistant.selectedSections.isEmpty || !canUseAssistant || assistant.phase != .reviewing)
                    .accessibilityIdentifier("consultation.assistant.apply")
                } footer: {
                    Text("Os trechos selecionados serão acrescentados às respectivas seções, preservando seu texto, a queixa e os CIDs. O resultado ficará somente no rascunho desta tela; você ainda deverá revisar, salvar e confirmar a evolução.")
                }
            }
            if let applicationError {
                Section { Text(applicationError).foregroundStyle(.red).accessibilityIdentifier("consultation.assistant.applicationError") }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("LARI nesta consulta").inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") { requestLeave() }.disabled(applying)
            }
        }
        .interactiveDismissDisabled(!assistant.text.isEmpty || assistant.suggestion != nil || assistant.phase == .generating || applying)
        .confirmationDialog("Fechar a assistência?", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Continuar revisando", role: .cancel) {}
            Button("Descartar esta assistência", role: .destructive) {
                sendingTask?.cancel(); assistant.cancelGeneration(); dismiss()
            }
        } message: {
            Text("O texto preparado e a resposta desta assistência sairão da tela. As anotações da consulta permanecem como estão. Se houve um envio, o serviço ainda pode concluir o processamento.")
        }
        .confirmationDialog("Usar as anotações atuais?", isPresented: $confirmCopy, titleVisibility: .visible) {
            Button("Copiar para o texto a enviar", role: .destructive) { assistant.useCurrentNotes(); applicationError = nil }
            Button("Preservar texto a enviar", role: .cancel) {}
        } message: { Text("Isso substitui apenas o texto a enviar e descarta a sugestão desta assistência. As anotações da consulta não serão alteradas nem enviadas nesta etapa.") }
        .confirmationDialog("Gerar outra sugestão?", isPresented: $confirmNewSuggestion, titleVisibility: .visible) {
            Button("Enviar texto e gerar outra sugestão") { startGenerating() }
            Button("Continuar revisando esta resposta", role: .cancel) {}
        } message: { Text("Uma nova solicitação será enviada. As edições feitas na resposta atual serão descartadas. A consulta continuará preservada.") }
        .onDisappear { sendingTask?.cancel(); assistant.cancelGeneration() }
        .onChange(of: app.contextID) { _, _ in
            sendingTask?.cancel(); assistant.invalidate(); dismiss()
        }
    }

    private var canUseAssistant: Bool {
        app.user?.canWriteClinicalDraft == true && workflow.canEdit && workflow.phase == .ready
            && workflow.comparison == nil && assistant.isCurrent(workflow.content)
    }

    private var inputSection: some View {
        Section {
            Button("Usar anotações desta consulta") {
                if assistant.text.isEmpty && assistant.suggestion == nil { assistant.useCurrentNotes() }
                else { confirmCopy = true }
            }.disabled(!canUseAssistant || assistant.phase == .generating || applying || !assistant.baseline.hasContent)
                .accessibilityIdentifier("consultation.assistant.copyNotes")
            TextEditor(text: $assistant.text)
                .frame(minHeight: 160)
                .accessibilityLabel("Texto que será enviado à LARI")
                .accessibilityIdentifier("consultation.assistant.input")
                .disabled(assistant.phase == .generating || applying)
            Text("\(assistant.text.utf16.count) de \(ConsultationAssistant.maximumInputCharacters) caracteres")
                .font(.caption)
                .foregroundStyle(assistant.text.utf16.count > ConsultationAssistant.maximumInputCharacters ? Color.red : Color.secondary)
        } header: { Text("Texto a enviar") } footer: {
            Text("Somente este texto será enviado. Confira-o antes de gerar a sugestão. Editar o texto invalida a resposta anterior; nenhum trecho é cortado automaticamente.")
        }
    }

    private var generationSection: some View {
        Section {
            if assistant.phase == .generating {
                ProgressView("Organizando as anotações…")
                Button("Parar espera") { sendingTask?.cancel(); assistant.cancelGeneration() }
            } else {
                Button {
                    if assistant.suggestion == nil { startGenerating() } else { confirmNewSuggestion = true }
                } label: { Label(assistant.suggestion == nil ? "Gerar sugestão SOAP" : "Gerar outra sugestão", systemImage: "sparkles") }
                    .disabled(!assistant.canGenerate || !canUseAssistant || applying || sendingTask != nil)
                    .accessibilityIdentifier("consultation.assistant.generate")
            }
            if let error = assistant.failure {
                Text(error is ConsultationAssistantFailure ? error.localizedDescription : (error is CancellationError ? "A espera foi interrompida." : message(for: error)))
                    .foregroundStyle(.red)
                Text("O texto foi preservado. Se houve envio, ele pode ter sido processado; nenhuma solicitação será repetida automaticamente. Revise antes de decidir por um novo envio.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func reviewSection(_ suggestion: ConsultationAssistantSuggestion) -> some View {
        Section {
            Label("Revise antes de usar", systemImage: "person.badge.shield.checkmark")
            Text("Nenhuma seção está selecionada. Confira a resposta com o texto enviado, corrija o que for necessário e escolha apenas os trechos pertinentes ao atendimento.")
            Text(suggestion.disclaimer).font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Revisão da sugestão") }
    }

    private func sectionReview(_ key: String) -> some View {
        Section {
            Toggle("Acrescentar \(assistant.title(for: key))", isOn: Binding(
                get: { assistant.selectedSections.contains(key) },
                set: { value in
                    if value { assistant.selectedSections.insert(key) } else { assistant.selectedSections.remove(key) }
                }
            ))
            TextEditor(text: Binding(get: { assistant.reviewedNotes[key] ?? "" }, set: { assistant.reviewedNotes[key] = $0 }))
                .frame(minHeight: 120).accessibilityLabel("Revisar sugestão de \(assistant.title(for: key))")
            if let existing = assistant.baseline.notes[key], !existing.isEmpty {
                DisclosureGroup("Texto atual que será preservado") { Text(existing).textSelection(.enabled) }
            }
        } header: { Text(assistant.destinationTitle(for: key)) } footer: {
            Text("O texto revisado será acrescentado ao final desta seção. Não substitui o conteúdo atual.")
        }
        .disabled(applying || !canUseAssistant)
    }

    private func citationsSection(_ suggestion: ConsultationAssistantSuggestion) -> some View {
        Section {
            ForEach(Array(suggestion.citacoes.enumerated()), id: \.offset) { _, citation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(citation.fonte)
                    if let reference = citation.referencia {
                        if let url = URL(string: reference), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
                            Link(reference, destination: url)
                        } else { Text(reference) }
                    }
                }.font(.footnote)
            }
        } header: { Text("Referências retornadas pelo serviço") } footer: {
            Text("Essas referências não comprovam cada frase da sugestão. Confira o conteúdo antes de utilizá-lo.")
        }
    }

    private func requestLeave() {
        if !assistant.text.isEmpty || assistant.suggestion != nil || assistant.phase == .generating { showLeave = true }
        else { dismiss() }
    }

    private func startGenerating() {
        guard sendingTask == nil, canUseAssistant, assistant.canGenerate else { return }
        let context = app.contextID
        applicationError = nil
        sendingTask = Task {
            await assistant.generate(canWrite: app.user?.canWriteClinicalDraft == true)
            guard app.contextID == context else { return }
            sendingTask = nil
            if let error = assistant.failure { await app.checkSession(after: error) }
        }
    }

    @MainActor private func applySelection() async {
        guard !applying, canUseAssistant else { return }
        let context = app.contextID
        applying = true; applicationError = nil
        defer { applying = false }
        do {
            try await assistant.apply(to: workflow, patientID: patient.id, canWrite: app.user?.canWriteClinicalDraft == true)
            guard app.contextID == context else { return }
            dismiss()
        } catch {
            guard app.contextID == context else { return }
            applicationError = error is ConsultationAssistantFailure ? error.localizedDescription : message(for: error)
            await app.checkSession(after: error)
        }
    }
}
