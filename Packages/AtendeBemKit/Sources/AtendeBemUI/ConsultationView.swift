import AtendeBemCore
import SwiftUI

struct ConsultationView: View {
    let patient: Patient
    let appointment: Appointment?
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var workflow: ConsultationWorkflow?
    @State private var sessionID: UUID?
    @State private var showCIDSearch = false
    @State private var showComparison = false
    @State private var showLeave = false
    @State private var confirmUseServer = false
    @State private var reviewSheetVisible = false
    @State private var assistantSession: AssistantSession?
    @State private var preparingAssistant = false
    @State private var showTranscription = false

    private struct AssistantSession: Identifiable {
        let id = UUID()
        let workflow: ConsultationWorkflow
        let assistant: ConsultationAssistant
    }

    var body: some View {
        Group {
            if app.user?.canReadClinicalData != true { RestrictedState() }
            else if let workflow { consultation(workflow) }
            else { ProgressView("Abrindo consulta…") }
        }
        .navigationTitle("Consulta").inlineTitle()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Voltar", systemImage: "chevron.backward") { requestLeave() }
                    .disabled(workflow?.isBusy == true)
            }
        }
        .interactiveDismissDisabled(workflow?.shouldProtectExit == true)
        .task { await initialize() }
        .onChange(of: app.contextID) { _, _ in
            workflow?.invalidate(); showComparison = false; showCIDSearch = false
            assistantSession?.assistant.invalidate(); assistantSession = nil; showTranscription = false
        }
        .confirmationDialog("Sair da consulta?", isPresented: $showLeave, titleVisibility: .visible) {
            if let workflow, workflow.canSave {
                Button("Salvar rascunho e sair") {
                    Task {
                        await workflow.save(); await afterOperation(workflow)
                        if workflow.phase == .ready && !workflow.hasUnsavedChanges && workflow.comparison == nil { dismiss() }
                    }
                }
            }
            Button("Continuar depois neste aplicativo") {
                guard workflow?.isBusy != true else { return }
                dismiss()
            }
            Button("Continuar na consulta", role: .cancel) {}
            if let workflow, ![.uncertainSave, .uncertainConfirmation].contains(workflow.phase) {
                Button("Descartar alterações deste aplicativo e sair", role: .destructive) {
                    guard let sessionID, app.consultations.discard(id: sessionID) else { return }
                    dismiss()
                }
            }
        } message: {
            Text([ConsultationWorkflow.Phase.uncertainSave, .uncertainConfirmation].contains(workflow?.phase ?? .ready)
                 ? "O resultado do envio ainda precisa ser conferido. A consulta será mantida nesta sessão para conferir o servidor sem repetir a operação. Encerrar o aplicativo, sair da conta ou trocar de clínica perde essa recuperação local."
                 : "Continuar depois mantém as anotações somente nesta sessão. Elas se perdem ao encerrar o aplicativo, sair da conta ou trocar de clínica. Salve para sincronizar com a web. Descartar não apaga o rascunho já salvo no servidor.")
        }
        .sheet(isPresented: $showCIDSearch) {
            NavigationStack {
                ClinicalCodePicker { code in
                    guard let workflow, workflow.canEdit else { return }
                    if !workflow.content.codes.contains(code.codigo) { workflow.content.codes.append(code.codigo) }
                }
            }
        }
        .sheet(isPresented: reviewPresented, onDismiss: {
            reviewSheetVisible = false
            if workflow?.comparison != nil { showComparison = true }
        }) {
            if let workflow, let review = workflow.review { reviewSheet(workflow, review: review) }
        }
        .sheet(isPresented: $showComparison) {
            if let workflow { comparisonSheet(workflow) }
        }
        .sheet(isPresented: $showTranscription) {
            if let workflow {
                NavigationStack { LARITranscriptionTaskView(command: "Transcrição desta consulta", workflow: workflow) }
            }
        }
        .sheet(item: $assistantSession) { session in
            NavigationStack {
                ConsultationAssistantView(patient: patient, workflow: session.workflow, assistant: session.assistant)
            }
        }
    }

    private func consultation(_ workflow: ConsultationWorkflow) -> some View {
        Form {
            Section {
                LabeledContent("Paciente", value: patient.nome)
                LabeledContent("Clínica", value: app.clinicName)
                if let name = app.user?.nome { LabeledContent("Profissional", value: name) }
            }
            statusSection(workflow)
            Section {
                LariSummaryButton(patient: patient)
                    .disabled(workflow.isBusy)
            } footer: {
                Text("Consulte fatos e trechos de origem antes ou durante o atendimento. Gerar o resumo não modifica estas anotações.")
            }
            if workflow.phase == .confirmed, let evolution = workflow.confirmed {
                ConsultationContentSummary(content: ConsultationContent(evolution))
                Section {
                    if app.user?.canPrescribe == true {
                        NavigationLink { PrescriptionForm(patient: patient) } label: { Label("Preparar receita", systemImage: "pills") }
                    }
                    if app.user?.canRequestExam == true {
                        NavigationLink { ExamRequestForm(patient: patient) } label: { Label("Solicitar exames", systemImage: "cross.case") }
                    }
                    if app.user?.canIssueDocument == true {
                        NavigationLink { MedicalDocumentForm(patient: patient) } label: { Label("Preparar atestado ou documento", systemImage: "doc.text") }
                    }
                } header: { Text("Continuar o atendimento") } footer: {
                    Text("O paciente desta consulta será mantido nos formulários. Cada documento precisa da sua revisão e confirmação; nenhum será criado automaticamente.")
                }
                Section {
                    NavigationLink("Ver evoluções do paciente") { MedicalRecordView(patient: patient) }
                    NavigationLink("Documentos do paciente") { PatientDocumentsView(patient: patient) }
                    Button("Concluir esta revisão") {
                        if let sessionID { _ = app.consultations.discard(id: sessionID) }
                        dismiss()
                    }
                } footer: { Text("Esta evolução já foi registrada. Uma nova consulta deve ser iniciada separadamente para evitar duplicar a mesma nota.") }
            } else if workflow.loaded {
                Section("Anotações da consulta") {
                    TextField("Queixa principal (opcional)", text: contentBinding(workflow, \.complaint), axis: .vertical)
                    ForEach(workflow.content.displayedSections) { section in
                        ClinicalTextEditor(title: workflow.content.title(for: section), text: Binding(
                            get: { workflow.content.notes[section.id] ?? "" },
                            set: { workflow.content.notes[section.id] = $0 }
                        ))
                    }
                    TextField("CID-10 (separe por vírgulas)", text: Binding(
                        get: { workflow.content.codes.joined(separator: ", ") },
                        set: { workflow.content.codes = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() } }
                    )).clinicalCodeInput()
                    Button("Buscar CID-10") { showCIDSearch = true }
                }.disabled(!workflow.canEdit)
                if app.user?.canWriteClinicalDraft == true {
                    Section {
                        Button {
                            Task { await openAssistant(workflow) }
                        } label: {
                            if preparingAssistant { ProgressView("Abrindo assistência…") }
                            else { Label("Organizar anotações com a LARI", systemImage: "sparkles") }
                        }
                        .disabled(preparingAssistant || !workflow.canEdit || workflow.phase != .ready || workflow.comparison != nil)
                        .accessibilityIdentifier("consultation.assistant.open")
                        Button { showTranscription = true } label: { Label("Gravar e transcrever consulta", systemImage: "mic") }
                            .disabled(!workflow.canEdit || workflow.phase != .ready || workflow.comparison != nil)
                            .accessibilityIdentifier("consultation.transcription.open")
                    } footer: { Text("Escolha o texto a enviar e revise os trechos sugeridos antes de acrescentá-los à consulta. As anotações existentes serão preservadas.") }
                }
                Section {
                    Button("Salvar rascunho") {
                        Task { await workflow.save(); await afterOperation(workflow) }
                    }.disabled(!workflow.canSave)
                        .accessibilityIdentifier("consultation.saveDraft")
                    Button("Revisar evolução") {
                        workflow.prepareReview(); reviewSheetVisible = workflow.review != nil
                    }
                        .disabled(!workflow.canReview)
                        .accessibilityIdentifier("consultation.review")
                    if workflow.comparison != nil {
                        Button("Comparar com o servidor") { showComparison = true }.disabled(workflow.isBusy)
                    } else if workflow.phase == .uncertainConfirmation {
                        Button("Conferir confirmação no servidor") {
                            Task { await workflow.reconcileConfirmation(); await afterOperation(workflow) }
                        }
                    } else if !workflow.isBusy && workflow.phase != .expired {
                        Button("Conferir versão do servidor") {
                            Task { await workflow.compareWithServer(); await afterOperation(workflow) }
                        }
                    }
                } footer: {
                    Text("Salve para continuar em qualquer dispositivo. Anotações não salvas podem ser retomadas na aba Hoje durante esta sessão; encerrar o aplicativo, sair da conta ou trocar de clínica apaga essa cópia local. Revisar e confirmar não assina nem encerra o agendamento.")
                }
                Section("Consultar durante o atendimento") {
                    NavigationLink { PatientClinicalChartView(patient: patient) } label: {
                        Label("Problemas, medicações e sinais vitais", systemImage: "heart.text.clipboard")
                    }
                    NavigationLink { PatientTriageView(patient: patient) } label: {
                        Label("Triagem e queixa registrada", systemImage: "cross.case")
                    }
                    NavigationLink { PatientDocumentsView(patient: patient) } label: { Label("Documentos do paciente", systemImage: "doc.on.doc") }
                }
                PatientHistorySection(patientID: patient.id)
            }
        }
    }

    private func statusSection(_ workflow: ConsultationWorkflow) -> some View {
        Section {
            if workflow.isBusy {
                ProgressView(workflow.phase == .confirming ? "Conferindo e confirmando evolução…" : (workflow.phase == .saving ? "Salvando rascunho…" : "Conferindo servidor…"))
            } else if workflow.phase == .uncertainConfirmation {
                Label("Confirmação ainda não comprovada", systemImage: "exclamationmark.triangle")
                Text("Nenhum novo envio será feito nesta tela. Use a conferência abaixo para procurar a evolução já enviada.").font(.footnote)
            } else if workflow.phase == .uncertainSave {
                Label("Salvamento ainda não comprovado", systemImage: "exclamationmark.triangle")
                Text("Seu texto continua aqui. Compare com o servidor antes de salvar novamente.").font(.footnote)
            } else if workflow.phase == .confirmed {
                Label("Evolução registrada", systemImage: "checkmark.circle")
                Text("A confirmação não equivale a assinatura digital nem a conclusão do agendamento.").font(.footnote)
            } else if workflow.hasUnsavedChanges {
                Label("Alterações ainda não salvas", systemImage: "pencil.circle")
            } else if workflow.saved != nil {
                Label("Rascunho salvo no servidor", systemImage: "checkmark.icloud")
            } else if workflow.loaded { Text("A consulta ainda não tem anotações salvas.").foregroundStyle(.secondary) }
            if let saved = workflow.saved, let instant = saved.evolution.rascunhoSalvoEm {
                ClinicalTimestamp(label: "Última versão consultada", value: instant)
            }
            if let notice = workflow.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if let error = workflow.failure {
                Text(error is ConsultationFailure ? error.localizedDescription : message(for: error)).foregroundStyle(.red).font(.callout)
                if !workflow.loaded && workflow.phase != .expired {
                    Button("Tentar novamente") { Task { await workflow.load(); await afterOperation(workflow) } }
                }
            }
        }
    }

    private var reviewPresented: Binding<Bool> {
        Binding(get: { workflow?.review != nil }, set: { presented in
            if !presented, workflow?.isBusy != true { workflow?.cancelReview() }
        })
    }

    private func reviewSheet(_ workflow: ConsultationWorkflow, review: ConsultationSnapshot) -> some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Paciente", value: patient.nome)
                    LabeledContent("Clínica", value: app.clinicName)
                    Text("Confira todo o conteúdo antes de registrar esta evolução. Ela continuará sem assinatura digital e o agendamento manterá o estado atual.")
                }
                ConsultationContentSummary(content: review.content)
                Section {
                    Button {
                        Task { await workflow.confirmReviewed(); await afterOperation(workflow) }
                    } label: {
                        if workflow.isBusy { ProgressView("Confirmando…") } else { Text("Confirmar evolução sem assinar") }
                    }.disabled(workflow.isBusy || app.user?.canWriteClinicalDraft != true)
                        .accessibilityIdentifier("consultation.confirm")
                } footer: { Text("A versão do servidor será conferida novamente antes do envio. Evite editar esta mesma consulta em outro dispositivo durante a confirmação.") }
            }.navigationTitle("Revisar evolução").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Voltar à edição") { workflow.cancelReview() }.disabled(workflow.isBusy) } }
                .interactiveDismissDisabled(workflow.isBusy)
        }
    }

    private func comparisonSheet(_ workflow: ConsultationWorkflow) -> some View {
        NavigationStack {
            List {
                Section {
                    Text("Compare antes de escolher. Abrir esta tela não substitui nem envia suas anotações.")
                    LabeledContent("Paciente", value: patient.nome)
                }
                Section { Text("Texto desta tela").font(.title2.bold()) }
                ConsultationContentSummary(content: workflow.content)
                Section { Text("Versão do servidor").font(.title2.bold()) }
                if let latest = workflow.comparison?.server {
                    if let instant = latest.evolution.rascunhoSalvoEm {
                        Section { ClinicalTimestamp(label: "Salvo em", value: instant) }
                    }
                    ConsultationContentSummary(content: latest.content)
                    Section {
                        Button("Manter meu texto para salvar") { workflow.keepLocalVersion(); showComparison = false }
                            .disabled(!workflow.canKeepLocalVersion)
                        Button("Usar a versão do servidor", role: .destructive) { confirmUseServer = true }
                    } footer: {
                        Text(workflow.canKeepLocalVersion
                             ? "Manter seu texto não salva automaticamente. A próxima gravação conferirá novamente esta versão antes de enviar. Evite editar a mesma consulta em dois dispositivos ao mesmo tempo."
                             : "O rascunho aberto agora é outro registro. Não vamos substituir esse registro pelo texto da consulta anterior. Confira a linha do tempo.")
                    }
                } else {
                    Section {
                        Text("Não há rascunho aberto. Ele pode ter sido confirmado em outro dispositivo. Seu texto permanece nesta tela; confira a linha do tempo antes de criar outra evolução.")
                    }
                }
                Section {
                    NavigationLink("Conferir evoluções do paciente") { MedicalRecordView(patient: patient) }
                } footer: { Text("Suas anotações desta tela permanecem preservadas enquanto você consulta o histórico.") }
            }.navigationTitle("Comparar versões").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Continuar conferindo depois") { showComparison = false } } }
                .confirmationDialog("Substituir o texto desta tela?", isPresented: $confirmUseServer, titleVisibility: .visible) {
                    Button("Usar versão do servidor", role: .destructive) { workflow.useServerVersion(); showComparison = false }
                    Button("Preservar meu texto", role: .cancel) {}
                } message: { Text("As anotações locais serão substituídas pela versão exibida do servidor. Essa ação não grava nem confirma uma evolução.") }
        }
    }

    private func contentBinding(_ workflow: ConsultationWorkflow, _ key: WritableKeyPath<ConsultationContent, String>) -> Binding<String> {
        Binding(get: { workflow.content[keyPath: key] }, set: { workflow.content[keyPath: key] = $0 })
    }
    private func requestLeave() {
        if workflow?.shouldProtectExit == true { showLeave = true }
        else {
            if let sessionID, workflow?.content.hasContent != true || workflow?.phase == .confirmed {
                _ = app.consultations.discard(id: sessionID)
            }
            dismiss()
        }
    }
    @MainActor private func initialize() async {
        guard workflow == nil, let session = await app.consultationSession(patient: patient) else { return }
        sessionID = session.id; workflow = session.workflow
        // An existing instance includes any uncertain write; load is a no-op once loaded.
        await session.workflow.load(); await afterOperation(session.workflow)
    }
    @MainActor private func afterOperation(_ workflow: ConsultationWorkflow) async {
        if let error = workflow.failure { await app.checkSession(after: error) }
        if workflow.comparison != nil && !reviewSheetVisible { showComparison = true }
    }

    @MainActor private func openAssistant(_ workflow: ConsultationWorkflow) async {
        guard !preparingAssistant, workflow.canEdit, workflow.phase == .ready, workflow.comparison == nil,
              app.user?.canWriteClinicalDraft == true else { return }
        preparingAssistant = true
        defer { preparingAssistant = false }
        let context = app.contextID
        let apiContext = await app.api.requestContextID()
        guard app.contextID == context, app.user?.canWriteClinicalDraft == true,
              workflow.canEdit, workflow.phase == .ready, workflow.comparison == nil else { return }
        assistantSession = AssistantSession(workflow: workflow, assistant: ConsultationAssistant(
            api: app.api, context: apiContext, patientID: patient.id, baseline: workflow.content))
    }
}

private struct ClinicalTextEditor: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).frame(minHeight: 100).accessibilityLabel(title)
        }
    }
}

private struct ConsultationContentSummary: View {
    let content: ConsultationContent
    var body: some View {
        Section("Queixa principal") { Text(content.complaint.trimmedOrNil ?? "Não informada").textSelection(.enabled) }
        ForEach(content.displayedSections) { section in
            Section(content.title(for: section)) {
                Text(content.notes[section.id]?.trimmedOrNil ?? "Sem anotação nesta seção").textSelection(.enabled)
            }
        }
        Section("CID-10") { Text(content.codes.filter { !$0.isEmpty }.isEmpty ? "Não informado" : content.codes.joined(separator: ", ")).textSelection(.enabled) }
    }
}
