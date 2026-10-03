import Foundation
import Observation

public struct LARIExamCommand: Sendable {
    public let original: String
    public let patientQuery: String
    public let proposedItems: [String]
    public init(text: String) {
        original = text; patientQuery = LARICommandFields.patientQuery(from: text)
        let tail = LARICommandFields.capture(#"\bexames?\s+(?:de\s+|:\s*)(.+?)(?:\s+para\s+|$)"#, from: text) ?? ""
        // Only copy explicit descriptions. No generated tests, indication, classification or TUSS codes.
        proposedItems = tail.components(separatedBy: CharacterSet(charactersIn: ",;\n")).compactMap(\.lariNonempty)
    }
}

private struct LARIExamDelivery: Decodable, Sendable {
    let status: String
    let solicitacaoId: String
    let canais: [String]
}

private enum LARIExamDeliveryError: LocalizedError {
    case cancelled
    var errorDescription: String? { "A requisição tem cancelamento informado. O envio não será solicitado por esta tarefa." }
}

@Observable @MainActor public final class LARIExamRequestTask {
    public let command: LARIExamCommand
    public let lookup: LARIPatientLookup
    public var type = "" { didSet { reviewed = false } }
    public var indication = "" { didSet { reviewed = false } }
    public var itemDescription = ""
    public var itemTUSS = ""
    public var reviewed = false
    public var sendByWhatsApp = false { didSet { deliveryReviewed = false } }
    public var sendByEmail = false { didSet { deliveryReviewed = false } }
    public var deliveryReviewed = false
    public private(set) var items: [ExamItem]
    public private(set) var document: ExamRequest?
    public private(set) var signatureReview: DocumentReview?
    public private(set) var delivery: PrescriptionDeliveryReview?
    public private(set) var existingRequests: [ExamRequest] = []
    public private(set) var outcome = WriteOutcome.ready
    public private(set) var deliveryOutcome = WriteOutcome.ready
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var deliveryError: String?
    private let scope: LARIPatientTaskContext
    private var submittedInput: CreateExamRequest?
    public init(command: String, api: APIClient, context: UUID, user: User, isContextCurrent: @escaping @MainActor () -> Bool = { true }) {
        let parsed = LARIExamCommand(text: command)
        self.command = parsed; items = parsed.proposedItems.map { ExamItem(descricao: $0) }
        let scope = LARIPatientTaskContext(api: api, context: context, user: user, route: .examRequest, isContextCurrent: isContextCurrent)
        self.scope = scope; lookup = LARIPatientLookup(query: parsed.patientQuery, scope: scope)
    }
    public var isWorking: Bool { busy || lookup.busy || signatureReview?.busy == true }
    public var canEdit: Bool { scope.available && !isWorking && outcome.canSubmit }
    public var itemValidationMessage: String? {
        if items.count > 50 { return "O pedido contém \(items.count) exames. Revise e reduza para até 50 antes de emitir. Todos os itens foram preservados." }
        if items.contains(where: { $0.descricao.lariTrimmed.isEmpty || $0.descricao.count > 500 }) { return "Cada exame precisa de uma descrição de até 500 caracteres. Edite os itens antes de emitir; nenhum exame foi descartado." }
        return nil
    }
    public var canCreate: Bool {
        canEdit && reviewed && lookup.patient != nil && ["laboratorial", "imagem", "outro"].contains(type) &&
        !items.isEmpty && itemValidationMessage == nil && indication.count <= 8_000 && itemDescription.lariTrimmed.isEmpty && itemTUSS.lariTrimmed.isEmpty
    }
    public var selectedChannels: [String] { (sendByWhatsApp ? ["whatsapp"] : []) + (sendByEmail ? ["email"] : []) }
    private static func isCancelled(_ status: String?) -> Bool {
        guard let status else { return false }
        return ["cancelado", "cancelada", "cancelled", "canceled"].contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    private var hasKnownCancellation: Bool {
        Self.isCancelled(document?.status) || Self.isCancelled(signatureReview?.document?.status)
    }
    public var canSend: Bool {
        scope.available && !isWorking && !hasKnownCancellation && deliveryReviewed && deliveryOutcome.canSubmit && document?.origem == "solicitada" &&
        document?.assinatura?.padrao == "ICP-Brasil" && !selectedChannels.isEmpty &&
        (!sendByWhatsApp || delivery?.phone != nil) && (!sendByEmail || delivery?.email != nil) && delivery != nil
    }
    public func invalidate() {
        scope.invalidate(); lookup.invalidate(); document = nil; delivery = nil; items = []; existingRequests = []
        signatureReview?.invalidate(); signatureReview = nil; submittedInput = nil; reviewed = false; deliveryReviewed = false
        indication = ""; itemDescription = ""; itemTUSS = ""
    }
    private func fail(_ failure: Error) {
        error = failure.localizedDescription
        if lariInvalidatesContent(failure) {
            lookup.invalidate(); document = nil; delivery = nil; existingRequests = []; signatureReview?.invalidate(); signatureReview = nil; reviewed = false; deliveryReviewed = false
        }
    }
    public func searchPatients() async { guard canEdit else { return }; await lookup.search() }
    public func selectPatient(_ patient: Patient) async { guard canEdit else { return }; reviewed = false; await lookup.select(patient) }
    public func changePatient() { guard canEdit else { return }; reviewed = false; lookup.clearSelection() }
    public func addItem() {
        guard canEdit, let description = itemDescription.lariNonempty, description.count <= 500, itemTUSS.count <= 30, items.count < 50 else { return }
        let item = ExamItem(tuss: itemTUSS.lariNonempty, descricao: description)
        guard !items.contains(where: { $0.id == item.id }) else { error = "Este exame já está na lista. Confira o pedido antes de repetir um item."; return }
        items.append(item); itemDescription = ""; itemTUSS = ""; reviewed = false; error = nil
    }
    public func updateItemDescription(at index: Int, text: String) {
        guard canEdit, items.indices.contains(index) else { return }
        items[index] = ExamItem(tuss: items[index].tuss, descricao: text); reviewed = false
    }
    public func removeItem(at index: Int) { guard canEdit, items.indices.contains(index) else { return }; items.remove(at: index); reviewed = false }
    public func create() async {
        guard canCreate, let patient = lookup.patient else { return }
        let body = CreateExamRequest(pacienteId: patient.id, pacienteNome: patient.nome, tipo: type, itens: items, indicacaoClinica: indication.lariNonempty, medicoNome: scope.user.nome, medicoCrm: nil)
        busy = true; error = nil; var submitted = false
        defer { busy = false }
        do {
            let fresh = try await scope.readPatient(patient.id)
            guard PrescriptionDeliveryReview(fresh) == PrescriptionDeliveryReview(patient) else { lookup.update(fresh); reviewed = false; throw DocumentReviewError.changed }
            try await scope.check()
            guard reviewed else { throw DocumentReviewError.changed }
            submittedInput = body; submitted = true; outcome = .sending
            let result: ExamRequest = try await scope.api.post(["exames"], body: body, expectedContext: scope.context)
            try await scope.check()
            try validate(result, against: body)
            document = result; outcome = .succeeded
            signatureReview = DocumentReview(api: scope.api, context: scope.context, kind: .exam, documentID: result.id, patientID: patient.id, user: scope.user, isContextCurrent: { [weak scope] in scope?.available == true })
        } catch {
            if submitted { outcome = WriteOutcome.afterFailure(error) }
            fail(error)
        }
    }
    private func validate(_ value: ExamRequest, against input: CreateExamRequest) throws {
        try ClinicalDocumentSnapshot(value).validate(patientID: input.pacienteId, authorID: scope.user.id)
        guard value.origem == "solicitada", value.pacienteNome == input.pacienteNome, value.tipo == input.tipo,
              value.indicacaoClinica == input.indicacaoClinica, value.itens.count == input.itens.count,
              zip(value.itens, input.itens).allSatisfy({ $0.0.descricao == $0.1.descricao && $0.0.tuss == $0.1.tuss }) else { throw APIError.invalidResponse }
    }
    /// The server does not accept a client creation id. These are candidates for human inspection only.
    public func consultExistingRequests() async {
        guard scope.available, !isWorking, outcome == .uncertain, let input = submittedInput else { return }
        busy = true; error = nil; existingRequests = []
        defer { busy = false }
        do {
            try await scope.check()
            let values: [ExamRequest] = try await scope.api.get(["exames"], query: [.init(name: "pacienteId", value: input.pacienteId)])
            try await scope.check()
            guard values.allSatisfy({ $0.pacienteId == input.pacienteId }), Set(values.map(\.id)).count == values.count else { throw APIError.invalidResponse }
            existingRequests = Array(values.sorted { $0.criadoEm > $1.criadoEm }.prefix(25))
            if lookup.patient == nil { lookup.update(try await scope.readPatient(input.pacienteId)) }
            error = "Confira os pedidos no sistema. O serviço não fornece um identificador desta tentativa; a tarefa não reenviará nem assumirá que um pedido parecido é o mesmo."
        } catch { fail(error) }
    }
    public func prepareDelivery() async {
        guard scope.available, !isWorking, let saved = document, let input = submittedInput else { return }
        busy = true; deliveryError = nil; delivery = nil; deliveryReviewed = false
        defer { busy = false }
        do {
            try await scope.check()
            let current: ExamRequest = try await scope.api.get(["exames", saved.id])
            try await scope.check(); try validate(current, against: input)
            guard current.id == saved.id else { throw APIError.invalidResponse }
            let patient = try await scope.readPatient(current.pacienteId)
            document = current; lookup.update(patient); delivery = PrescriptionDeliveryReview(patient)
        } catch { deliveryError = error.localizedDescription; if lariInvalidatesContent(error) { fail(error) } }
    }
    public func send() async {
        guard canSend, let saved = document, let input = submittedInput, let reviewedDelivery = delivery else { return }
        let channels = selectedChannels
        busy = true; deliveryError = nil; var submitted = false
        defer { busy = false }
        do {
            try await scope.check()
            let current: ExamRequest = try await scope.api.get(["exames", saved.id])
            try await scope.check(); try validate(current, against: input)
            guard current.id == saved.id else { throw APIError.invalidResponse }
            if Self.isCancelled(current.status) || hasKnownCancellation {
                deliveryReviewed = false; document = current; throw LARIExamDeliveryError.cancelled
            }
            guard ClinicalDocumentSnapshot(current) == ClinicalDocumentSnapshot(saved) else { deliveryReviewed = false; document = current; throw DocumentReviewError.changed }
            let patient = try await scope.readPatient(current.pacienteId)
            let contacts = PrescriptionDeliveryReview(patient)
            guard contacts == reviewedDelivery else { deliveryReviewed = false; delivery = contacts; lookup.update(patient); throw DocumentReviewError.changed }
            guard !hasKnownCancellation else { deliveryReviewed = false; throw LARIExamDeliveryError.cancelled }
            guard current.assinatura?.padrao == "ICP-Brasil", deliveryReviewed else { throw DocumentReviewError.notAuthorized }
            submitted = true; deliveryOutcome = .sending
            let result: LARIExamDelivery = try await scope.api.post(["exames", current.id, "enviar"], body: ["canais": channels], expectedContext: scope.context)
            try await scope.check()
            guard result.status == "enfileirado", result.solicitacaoId == current.id, result.canais.sorted() == channels.sorted() else { throw APIError.invalidResponse }
            deliveryOutcome = .succeeded
        } catch {
            if submitted { deliveryOutcome = WriteOutcome.afterFailure(error) }
            deliveryError = error.localizedDescription
            if lariInvalidatesContent(error) { fail(error) }
        }
    }
}
