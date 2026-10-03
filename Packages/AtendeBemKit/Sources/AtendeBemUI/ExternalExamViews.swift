import AtendeBemCore
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// This entrance is also available to reception, without granting access to the clinical chart.
struct PatientExamsView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<[ExamRequest]>()
    @State private var search = ""

    private var allowed: Bool { app.user.map(ExternalExamPolicy.canReceive) == true }
    private var visible: [ExamRequest] {
        (resource.value ?? []).filter { exam in
            search.isEmpty || (exam.itens.map(\.descricao).joined(separator: " ") + " " + (exam.laboratorio ?? "")).localizedStandardContains(search)
        }
    }
    var body: some View {
        Group {
            if allowed {
                List {
                    ExamPatientSection(patient: patient, clinic: app.clinicName)
                    Section {
                        NavigationLink { ExternalExamForm(patient: patient) } label: {
                            Label("Receber exame externo", systemImage: "tray.and.arrow.down")
                        }.accessibilityIdentifier("exams.receiveExternal")
                    } footer: { Text("Registre exames trazidos pelo paciente e anexe seus resultados. Uma solicitação da clínica continua identificada separadamente.") }
                    Section {
                        ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                        if resource.error != nil { Button("Atualizar exames") { Task { await load() } } }
                        if resource.value != nil && visible.isEmpty {
                            ContentUnavailableView("Nenhum exame neste recorte", systemImage: "cross.vial", description: Text("Busque pelo nome do exame ou pelo laboratório."))
                        }
                        ForEach(visible) { exam in
                            NavigationLink { ExternalExamDetailView(patient: patient, examID: exam.id) } label: { ExamSummary(exam: exam) }
                        }
                    } header: { Text("Exames e resultados") }
                }
            } else { RestrictedState() }
        }.navigationTitle("Exames e resultados").inlineTitle()
            .searchable(text: $search, prompt: "Exame ou laboratório")
            .task(id: patient.id) { await load() }
            .refreshable { await load() }
            .onChange(of: app.contextID) { _, _ in resource.clear(); search = "" }
    }
    private func load() async {
        guard allowed else { resource.clear(); return }
        let context = await app.api.requestContextID()
        await resource.load(app: app) {
            try await ExternalExamService(api: app.api).list(patientID: patient.id, expectedContext: context)
        }
    }
}

struct ExternalExamDetailView: View {
    let patient: Patient
    let examID: String
    @Environment(AppState.self) private var app
    @State private var workflow: ExternalExamWorkflow?
    @State private var resultSheet: ExamResultSheet?

    private var allowed: Bool { app.user.map(ExternalExamPolicy.canReceive) == true }
    var body: some View {
        Group {
            if allowed {
                List {
                    ExamPatientSection(patient: patient, clinic: app.clinicName)
                    if let workflow {
                        if let exam = workflow.exam {
                            ExamMetadataSections(exam: exam)
                            if exam.origem == "solicitada", app.user?.canReadClinicalData == true {
                                Section {
                                    NavigationLink { ClinicalDocumentDetailView(patient: patient, kind: .exam, documentID: examID) } label: {
                                        Label("Revisar solicitação da clínica", systemImage: "doc.text")
                                    }
                                }
                            }
                            Section {
                                Button {
                                    workflow.resetAttachment()
                                    resultSheet = ExamResultSheet(id: examID, workflow: workflow)
                                } label: { Label("Anexar resultado", systemImage: "paperclip") }
                                .disabled(!workflow.canStartAttachment)
                                .accessibilityIdentifier("exams.attachResult")
                                if workflow.attachmentOutcome == .uncertain {
                                    Text("Um envio está sem confirmação. Confira os resultados antes de decidir por outra anexação.").foregroundStyle(.orange)
                                    Button("Conferir envio anterior") { Task { await workflow.reconcileAttachment(); await recoverSession() } }
                                        .disabled(workflow.busy)
                                }
                            } footer: { Text("O resultado pertence a este exame. O registro do exame permanece disponível mesmo se a anexação não terminar.") }
                            if let results = exam.resultados {
                                Section {
                                    if results.isEmpty { Text("Nenhum resultado anexado foi retornado.").foregroundStyle(.secondary) }
                                    ForEach(results) { result in
                                        NavigationLink {
                                            ExamResultDetailView(patient: patient, examID: examID, resultID: result.id)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Label(result.arquivoNome ?? "Laudo em texto", systemImage: result.temArquivo ? "doc" : "text.alignleft")
                                                    .font(.headline)
                                                if result.alterado { Label("Fora da referência, conforme registro", systemImage: "exclamationmark.circle").font(.subheadline) }
                                                ClinicalTimestamp(label: "Anexado em", value: result.anexadoEm)
                                            }.padding(.vertical, 4)
                                        }
                                    }
                                } header: { Text("Resultados recebidos") }
                            } else {
                                Section { Text("O serviço não retornou a lista de resultados. Atualize para tentar consultá-la.").foregroundStyle(.secondary) }
                            }
                        }
                        Section {
                            ConnectionState(updatedAt: nil, error: workflow.error, isLoading: workflow.busy)
                            Button("Atualizar exame e resultados") { Task { await workflow.load(); await recoverSession() } }.disabled(workflow.busy)
                        }
                    } else { ProgressView("Abrindo exame…") }
                }
            } else { RestrictedState() }
        }.navigationTitle("Exame e resultados").inlineTitle()
            .task(id: examID) { await prepare() }
            .sheet(item: $resultSheet, onDismiss: { Task { await workflow?.load(); await recoverSession() } }) { selection in
                NavigationStack { ExamResultForm(patient: patient, workflow: selection.workflow) }
            }
            .onChange(of: app.contextID) { _, _ in workflow?.invalidate(); resultSheet = nil; workflow = nil }
    }
    private func prepare() async {
        guard workflow == nil, let user = app.user, ExternalExamPolicy.canReceive(user: user) else { return }
        let uiContext = app.contextID
        let context = await app.api.requestContextID()
        guard app.contextID == uiContext else { return }
        let model = ExternalExamWorkflow(api: app.api, context: context, patientID: patient.id, patientName: patient.nome, user: user, examID: examID)
        workflow = model
        await model.load(); await recoverSession()
    }
    private func recoverSession() async {
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }
}

private struct ExamResultSheet: Identifiable {
    let id: String
    let workflow: ExternalExamWorkflow
}

struct ExternalExamForm: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var workflow: ExternalExamWorkflow?
    @State private var type = "laboratorial"
    @State private var laboratory = ""
    @State private var indication = ""
    @State private var knownDate = false
    @State private var performedDate = Date()
    @State private var itemDescription = ""
    @State private var items: [ExamItem] = []
    @State private var confirmedPatient = false

    private var allowed: Bool { app.user.map(ExternalExamPolicy.canReceive) == true }
    private var canEdit: Bool { workflow?.canCreate == true }
    var body: some View {
        Group {
            if allowed {
                Form {
                    ExamPatientSection(patient: patient, clinic: app.clinicName)
                    if let exam = workflow?.exam {
                        Section {
                            Label("Exame registrado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            ExamSummary(exam: exam)
                            NavigationLink { ExternalExamDetailView(patient: patient, examID: exam.id) } label: {
                                Label("Anexar resultado e acompanhar", systemImage: "paperclip")
                            }.accessibilityIdentifier("exams.created.open")
                        } footer: { Text("O exame já existe. Continue neste registro para enviar o laudo ou arquivo; não é necessário cadastrá-lo novamente.") }
                    } else {
                        Section("Exame trazido pelo paciente") {
                            Picker("Tipo", selection: $type) {
                                Text("Laboratorial").tag("laboratorial")
                                Text("Imagem").tag("imagem")
                                Text("Outro").tag("outro")
                            }
                            TextField("Laboratório ou serviço (opcional)", text: $laboratory)
                            Toggle("Sei a data de realização", isOn: $knownDate)
                            if knownDate { DatePicker("Realizado em", selection: $performedDate, displayedComponents: .date).environment(\.timeZone, ClinicClock.timeZone) }
                            TextField("Contexto informado (opcional)", text: $indication, axis: .vertical)
                        }.disabled(!canEdit)
                        Section {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                HStack {
                                    Text(item.descricao)
                                    Spacer()
                                    Button(role: .destructive) { items.remove(at: index) } label: { Label("Remover \(item.descricao)", systemImage: "minus.circle") }.labelStyle(.iconOnly)
                                }
                            }
                            TextField("Nome do exame", text: $itemDescription, axis: .vertical)
                            Button("Adicionar exame à lista") {
                                guard let description = itemDescription.trimmedOrNil else { return }
                                items.append(ExamItem(tuss: nil, descricao: description)); itemDescription = ""
                            }.disabled(itemDescription.trimmedOrNil == nil)
                        } header: { Text("Exames contidos no documento") }
                        footer: { Text("Informe ao menos um exame. Se a data não estiver disponível, ela ficará como desconhecida.") }
                        .disabled(!canEdit)
                        Section {
                            Toggle("Conferi o paciente e os exames informados", isOn: $confirmedPatient).disabled(!canEdit)
                            Button("Registrar exame externo") { Task { await create() } }
                                .disabled(!canEdit || !confirmedPatient || items.isEmpty || laboratory.utf16.count > 160 || itemDescription.trimmedOrNil != nil)
                                .accessibilityIdentifier("exams.external.create")
                            if itemDescription.trimmedOrNil != nil { Text("Adicione o exame digitado à lista antes de registrar.").font(.footnote) }
                            if laboratory.utf16.count > 160 { Text("O nome do laboratório deve ter até 160 caracteres.").foregroundStyle(.red) }
                        } footer: { Text("Este registro identifica um exame de outro serviço. Ele não emite uma solicitação em nome da clínica.") }
                    }
                    if let workflow {
                        Section { ConnectionState(updatedAt: nil, error: workflow.error, isLoading: workflow.busy) }
                        if workflow.creationOutcome == .uncertain {
                            Section {
                                Text("Não foi possível confirmar o cadastro. Uma nova criação está bloqueada para evitar duplicação.").foregroundStyle(.orange)
                                Button("Conferir registros recebidos") { Task { await workflow.reconcileCreation(); await recoverSession() } }.disabled(workflow.busy)
                                if workflow.creationCandidates.isEmpty {
                                    Text("Nenhum registro correspondente foi confirmado. Confira os exames recebidos com a equipe antes de iniciar outro cadastro.").font(.footnote).foregroundStyle(.secondary)
                                }
                                ForEach(workflow.creationCandidates) { candidate in
                                    VStack(alignment: .leading, spacing: 8) {
                                        ExamSummary(exam: candidate)
                                        ClinicalTimestamp(label: "Registrado em", value: candidate.criadoEm)
                                        Button("Este é o exame que registrei") { Task { await workflow.selectCreatedExam(id: candidate.id); if workflow.exam != nil { clearDraft() }; await recoverSession() } }.disabled(workflow.busy)
                                    }
                                }
                            } header: { Text("Conferência do cadastro") }
                            footer: { Text("Compare os itens, a data e o laboratório antes de escolher. A listagem não prova que um registro corresponde ao envio que ficou sem resposta.") }
                        }
                    }
                }
            } else { RestrictedState() }
        }.navigationTitle("Receber exame externo").inlineTitle()
            .task { await prepare() }
            .onChange(of: type) { _, _ in confirmedPatient = false }
            .onChange(of: laboratory) { _, _ in confirmedPatient = false }
            .onChange(of: indication) { _, _ in confirmedPatient = false }
            .onChange(of: knownDate) { _, _ in confirmedPatient = false }
            .onChange(of: performedDate) { _, _ in confirmedPatient = false }
            .onChange(of: items.count) { _, _ in confirmedPatient = false }
            .onChange(of: app.contextID) { _, _ in workflow?.invalidate(); clearDraft(); workflow = nil }
    }
    private func prepare() async {
        guard workflow == nil, let user = app.user, ExternalExamPolicy.canReceive(user: user) else { return }
        let uiContext = app.contextID
        let context = await app.api.requestContextID()
        guard app.contextID == uiContext else { return }
        workflow = ExternalExamWorkflow(api: app.api, context: context, patientID: patient.id, patientName: patient.nome, user: user)
    }
    private func create() async {
        guard let workflow, workflow.canCreate, confirmedPatient, !items.isEmpty, laboratory.utf16.count <= 160, itemDescription.trimmedOrNil == nil else { return }
        let performedOn: String? = knownDate ? ClinicClock.day(performedDate) : nil
        await workflow.create(ExternalExamInput(patientID: patient.id, patientName: patient.nome, type: type, items: items, performedOn: performedOn, laboratory: laboratory.trimmedOrNil, indication: indication.trimmedOrNil))
        if workflow.exam != nil { clearDraft() }
        await recoverSession()
    }
    private func clearDraft() { laboratory = ""; indication = ""; itemDescription = ""; items = []; confirmedPatient = false; knownDate = false; performedDate = .now }
    private func recoverSession() async {
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }
}

private struct ExamResultForm: View {
    let patient: Patient
    let workflow: ExternalExamWorkflow
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var report = ""
    @State private var file: ExamResultFile?
    @State private var altered = false
    @State private var checked = false
    @State private var fileImporter = false
    @State private var fileError: String?
    @State private var readingFile = false
    private var editable: Bool { workflow.canAttach && !readingFile }

    var body: some View {
        Form {
            ExamPatientSection(patient: patient, clinic: app.clinicName)
            if let exam = workflow.exam { Section { ExamSummary(exam: exam) } }
            if workflow.attachmentOutcome == .succeeded {
                Section {
                    Label("Resultado confirmado no registro", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Concluir") { dismiss() }.accessibilityIdentifier("exams.result.done")
                }
            } else {
                Section {
                    TextField("Texto do laudo (opcional se houver arquivo)", text: $report, axis: .vertical).lineLimit(5...12)
                    Text("\(report.utf16.count) de 20.000 caracteres").font(.caption).foregroundStyle(report.utf16.count > 20_000 ? .red : .secondary)
                    Toggle("Laudo indica resultado fora da referência", isOn: $altered)
                } header: { Text("Laudo recebido") }
                footer: { Text("Transcreva fielmente o documento. A indicação fora da referência deve constar do laudo; o app não interpreta o resultado.") }
                .disabled(!editable)
                Section {
                    if let file {
                        LabeledContent("Arquivo", value: file.name)
                        LabeledContent("Tamanho", value: ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                        NavigationLink("Conferir arquivo selecionado") { ExamResultPreview(file: file) }
                        Button("Remover arquivo", role: .destructive) { self.file = nil; checked = false }.disabled(!editable)
                    }
                    Button(file == nil ? "Selecionar arquivo" : "Trocar arquivo") { fileImporter = true }.disabled(!editable)
                    if readingFile { ProgressView("Conferindo arquivo…") }
                    if let fileError { Text(fileError).foregroundStyle(.red) }
                } header: { Text("Arquivo do resultado") }
                footer: { Text("PDF, PNG, JPEG ou DICOM, até 18 MiB por arquivo neste app. Se o conteúdo exceder o limite de envio, escolha um arquivo menor. DICOM exige um visualizador especializado para avaliação.") }
                Section {
                    Toggle("Conferi o paciente, o exame e o resultado", isOn: $checked).disabled(!editable)
                    Button("Enviar resultado") { Task { await attach() } }
                        .disabled(!editable || !checked || (report.trimmedOrNil == nil && file == nil) || report.utf16.count > 20_000)
                        .accessibilityIdentifier("exams.result.upload")
                } footer: { Text("O resultado será incluído neste exame da clínica ativa. O arquivo não é salvo automaticamente em Fotos, Arquivos ou iCloud.") }
            }
            Section {
                ConnectionState(updatedAt: nil, error: workflow.error, isLoading: workflow.busy)
                if workflow.attachmentOutcome == .uncertain {
                    Text("O envio ficou sem confirmação. Não envie novamente: confira o registro para evitar anexos duplicados.").foregroundStyle(.orange)
                    Button("Conferir resultado recebido") { Task { await workflow.reconcileAttachment(); clearAfterSuccess(); await recoverSession() } }.disabled(workflow.busy)
                }
            }
        }.navigationTitle("Anexar resultado").inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(workflow.attachmentOutcome == .succeeded ? "Fechar" : "Voltar") { dismiss() }.disabled(workflow.busy || readingFile) } }
            .interactiveDismissDisabled(workflow.busy || readingFile)
            .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.pdf, .png, .jpeg, UTType(filenameExtension: "dcm") ?? .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await readFile(url) } }
                case .failure: fileError = "Não foi possível abrir o arquivo selecionado. Tente selecioná-lo novamente."
                }
            }
            .onChange(of: report) { _, _ in checked = false }
            .onChange(of: altered) { _, _ in checked = false }
            .onChange(of: app.contextID) { _, _ in clearInput(); dismiss() }
    }
    private func readFile(_ url: URL) async {
        guard editable else { return }
        let context = app.contextID
        readingFile = true; fileError = nil; checked = false
        defer { readingFile = false }
        do {
            let candidate = try await Task.detached(priority: .userInitiated) { try readExamFile(url) }.value
            guard app.contextID == context, workflow.canAttach else { return }
            file = candidate
        } catch {
            guard app.contextID == context else { return }
            fileError = error.localizedDescription
        }
    }
    private func attach() async {
        guard editable, checked, report.utf16.count <= 20_000, report.trimmedOrNil != nil || file != nil else { return }
        await workflow.attach(ExamResultInput(report: report.trimmedOrNil, file: file, altered: altered))
        clearAfterSuccess(); await recoverSession()
    }
    private func clearAfterSuccess() { if workflow.attachmentOutcome == .succeeded { clearInput() } }
    private func clearInput() { report = ""; file = nil; checked = false; altered = false; fileError = nil }
    private func recoverSession() async {
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }
}

private struct ExamResultDetailView: View {
    let patient: Patient
    let examID: String
    let resultID: String
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<ExamRequest>()
    private var result: ExamResult? { resource.value?.resultados?.first { $0.id == resultID } }
    var body: some View {
        List {
            ExamPatientSection(patient: patient, clinic: app.clinicName)
            if let result {
                Section {
                    ClinicalTimestamp(label: "Anexado em", value: result.anexadoEm)
                    if result.alterado { Label("Fora da referência, conforme registro", systemImage: "exclamationmark.circle") }
                    if let code = result.codigoVerificacao { LabeledContent("Código de verificação", value: code).textSelection(.enabled) }
                }
                Section("Laudo recebido") {
                    Text(result.laudo?.trimmedOrNil ?? "Nenhum laudo em texto foi retornado. Consulte o arquivo, quando disponível.").textSelection(.enabled)
                }
                if result.temArquivo {
                    Section {
                        NavigationLink {
                            ExamResultFileView(patient: patient, examID: examID, resultID: resultID)
                        } label: { Label("Abrir \(result.arquivoNome ?? "arquivo do resultado")", systemImage: "doc") }
                        if result.arquivoTipo == "application/dicom" {
                            Text("DICOM exige um visualizador especializado; o app permite compartilhar o arquivo com autorização.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if resource.value != nil {
                Section { Text("Este resultado não está disponível no exame retornado. Atualize para conferir o acesso.").foregroundStyle(.secondary) }
            }
            Section {
                ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
                Button("Atualizar resultado") { Task { await load() } }.disabled(resource.isLoading)
            }
        }.navigationTitle("Resultado do exame").inlineTitle().task { await load() }
            .onChange(of: app.contextID) { _, _ in resource.clear() }
    }
    private func load() async {
        guard app.user.map(ExternalExamPolicy.canReceive) == true else { resource.clear(); return }
        let context = await app.api.requestContextID()
        await resource.load(reset: true, app: app) {
            try await ExternalExamService(api: app.api).detail(examID: examID, patientID: patient.id, expectedContext: context)
        }
    }
}

private struct ExamResultFileView: View {
    let patient: Patient
    let examID: String
    let resultID: String
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<ExamResultFile>()
    @State private var sharingEnabled = false
    var body: some View {
        Group {
            if let file = resource.value { ExamResultPreview(file: file) }
            else if let error = resource.error {
                RetryState(title: "Não foi possível abrir o resultado", detail: error) { Task { await load() } }
            } else { ProgressView("Abrindo arquivo autorizado…") }
        }.navigationTitle("Arquivo do resultado").inlineTitle()
            .toolbar {
                if let file = resource.value {
                    if sharingEnabled {
                        ShareLink(item: SharedExamResult(data: file.data, name: file.name), preview: SharePreview("Resultado de exame")) {
                            Label("Compartilhar arquivo", systemImage: "square.and.arrow.up")
                        }
                    } else { Button("Opções de compartilhamento", systemImage: "square.and.arrow.up") { sharingEnabled = true } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if sharingEnabled {
                    Text("Este arquivo contém informações de saúde. Confira o destinatário e compartilhe somente com autorização. A cópia enviada ficará fora do AtendeBem.")
                        .font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .task { await load() }
            .onChange(of: app.contextID) { _, _ in resource.clear(); sharingEnabled = false }
            .onDisappear { resource.clear(); sharingEnabled = false }
    }
    private func load() async {
        guard app.user.map(ExternalExamPolicy.canReceive) == true else { resource.clear(); return }
        let context = await app.api.requestContextID()
        await resource.load(reset: true, app: app) {
            try await ExternalExamService(api: app.api).resultFile(examID: examID, resultID: resultID, patientID: patient.id, expectedContext: context)
        }
    }
}

private struct ExamResultPreview: View {
    let file: ExamResultFile
    var body: some View {
        Group {
            if file.contentType == "application/pdf" {
                if let document = PDFDocument(data: file.data), document.pageCount > 0 { NativePDF(data: file.data) }
                else { ContentUnavailableView("PDF sem visualização disponível", systemImage: "doc.questionmark", description: Text("Confira o arquivo original. O envio não garante que seu conteúdo possa ser renderizado.")) }
            } else if file.contentType == "image/png" || file.contentType == "image/jpeg" {
                if let image = previewImage(file.data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                            .frame(width: min(CGFloat(image.width), 1_000))
                            .accessibilityHidden(false).accessibilityLabel("Imagem do resultado; consulte também o laudo em texto")
                    }
                } else { ContentUnavailableView("Imagem sem visualização disponível", systemImage: "photo.badge.exclamationmark") }
            } else {
                ContentUnavailableView("Arquivo DICOM", systemImage: "cube.transparent", description: Text("Este formato exige um visualizador especializado. A visualização diagnóstica não está disponível no AtendeBem para iOS."))
            }
        }.navigationTitle(file.name).inlineTitle()
    }
}

private struct ExamPatientSection: View {
    let patient: Patient
    let clinic: String
    var body: some View {
        Section {
            Text(patient.nome).font(.headline)
            if let birth = patient.nascimento { LabeledContent("Nascimento", value: readableCivilDate(birth)) }
            Text(clinic).font(.subheadline).foregroundStyle(.secondary)
        } header: { Text("Paciente") }
    }
}

private struct ExamSummary: View {
    let exam: ExamRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exam.itens.map(\.descricao).joined(separator: ", ")).font(.headline)
            Text(examOriginLabel(exam.origem)).font(.subheadline)
            if let performed = exam.realizadoEm { Text("Realizado em \(readableCivilDate(performed))").font(.caption) }
            if let laboratory = exam.laboratorio { Text(laboratory).font(.caption).foregroundStyle(.secondary) }
            Text(ClinicalDocumentSnapshot(exam).statusLabel).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

private struct ExamMetadataSections: View {
    let exam: ExamRequest
    var body: some View {
        Section {
            Text(examOriginLabel(exam.origem)).font(.headline)
            LabeledContent("Tipo", value: exam.tipo.capitalized)
            LabeledContent("Situação", value: ClinicalDocumentSnapshot(exam).statusLabel)
            if exam.origem == "externa" {
                LabeledContent("Realização", value: exam.realizadoEm.map(readableCivilDate) ?? "Data desconhecida")
                LabeledContent("Laboratório", value: exam.laboratorio ?? "Não informado")
                Text("Recebido de outro serviço. Este registro não identifica a clínica como solicitante.").font(.footnote).foregroundStyle(.secondary)
            } else if exam.origem != "solicitada" {
                Text("A origem não foi confirmada pelo serviço. Assinatura e PDF de requisição ficam indisponíveis.").font(.footnote).foregroundStyle(.secondary)
            }
            ClinicalTimestamp(label: "Registrado em", value: exam.criadoEm)
        } footer: { Text("Datas com horário são exibidas em UTC−03, o horário utilizado pela agenda do app.") }
        Section("Exames registrados") {
            ForEach(Array(exam.itens.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.descricao)
                    if let tuss = item.tuss { Text("TUSS: \(tuss)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let indication = exam.indicacaoClinica?.trimmedOrNil { Text(indication).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
}

private struct SharedExamResult: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { $0.data }.suggestedFileName { $0.name }
    }
}

private func examOriginLabel(_ origin: String?) -> String {
    switch origin {
    case "externa": "Exame externo recebido"
    case "solicitada": "Solicitado pela clínica"
    default: "Origem não informada"
    }
}

private func readableCivilDate(_ value: String) -> String {
    let day: String
    if value.count == 10 { day = value }
    else if let date = ClinicClock.parseInstant(value) { day = ClinicClock.day(date) }
    else { return value }
    let components = day.split(separator: "-")
    guard components.count == 3, components[0].count == 4, components[1].count == 2, components[2].count == 2 else { return value }
    return "\(components[2])/\(components[1])/\(components[0])"
}

/// Only an in-memory, bounded copy is held; security-scoped access ends before the preview is presented.
private func readExamFile(_ url: URL) throws -> ExamResultFile {
    // The service's JSON body cap is smaller than base64-encoded 20 MiB; leave room for the report.
    let uploadLimit = 18 * 1_024 * 1_024
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true, (values.fileSize ?? 0) <= uploadLimit else { throw ExamFileSelectionError.invalidSize }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while data.count <= uploadLimit {
        let chunk = try handle.read(upToCount: min(65_536, uploadLimit + 1 - data.count)) ?? Data()
        if chunk.isEmpty { break }
        data.append(chunk)
    }
    guard data.count <= uploadLimit else { throw ExamFileSelectionError.invalidSize }
    return try ExamResultFile(data: data, name: url.lastPathComponent)
}

private enum ExamFileSelectionError: LocalizedError {
    case invalidSize
    var errorDescription: String? { "Escolha um arquivo de até 18 MiB, nos formatos PDF, PNG, JPEG ou DICOM." }
}

private func previewImage(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 4_096
    ] as CFDictionary)
}
