import AtendeBemCore
import SwiftUI

struct ClinicalActionsLoader: View {
    let patientID: String
    let appointment: Appointment?
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<Patient>()

    var body: some View {
        Group {
            if let patient = resource.value {
                ClinicalActionsView(patient: patient, appointment: appointment)
            } else if let error = resource.error {
                RetryState(title: "Não foi possível abrir o atendimento", detail: error) {
                    Task { await load() }
                }
            } else {
                ProgressView("Abrindo atendimento…")
            }
        }
        .task { await load() }
    }

    private func load() async {
        await resource.load(app: app) { try await app.api.get(["pacientes", patientID]) }
    }
}

struct ClinicalActionsView: View {
    let patient: Patient
    let appointment: Appointment?
    @Environment(AppState.self) private var app

    var body: some View {
        List {
            Section("Atendimento") {
                NavigationLink {
                    ConsultationView(patient: patient, appointment: appointment)
                } label: {
                    Label("Realizar consulta", systemImage: "stethoscope")
                }
                if let appointment, appointment.canal == "teleconsulta" {
                    NavigationLink {
                        TeleconsultationView(appointment: appointment, patientName: patient.nome)
                    } label: {
                        Label("Entrar na teleconsulta", systemImage: "video")
                    }
                }
            }
            Section {
                NavigationLink { PatientDocumentsView(patient: patient) } label: { Label("Documentos do paciente", systemImage: "doc.on.doc") }
            }
            Section("Emitir documento") {
                if app.user?.canPrescribe == true {
                    NavigationLink { PrescriptionForm(patient: patient) } label: { Label("Receita", systemImage: "pills") }
                }
                if app.user?.canIssueDocument == true {
                    NavigationLink { MedicalDocumentForm(patient: patient) } label: { Label("Atestado ou declaração", systemImage: "doc.text") }
                }
                if app.user?.canRequestExam == true {
                    NavigationLink {
                        ExamRequestForm(patient: patient)
                    } label: {
                        Label("Solicitação de exames", systemImage: "cross.vial")
                    }
                }
            }
        }
        .navigationTitle("Atendimento")
        .inlineTitle()
    }
}

struct PrescriptionForm: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var templateSheet: ClinicalTemplateSheet?
    @State private var itemToEdit: PrescriptionEditSelection?
    @State private var type = "comum"
    @State private var allergies = RemoteResource<[Allergy]>()
    @State private var items: [PrescriptionItem] = []
    @State private var medicine = ""
    @State private var dosage = ""
    @State private var quantity = ""
    @State private var guidance = ""
    @State private var allergyJustification = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var createdDocument: ClinicalDocumentSnapshot?
    @State private var createdReview: DocumentReview?
    @State private var outcome = WriteOutcome.ready

    var body: some View {
        Form {
            Section("Paciente") { Text(patient.nome) }
            Section {
                Button("Escolher modelo de receita") { templateSheet = .choose }.disabled(!outcome.canSubmit)
                NavigationLink("Ajustar letra das receitas") { PrescriptionSettingsView() }
            }
            Section("Receita") {
                Picker("Tipo", selection: $type) {
                    Text("Comum").tag("comum")
                    Text("Controle especial").tag("controle_especial")
                    Text("Antimicrobiano").tag("antimicrobiano")
                }
                MedicineLookup(medicine: $medicine)
                TextField("Posologia", text: $dosage, axis: .vertical)
                TextField("Quantidade", text: $quantity)
                TextField("Orientações gerais", text: $guidance, axis: .vertical)
            }
            Section("Itens da receita") {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading) {
                        PrescriptionItemSummary(item: item)
                        HStack {
                            Button("Editar item") { itemToEdit = PrescriptionEditSelection(index: index, item: item) }
                            Spacer()
                            Button("Remover item", role: .destructive) { items.remove(at: index) }
                        }.buttonStyle(.borderless).disabled(!outcome.canSubmit)

                    }
                }
                Button("Adicionar medicamento à receita") {
                    guard let medicine = medicine.trimmedOrNil, let dosage = dosage.trimmedOrNil else { return }
                    items.append(PrescriptionItem(medicamento: medicine, posologia: dosage, quantidade: quantity.nilIfBlank))
                    self.medicine = ""; self.dosage = ""; quantity = ""
                }.disabled(medicine.trimmedOrNil == nil || dosage.trimmedOrNil == nil || !outcome.canSubmit)
            }
            if allergies.isLoading { ProgressView("Conferindo alergias…") }
            if let error = allergies.error { Text(error).foregroundStyle(.red); Button("Atualizar alergias") { Task { await loadAllergies() } } }
            if !(allergies.value ?? []).isEmpty {
                Section("Alergias registradas") {
                    ForEach(Array((allergies.value ?? []).enumerated()), id: \.offset) { _, allergy in
                        Label(allergy.substancia, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    TextField("Justificativa clínica, se aplicável", text: $allergyJustification, axis: .vertical)
                }
            }
            if !items.isEmpty {
                Section { Button("Salvar itens como modelo") { templateSheet = .save }.disabled(!outcome.canSubmit || items.count > 50 || medicine.trimmedOrNil != nil || dosage.trimmedOrNil != nil) }
            }
            submissionSection(title: "Salvar rascunho de receita", action: submit)
        }
        .navigationTitle("Nova receita")
        .inlineTitle()
        .interactiveDismissDisabled(isSaving)
        .task { await loadAllergies() }
        .sheet(item: $templateSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .choose:
                    ClinicalTemplatesView(applyingType: .prescription) { model in
                        guard outcome.canSubmit else { return }
                        items.append(contentsOf: model.medicamentos)
                        guidance = [guidance.trimmedOrNil, model.orientacoes].compactMap { $0 }.joined(separator: "\n")
                    }
                case .save: SaveClinicalTemplateView(type: .prescription, medicines: items, guidance: guidance.trimmedOrNil)
                }
            }
        }
        .sheet(item: $itemToEdit) { selection in
            NavigationStack {
                PrescriptionItemEditor(item: selection.item) { edited in
                    guard outcome.canSubmit, items.indices.contains(selection.index) else { return }
                    items[selection.index] = edited
                }
            }
        }
    }

    @ViewBuilder
    private func submissionSection(title: String, action: @escaping () async -> Void) -> some View {
        Section {
            WriteStatus(outcome: outcome, error: error)
            if let createdDocument {
                Label("Rascunho de receita salvo", systemImage: "checkmark.circle").foregroundStyle(.green)
                NavigationLink("Abrir documento criado") { ClinicalDocumentDetailView(patient: patient, kind: createdDocument.kind, documentID: createdDocument.serverID, existingReview: createdReview) }
            }
            Button { Task { await action() } } label: {
                if isSaving { ProgressView() } else { Text(title) }
            }
            .disabled(items.isEmpty || medicine.trimmedOrNil != nil || dosage.trimmedOrNil != nil || allergies.value == nil || allergies.error != nil || allergies.isLoading || isSaving || !outcome.canSubmit)
        } footer: {
            Text("Adicione cada medicamento à lista. Depois de salvar, abra o documento criado para revisar o rascunho, conferir o PDF e solicitar a assinatura.")
        }
    }

    private func loadAllergies() async {
        await allergies.load(app: app) { try await app.api.get(["pacientes", patient.id, "alergias"]) }
    }

    private func submit() async {
        guard let user = app.user, user.canPrescribe else { return }
        let professionalID = user.id
        guard outcome.canSubmit, !isSaving else { return }
        let context = app.contextID
        let apiContext = await app.api.requestContextID()
        guard context == app.contextID, outcome.canSubmit, !isSaving else { return }
        outcome = .sending
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let body = CreatePrescription(
                pacienteId: patient.id,
                profissionalId: professionalID,
                tipo: type,
                itens: items,
                orientacoes: guidance.nilIfBlank,
                justificativaAlergia: allergyJustification.nilIfBlank,
                id: UUID().uuidString
            )
            let result: Prescription = try await app.api.post(["receitas"], body: body, expectedContext: apiContext)
            guard context == app.contextID else { return }
            let document = ClinicalDocumentSnapshot(result)
            try document.validate(patientID: patient.id, authorID: professionalID)
            let evidence = try PrescriptionDraftEvidence(request: body, response: result)
            createdReview = DocumentReview(api: app.api, context: apiContext, kind: .prescription, documentID: result.id, patientID: patient.id, user: user, isContextCurrent: { app.contextID == context }, prescriptionEvidence: evidence)
            createdDocument = document
            outcome = .succeeded
        } catch {
            guard context == app.contextID else { return }
            outcome = WriteOutcome.afterFailure(error)
            self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

struct MedicalDocumentForm: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var type = "atestado"
    @State private var title = ""
    @State private var days = 1
    @State private var cid = ""
    @State private var details = ""
    @State private var cidAuthorized = false
    @State private var reviewed = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var createdDocument: ClinicalDocumentSnapshot?
    @State private var outcome = WriteOutcome.ready

    var body: some View {
        Form {
            Section("Documento") {
                Picker("Tipo", selection: $type) {
                    Text("Atestado").tag("atestado")
                    Text("Declaração").tag("declaracao")
                    Text("Comparecimento").tag("comparecimento")
                    Text("Documento livre").tag("documento")
                }
                if type == "documento" { TextField("Título", text: $title) }
                if type == "atestado" {
                    Stepper("Afastamento: \(days) dia(s)", value: $days, in: 1...365)
                    Toggle("Paciente autorizou incluir o CID neste documento", isOn: $cidAuthorized)
                    TextField("CID (opcional e mediante autorização)", text: $cid).disabled(!cidAuthorized)
                        .clinicalCodeInput()
                }
                TextField("Descrição", text: $details, axis: .vertical).lineLimit(4...10)
            }
            Section {
                Toggle("Revisei o paciente, o texto e o período antes da emissão", isOn: $reviewed)
                WriteStatus(outcome: outcome, error: error)
                if let createdDocument {
                    Label("Documento salvo pelo serviço", systemImage: "checkmark.circle").foregroundStyle(.green)
                    NavigationLink("Consultar este documento e assinatura") { ClinicalDocumentDetailView(patient: patient, kind: createdDocument.kind, documentID: createdDocument.serverID) }
                }
                Button { Task { await submit() } } label: {
                    if isSaving { ProgressView() } else { Text("Emitir e assinar") }
                }
                .disabled(details.nilIfBlank == nil || (type == "documento" && title.nilIfBlank == nil) || isSaving || !outcome.canSubmit || !reviewed || details.count > 8_000 || title.count > 120)
            } footer: {
                Text("O documento usa o mesmo fluxo de assinatura e entrega da versão web.")
            }
        }
        .navigationTitle("Novo documento")
        .inlineTitle()
        .interactiveDismissDisabled(isSaving)
    }

    private func submit() async {
        guard let user = app.user, user.canIssueDocument else { return }
        let professionalID = user.id
        guard outcome.canSubmit, !isSaving else { return }
        let context = app.contextID
        let apiContext = await app.api.requestContextID()
        guard context == app.contextID, outcome.canSubmit, !isSaving else { return }
        outcome = .sending
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let body = CreateMedicalDocument(
                pacienteId: patient.id,
                profissionalId: professionalID,
                tipo: type,
                titulo: title.nilIfBlank,
                diasAfastamento: type == "atestado" ? days : nil,
                cid: type == "atestado" && cidAuthorized ? cid.nilIfBlank : nil,
                descricao: details.nilIfBlank
            )
            let result: MedicalDocument = try await app.api.post(["atestados"], body: body, expectedContext: apiContext)
            guard context == app.contextID else { return }
            let document = ClinicalDocumentSnapshot(result)
            try document.validate(patientID: patient.id, authorID: professionalID)
            createdDocument = document
            outcome = .succeeded
        } catch {
            guard context == app.contextID else { return }
            outcome = WriteOutcome.afterFailure(error)
            self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

struct ExamRequestForm: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var refreshedPatient: Patient?
    private var currentPatient: Patient { refreshedPatient ?? patient }
    @State private var type = "laboratorial"
    @State private var exam = ""
    @State private var tuss = ""
    @State private var items: [ExamItem] = []
    @State private var indication = ""
    @State private var reviewed = false
    @State private var confirmingEmission = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var createdDocument: ClinicalDocumentSnapshot?
    @State private var outcome = WriteOutcome.ready
    @State private var templateSheet: ClinicalTemplateSheet?
    var body: some View {
        Form {
            Section("Paciente") { LARIPatientIdentity(patient: currentPatient) }
            if app.user?.canPrescribe == true {
                Section { Button("Escolher modelo de exames") { templateSheet = .choose }.disabled(!outcome.canSubmit) }
            }
            Section("Solicitação") {
                Picker("Tipo", selection: $type) {
                    Text("Laboratorial").tag("laboratorial"); Text("Imagem").tag("imagem"); Text("Outro").tag("outro")
                }
                TextField("Indicação clínica", text: $indication, axis: .vertical).lineLimit(3...8)
            }.disabled(!outcome.canSubmit)
            Section("Exames do pedido") {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.descricao).font(.headline)
                        if let code = item.tuss { Text("TUSS: \(code)").font(.caption).foregroundStyle(.secondary) }
                        Button("Remover exame", role: .destructive) { items.remove(at: index) }.disabled(!outcome.canSubmit)
                    }
                }
                TextField("Nome do exame", text: $exam)
                TextField("Código TUSS (opcional)", text: $tuss)
                Button("Adicionar exame ao pedido") {
                    guard let name = exam.trimmedOrNil else { return }
                    items.append(ExamItem(tuss: tuss.trimmedOrNil, descricao: name)); exam = ""; tuss = ""
                }.disabled(exam.trimmedOrNil == nil || !outcome.canSubmit)
            }.disabled(!outcome.canSubmit)
            if !items.isEmpty && app.user?.canPrescribe == true {
                Section { Button("Salvar exames como modelo") { templateSheet = .save }.disabled(!outcome.canSubmit || items.count > 50 || exam.trimmedOrNil != nil || tuss.trimmedOrNil != nil) }
            }
            Section {
                WriteStatus(outcome: outcome, error: error)
                if let createdDocument {
                    Label("Solicitação criada", systemImage: "checkmark.circle").foregroundStyle(.green)
                    NavigationLink("Abrir documento criado") { ClinicalDocumentDetailView(patient: currentPatient, kind: createdDocument.kind, documentID: createdDocument.serverID) }
                }
                Toggle("Conferi paciente, exames e indicação e autorizo a emissão e a tentativa de assinatura", isOn: $reviewed).disabled(!outcome.canSubmit || isSaving)
                Button { confirmingEmission = true } label: { if isSaving { ProgressView() } else { Text("Revisar emissão e assinatura") } }
                    .disabled(!reviewed || items.isEmpty || exam.trimmedOrNil != nil || tuss.trimmedOrNil != nil || isSaving || !outcome.canSubmit)
            } footer: { Text("Ao emitir, o serviço registra o pedido e já tenta assiná-lo com seu certificado. Confira o conteúdo completo antes de confirmar. O envio ao paciente é uma etapa separada.") }
        }.disabled(isSaving).navigationTitle("Solicitar exames").inlineTitle().interactiveDismissDisabled(isSaving)
        .navigationBarBackButtonHidden(isSaving)
        .onChange(of: type) { _, _ in reviewed = false }
        .onChange(of: indication) { _, _ in reviewed = false }
        .onChange(of: items.map(\.id)) { _, _ in reviewed = false }
        .confirmationDialog("Emitir esta solicitação?", isPresented: $confirmingEmission, titleVisibility: .visible) {
            Button("Emitir e solicitar assinatura") { Task { await submit() } }
            Button("Voltar à revisão", role: .cancel) {}
        } message: { Text("O serviço tentará assinar a requisição com o certificado da sua conta. Esta etapa não envia o documento ao paciente.") }
        .sheet(item: $templateSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .choose:
                    ClinicalTemplatesView(applyingType: .exams) { model in
                        guard outcome.canSubmit else { return }
                        items.append(contentsOf: model.exames.map { ExamItem(tuss: $0.tuss, descricao: $0.descricao) })
                        indication = [indication.trimmedOrNil, model.examIndication.trimmedOrNil].compactMap { $0 }.joined(separator: "\n")
                    }
                case .save: SaveClinicalTemplateView(type: .exams, exams: items.map { TemplateExam(descricao: $0.descricao, tuss: $0.tuss) }, guidance: indication.trimmedOrNil)
                }
            }
        }
    }
    private func submit() async {
        guard let doctor = app.user, doctor.canRequestExam, reviewed, outcome.canSubmit, !isSaving, !items.isEmpty else { return }
        let patient = currentPatient
        let context = app.contextID
        let apiContext = await app.api.requestContextID()
        guard context == app.contextID, outcome.canSubmit, !isSaving else { return }
        isSaving = true; error = nil; var submitted = false
        defer { isSaving = false }
        do {
            let fresh: Patient = try await app.api.get(["pacientes", patient.id])
            guard app.contextID == context, reviewed, app.user?.canRequestExam == true else { throw APIError.contextChanged }
            guard fresh.id == patient.id else { throw APIError.invalidResponse }
            guard PrescriptionDeliveryReview(fresh) == PrescriptionDeliveryReview(patient) else {
                refreshedPatient = fresh; reviewed = false; throw DocumentReviewError.changed
            }
            let body = CreateExamRequest(pacienteId: patient.id, pacienteNome: patient.nome, tipo: type, itens: items, indicacaoClinica: indication.trimmedOrNil, medicoNome: doctor.nome, medicoCrm: nil)
            submitted = true; outcome = .sending
            let result: ExamRequest = try await app.api.post(["exames"], body: body, expectedContext: apiContext)
            guard app.contextID == context else { return }
            let document = ClinicalDocumentSnapshot(result)
            try document.validate(patientID: patient.id, authorID: doctor.id)
            createdDocument = document; outcome = .succeeded
        } catch {
            guard app.contextID == context else { return }
            if submitted { outcome = WriteOutcome.afterFailure(error) }
            reviewed = false
            self.error = message(for: error); await app.checkSession(after: error)
        }
    }
}

private enum ClinicalTemplateSheet: String, Identifiable {
    case choose, save
    var id: String { rawValue }
}
private struct PrescriptionEditSelection: Identifiable {
    let index: Int
    let item: PrescriptionItem
    var id: Int { index }
}
private struct PrescriptionItemEditor: View {
    let onSave: (PrescriptionItem) -> Void
    let concentration: String?
    let pharmaceuticalForm: String?
    let regulatoryCategory: String?
    @Environment(\.dismiss) private var dismiss
    @State private var medicine: String
    @State private var dosage: String
    @State private var quantity: String
    @State private var dose: String
    @State private var frequency: String
    @State private var duration: String
    @State private var instructions: String
    @State private var continuous: Bool
    init(item: PrescriptionItem, onSave: @escaping (PrescriptionItem) -> Void) {
        self.onSave = onSave
        concentration = item.concentracao; pharmaceuticalForm = item.formaFarmaceutica; regulatoryCategory = item.categoriaRegulatoria
        _medicine = State(initialValue: item.medicamento); _dosage = State(initialValue: item.posologia)
        _quantity = State(initialValue: item.quantidade ?? ""); _dose = State(initialValue: item.dose ?? "")
        _frequency = State(initialValue: item.frequencia ?? ""); _duration = State(initialValue: item.duracao ?? "")
        _instructions = State(initialValue: item.instrucoes ?? ""); _continuous = State(initialValue: item.usoContinuo ?? false)
    }
    var body: some View {
        Form {
            Section("Prescrição") {
                TextField("Medicamento", text: $medicine, axis: .vertical)
                    .disabled(concentration != nil || pharmaceuticalForm != nil || regulatoryCategory != nil)
                if concentration != nil || pharmaceuticalForm != nil || regulatoryCategory != nil {
                    Text("Este item preserva a apresentação e a categoria do catálogo. Para trocar o produto, remova o item e selecione outro medicamento.").font(.footnote).foregroundStyle(.secondary)
                }
                TextField("Posologia", text: $dosage, axis: .vertical)
                TextField("Quantidade", text: $quantity)
                Toggle("Uso contínuo", isOn: $continuous)
            }
            Section("Detalhes opcionais") {
                TextField("Dose", text: $dose); TextField("Frequência", text: $frequency)
                TextField("Duração", text: $duration); TextField("Instruções", text: $instructions, axis: .vertical)
            }
            Section { Button("Aplicar alterações ao item") {
                guard let medicine = medicine.trimmedOrNil, let dosage = dosage.trimmedOrNil else { return }
                onSave(PrescriptionItem(medicamento: medicine, posologia: dosage, quantidade: quantity.trimmedOrNil, usoContinuo: continuous, dose: dose.trimmedOrNil, frequencia: frequency.trimmedOrNil, duracao: duration.trimmedOrNil, instrucoes: instructions.trimmedOrNil, concentracao: concentration, formaFarmaceutica: pharmaceuticalForm, categoriaRegulatoria: regulatoryCategory))
                dismiss()
            }.disabled(medicine.trimmedOrNil == nil || dosage.trimmedOrNil == nil) }
        }.navigationTitle("Revisar medicamento").inlineTitle().toolbar { Button("Cancelar") { dismiss() } }
    }
}

struct TeleconsultationView: View {
    let appointment: Appointment
    let patientName: String
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var room: TelemedicineRoom?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Paciente", value: patientName)
                LabeledContent("Criptografia", value: room?.criptografia ?? "A confirmar pelo serviço")
                LabeledContent("Sala", value: room?.status ?? "Ainda não preparada")
            }
            Section {
                if let error { Text(error).foregroundStyle(.red) }
                Button {
                    Task { await prepare() }
                } label: {
                    if isLoading { ProgressView() } else { Label("Preparar sala segura", systemImage: "video.badge.plus") }
                }
                .disabled(isLoading)
                if room != nil, let url = URL(string: "https://app.atendebem.io/teleconsulta?agendamentoId=\(appointment.id)") {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Abrir videochamada", systemImage: "arrow.up.right.square")
                    }
                }
            } footer: {
                Text("A sala é criada pela mesma API da versão web. A videochamada abre no ambiente seguro do AtendeBem.")
            }
        }
        .navigationTitle("Teleconsulta")
        .inlineTitle()
    }

    private func prepare() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            room = try await app.api.post(["salas"], body: ["agendamentoId": appointment.id])
        } catch {
            self.error = message(for: error)
            await app.checkSession(after: error)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
