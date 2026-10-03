import AtendeBemCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PatientDocumentsView: View {
    let patient: Patient
    @Environment(AppState.self) private var app
    @State private var prescriptions = RemoteResource<[ClinicalDocumentSnapshot]>()
    @State private var certificates = RemoteResource<[ClinicalDocumentSnapshot]>()
    @State private var exams = RemoteResource<[ClinicalDocumentSnapshot]>()
    @State private var selectedKind: ClinicalDocumentKind?
    @State private var onlyMineToSign = false
    @State private var search = ""

    private var documents: [ClinicalDocumentSnapshot] {
        (prescriptions.value ?? []) + (certificates.value ?? []) + (exams.value ?? [])
    }
    private var visible: [ClinicalDocumentSnapshot] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return documents.filter { document in
            (selectedKind == nil || document.kind == selectedKind)
            && (!onlyMineToSign || app.user.map { document.canSign(user: $0) } == true)
            && (query.isEmpty || (document.title + " " + document.detail + " " + document.statusLabel).localizedStandardContains(query))
        }
    }
    private var incomplete: Bool { prescriptions.error != nil || certificates.error != nil || exams.error != nil }
    private var loading: Bool { prescriptions.isLoading || certificates.isLoading || exams.isLoading }
    var body: some View {
        List {
            Section {
                Text(patient.nome).font(.headline)
                Text(app.clinicName).font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Picker("Tipo de documento", selection: $selectedKind) {
                    Text("Todos").tag(Optional<ClinicalDocumentKind>.none)
                    ForEach(ClinicalDocumentKind.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Toggle("Meus rascunhos", isOn: $onlyMineToSign)
            } footer: { Text("Abra um documento para revisar seu conteúdo, consultar o PDF e conferir a assinatura.") }
            if app.user?.canPrescribe == true {
                Section { NavigationLink { ProfessionalCertificateView() } label: { Label("Meu certificado digital", systemImage: "signature") } }
            }
            if app.user.map(ExternalExamPolicy.canReceive) == true {
                Section {
                    NavigationLink { PatientExamsView(patient: patient) } label: {
                        Label("Exames e resultados recebidos", systemImage: "cross.vial")
                    }
                } footer: { Text("Receba exames externos, anexe laudos e abra resultados deste paciente.") }
            }
            if app.user?.canPrescribe == true { sourceStatus("Receitas", resource: prescriptions) }
            if app.user?.canIssueDocument == true { sourceStatus("Atestados e declarações", resource: certificates) }
            sourceStatus("Exames", resource: exams)
            Section {
                Text("\(visible.count) de \(documents.count) documentos carregados").font(.subheadline).foregroundStyle(.secondary)
                if incomplete { Label("A lista está parcial. Uma fonte não respondeu.", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                if visible.isEmpty && !loading {
                    ContentUnavailableView("Nenhum documento neste recorte", systemImage: "doc.text.magnifyingglass", description: Text(incomplete ? "Tente atualizar as fontes indisponíveis." : "Altere os filtros ou crie um documento durante o atendimento."))
                }
                if selectedKind != nil || onlyMineToSign || !search.isEmpty {
                    Button("Limpar filtros") { selectedKind = nil; onlyMineToSign = false; search = "" }
                }
                ForEach(visible) { document in
                    NavigationLink {
                        if document.kind == .exam {
                            ExternalExamDetailView(patient: patient, examID: document.serverID)
                        } else {
                            ClinicalDocumentDetailView(patient: patient, kind: document.kind, documentID: document.serverID)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(document.title).font(.headline)
                            Text(document.statusLabel).font(.subheadline)
                            Text(document.signatureLabel).font(.caption).foregroundStyle(.secondary)
                            if let date = document.date { Text(date).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.navigationTitle("Documentos do paciente").inlineTitle()
            .searchable(text: $search, prompt: "Buscar nos documentos")
            .task { await load() }.refreshable { await load() }
    }
    private func sourceStatus(_ title: String, resource: RemoteResource<[ClinicalDocumentSnapshot]>) -> some View {
        Section {
            ConnectionState(updatedAt: resource.updatedAt, error: resource.error, isLoading: resource.isLoading)
            if resource.error != nil { Button("Atualizar \(title.lowercased())") { Task { await load() } }.disabled(loading) }
        } header: { Text(title) }
    }
    private func load() async {
        guard let user = app.user else { return }
        async let a: Void = loadPrescriptions(user)
        async let b: Void = loadCertificates(user)
        async let c: Void = exams.load(app: app) { try await ClinicalDocuments.list(api: app.api, kind: .exam, patientID: patient.id) }
        _ = await (a, b, c)
    }
    private func loadPrescriptions(_ user: User) async {
        guard user.canPrescribe else { return }
        await prescriptions.load(app: app) { try await ClinicalDocuments.list(api: app.api, kind: .prescription, patientID: patient.id) }
    }
    private func loadCertificates(_ user: User) async {
        guard user.canIssueDocument else { return }
        await certificates.load(app: app) { try await ClinicalDocuments.list(api: app.api, kind: .certificate, patientID: patient.id) }
    }
}

struct ClinicalDocumentDetailView: View {
    let patient: Patient
    let kind: ClinicalDocumentKind
    let documentID: String
    var existingReview: DocumentReview? = nil
    @Environment(AppState.self) private var app
    @State private var review: DocumentReview?
    @State private var confirmingSignature = false
    @State private var contentReviewed = false
    var body: some View {
        List {
            Section {
                Text(patient.nome).font(.headline)
                Text(app.clinicName).foregroundStyle(.secondary)
            }
            if let review {
                if let document = review.document {
                    Section {
                        LabeledContent("Situação", value: document.statusLabel)
                        if let date = document.date { LabeledContent("Data informada", value: date) }
                        Text(document.signatureLabel).font(.footnote)
                        if let signature = document.signature {
                            LabeledContent("Verificação", value: signature.codigoVerificacao).textSelection(.enabled)
                        }
                    } header: { Text(document.title) }
                    Section {
                        Text(review.reviewDetail.isEmpty ? "O serviço não forneceu o conteúdo em texto. Consulte o PDF." : review.reviewDetail).textSelection(.enabled)
                        if kind == .prescription && document.status == "rascunho" {
                            Text("O serviço disponibiliza o PDF da receita após a assinatura.").font(.footnote).foregroundStyle(.secondary)
                        } else if document.canOpenPDF {
                            NavigationLink { DocumentPDFView(path: [kind.rawValue, documentID, "pdf"], title: document.title) } label: { Label("Abrir PDF deste documento", systemImage: "doc.richtext") }
                        } else if kind == .exam {
                            Text("Este registro não disponibiliza PDF de requisição. Consulte os arquivos dos resultados recebidos.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text(review.hasCompletePrescriptionPayload ? "Conteúdo da receita preparada nesta sessão" : "Conteúdo retornado pelo serviço") } footer: { Text(kind == .prescription ? (review.hasCompletePrescriptionPayload ? "A revisão combina o conteúdo enviado nesta sessão com os itens conferidos no sistema. O PDF fica disponível após a assinatura. A conferência não bloqueia alterações simultâneas de forma atômica." : "O serviço pode omitir orientações gerais e justificativas de alergia de receitas criadas em outros fluxos. Sem os dados completos da criação, a assinatura fica indisponível nesta tela.") : "Quando disponível, confira também o PDF: ele pode incluir informações que o serviço não retorna neste resumo.") }
                    if kind == .exam, app.user.map(ExternalExamPolicy.canReceive) == true {
                        Section {
                            NavigationLink { ExternalExamDetailView(patient: patient, examID: documentID) } label: {
                                Label("Consultar e anexar resultados", systemImage: "paperclip")
                            }
                        }
                    }
                    if let reason = review.signingUnavailableReason {
                        Section {
                            Label("Assinatura indisponível nesta tela", systemImage: "lock")
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if document.canSign(user: review.user) {
                        Section {
                            if kind == .prescription, let delivery = review.delivery {
                                Text(delivery.name).font(.headline)
                                LabeledContent("WhatsApp cadastrado", value: delivery.phone ?? "Não informado")
                                LabeledContent("E-mail cadastrado", value: delivery.email ?? "Não informado")
                                Text(delivery.hasDestination ? "Ao assinar, o serviço inicia o envio da receita pelos canais cadastrados acima. Se o contato estiver incorreto, atualize o cadastro antes de assinar." : "Nenhum contato de entrega está cadastrado. Você pode assinar para obter o PDF; a entrega eletrônica depende de atualizar o cadastro do paciente.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Toggle(kind == .prescription ? "Revisei o conteúdo, o paciente e os contatos de envio" : "Revisei o conteúdo e confirmei o paciente", isOn: $contentReviewed).disabled(review.busy)
                            Button(kind == .prescription && review.delivery?.hasDestination == true ? "Assinar e solicitar envio" : "Assinar este documento") { confirmingSignature = true }
                                .disabled(!contentReviewed || !review.canSign)
                        } footer: { Text("A assinatura será solicitada ao serviço com o certificado vinculado à sua conta.") }
                    }
                    if kind == .prescription, document.signature != nil {
                        Section {
                            Label("Assinatura confirmada pelo serviço", systemImage: "signature")
                            Text("A assinatura aciona o fluxo de envio do sistema. Esta tela não confirma a entrega ao paciente e não repete o envio automaticamente.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ConnectionState(updatedAt: review.updatedAt, error: review.error, isLoading: review.busy)
                    if review.outcome == .uncertain { Text("O resultado da assinatura ainda não está confirmado. Apenas a leitura será repetida ao atualizar.").foregroundStyle(.orange) }
                    Button("Atualizar este documento") { Task { contentReviewed = false; await review.load(); await recoverSessionIfNeeded() } }.disabled(review.busy)
                }
            } else { ProgressView("Abrindo documento…") }
        }.navigationTitle("Revisar documento").inlineTitle()
            .navigationBarBackButtonHidden(review?.busy == true)
            .interactiveDismissDisabled(review?.busy == true)
            .task {
                guard review == nil, let user = app.user else { return }
                let model = if let existingReview { existingReview } else { DocumentReview(api: app.api, context: await app.api.requestContextID(), kind: kind, documentID: documentID, patientID: patient.id, user: user) }
                review = model; await model.load(); await recoverSessionIfNeeded()
            }
            .confirmationDialog("Assinar o documento de \(patient.nome)?", isPresented: $confirmingSignature, titleVisibility: .visible) {
                Button(kind == .prescription && review?.delivery?.hasDestination == true ? "Confirmar assinatura e envio" : "Confirmar assinatura") { Task { await review?.sign(); contentReviewed = false; await recoverSessionIfNeeded() } }
                Button("Voltar à revisão", role: .cancel) {}
            } message: { Text(kind == .prescription ? "O conteúdo e os contatos serão consultados novamente. Ao assinar, o serviço inicia o envio pelos canais cadastrados. Se algo mudar, será necessária outra revisão." : "O conteúdo será consultado novamente antes da solicitação. Se tiver mudado, você deverá revisá-lo outra vez.") }
    }
    private func recoverSessionIfNeeded() async {
        if !(await app.api.hasSession()) { await app.checkSession(after: APIError.sessionExpired) }
    }
}

struct DocumentPDFView: View {
    let path: [String]
    let title: String
    @Environment(AppState.self) private var app
    @State private var resource = RemoteResource<Data>()
    @State private var sharingEnabled = false
    var body: some View {
        Group {
            if let data = resource.value { NativePDF(data: data).id(resource.updatedAt) }
            else if let error = resource.error {
                RetryState(title: "Não foi possível abrir o PDF", detail: error) { Task { await load() } }
            } else { ProgressView("Carregando documento…") }
        }.navigationTitle(title).inlineTitle().task { await load() }
            .toolbar {
                if let data = resource.value {
                    if sharingEnabled {
                        ShareLink(item: SharedClinicalPDF(data: data), preview: SharePreview("Documento clínico")) {
                            Label("Compartilhar PDF", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button { sharingEnabled = true } label: { Label("Opções do PDF", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if sharingEnabled {
                    Text("Este PDF contém informações de saúde. Confira o destinatário e compartilhe somente com autorização. A cópia enviada ficará fora do AtendeBem.")
                        .font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
    }
    private func load() async {
        await resource.load(app: app) {
            let data = try await app.api.pdf(path)
            guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw APIError.invalidResponse }
            return data
        }
    }
}

private struct SharedClinicalPDF: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName("documento-atendebem.pdf")
    }
}

// PDF bytes remain in memory; opening a document does not export it to Files or iCloud.
#if os(iOS)
struct NativePDF: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#elseif os(macOS)
struct NativePDF: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#endif
