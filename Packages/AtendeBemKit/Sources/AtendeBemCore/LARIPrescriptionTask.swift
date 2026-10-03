import Foundation
import Observation

/// A conservative local extraction. Unrecognized clinical instructions stay in `original` for review.
public struct LARIPrescriptionCommand: Sendable {
    public let original: String
    public let patientQuery: String
    public let medicineQuery: String
    public let continuous: Bool
    public let duration: String
    public let posology = ""
    public let quantity = ""
    public let prescriptionType = ""
    public static func matches(_ text: String) -> Bool {
        text.range(of: #"^\s*(?:por favor[, ]+)?(?:emitir|emita|emit[a-zá]*|gerar|gere|preparar|prepare|criar|crie|faça|fazer)\s+(?:uma\s+)?receita\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    public init(text: String) {
        original = text
        let hasContinuous = text.range(of: #"\buso cont[ií]nuo\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let negated = text.range(of: #"\b(?:n[aã]o|sem)\b[^,.!?;]*\buso cont[ií]nuo\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        continuous = hasContinuous && !negated
        duration = Self.capture(#"\b(?:por|para)\s+(\d{1,3}\s+dias?)\b"#, text) ?? ""
        let tail = Self.capture(#"\breceita\s+(?:de\s+)?(.+)$"#, text) ?? ""
        let split = tail.range(of: #"\bpara\s+(?:(?:o|a|um|uma)\s+)?(?!\d)"#, options: [.regularExpression, .caseInsensitive])
        if let split {
            medicineQuery = String(tail[..<split.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(tail[split.upperBound...])
            patientQuery = name.components(separatedBy: .newlines).first?.replacingOccurrences(of: #"\s+(?:(?:de\s+)?uso cont[ií]nuo|por\s+\d|para\s+\d|posologia\s*:|quantidade\s*:).*$"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else { medicineQuery = ""; patientQuery = "" }
    }
    private static func capture(_ pattern: String, _ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// Actual current patient contacts are reviewed because signature dispatches the backend's delivery event.
public struct PrescriptionDeliveryReview: Sendable, Equatable {
    public let patientID: String
    public let name: String
    public let birthDate: String?
    public let maskedCPF: String?
    public let phone: String?
    public let email: String?
    public var hasDestination: Bool { phone != nil || email != nil }
    public init(_ patient: Patient) {
        patientID = patient.id; name = patient.nome; birthDate = patient.nascimento; maskedCPF = patient.cpfMascarado
        phone = patient.telefone?.taskNonempty; email = patient.email?.taskNonempty
    }
}

public struct PrescriptionMedicineControl: Decodable, Sendable {
    public let controlado: Bool?
    public let lista: String?
    public let modelo: String?
    public let procedencia: String
    public var supported: Bool {
        (modelo == "simples" && controlado == false && lista == nil && procedencia == "fora_do_catalogo_344") ||
        (modelo == "controle_especial" && controlado == true && ["C1", "C4", "C5"].contains(lista ?? "") && procedencia == "catalogo_344")
    }
    public func supports(type: String) -> Bool {
        supported && (modelo == "simples" ? ["comum", "antimicrobiano"].contains(type) : type == "controle_especial")
    }
}

@Observable @MainActor public final class LARIPrescriptionTask {
    public let command: LARIPrescriptionCommand
    public let draftID = UUID().uuidString
    public var patientQuery: String
    public var medicineQuery: String
    public var medicine: String { didSet { reviewed = false } }
    public var posology = "" { didSet { reviewed = false } }
    public var quantity = "" { didSet { reviewed = false } }
    public var prescriptionType = "" { didSet { reviewed = false } }
    public var continuous: Bool { didSet { reviewed = false } }
    public var duration: String { didSet { reviewed = false } }
    public var guidance = "" { didSet { reviewed = false } }
    public var allergyJustification = "" { didSet { reviewed = false } }
    public var reviewed = false
    public private(set) var patients: [Patient] = []
    public private(set) var medicines: [MedicineMatch] = []
    public private(set) var patient: Patient?
    public private(set) var selectedMedicine: MedicineMatch?
    public private(set) var medicineControl: PrescriptionMedicineControl?
    public private(set) var allergies: [Allergy]?
    public private(set) var document: ClinicalDocumentSnapshot?
    public private(set) var signatureReview: DocumentReview?
    public private(set) var outcome = WriteOutcome.ready
    public private(set) var error: String?
    public private(set) var busy = false
    public private(set) var hasMorePatients = false
    private let api: APIClient
    private let context: UUID
    private let user: User
    private let isContextCurrent: @MainActor () -> Bool
    private var active = true
    private var requestedPatientID: String?
    private var selectedMedicineText: String?
    private var submittedDraft: CreatePrescription?
    public init(command: String, api: APIClient, context: UUID, user: User, isContextCurrent: @escaping @MainActor () -> Bool = { true }) {
        let parsed = LARIPrescriptionCommand(text: command)
        self.command = parsed; self.api = api; self.context = context; self.user = user
        self.isContextCurrent = isContextCurrent
        patientQuery = parsed.patientQuery
        medicineQuery = parsed.medicineQuery.replacingOccurrences(of: #"\s+\d[\d.,]*\s*(?:mg|mcg|g|ml|ui|%)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        medicine = parsed.medicineQuery
        continuous = parsed.continuous; duration = parsed.duration
    }
    public var canEdit: Bool { active && isContextCurrent() && user.canPrescribe && !busy && outcome.canSubmit }
    public var isWorking: Bool { busy || signatureReview?.busy == true }
    public var catalogPresentationIsFixed: Bool { selectedMedicine?.concentracao?.taskNonempty != nil || selectedMedicine?.formaFarmaceutica?.taskNonempty != nil }
    public var controlMatchesCatalog: Bool {
        guard let medicineControl else { return false }
        let category = selectedMedicine?.categoriaRegulatoria?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let controlledLists = ["A1", "A2", "A3", "B1", "B2", "C1", "C2", "C3", "C4", "C5"]
        let normalizedCategory = category.replacingOccurrences(of: #"^LISTA\s+"#, with: "", options: .regularExpression)
        if controlledLists.contains(normalizedCategory) {
            return medicineControl.controlado == true && medicineControl.lista?.uppercased() == normalizedCategory
        }
        // Do not override a source that mentions a controlled list or notification in an unrecognized form.
        let caution = ["LISTA", "CONTROL", "NOTIFICA", "RETINO", "ISOTRETINO", "ACITRETINA", "TRETINOINA", "TALIDOMIDA", "PSICOTR", "ENTORPEC"]
        if caution.contains(where: { category.contains($0) }) { return false }
        return true
    }
    public var medicineMatchesSelection: Bool {
        guard let selectedMedicine else { return false }
        let product = selectedMedicine.nomeProduto.taskComparison
        let entered = medicine.taskComparison
        if catalogPresentationIsFixed { return entered == selectedMedicineText?.taskComparison }
        return entered == product || entered.hasPrefix(product + " ") || entered.hasPrefix(product + " — ")
    }
    public var canCreate: Bool {
        canEdit && patient != nil && medicineMatchesSelection && allergies != nil && reviewed &&
        medicineControl?.supports(type: prescriptionType) == true &&
        controlMatchesCatalog &&
        medicine.taskNonempty != nil && posology.taskNonempty != nil && quantity.taskNonempty != nil &&
        ["comum", "controle_especial", "antimicrobiano"].contains(prescriptionType) &&
        medicine.count <= 500 && posology.count <= 2_000 && quantity.count <= 200 && duration.count <= 200 && guidance.count <= 8_000
    }
    private func checkContext() async throws {
        let current = await api.requestContextID()
        guard active, isContextCurrent(), user.canPrescribe, context == current else { throw APIError.contextChanged }
    }
    public func invalidate() { active = false; patient = nil; patients = []; allergies = nil; medicines = []; selectedMedicine = nil; medicineControl = nil; document = nil; signatureReview?.invalidate(); signatureReview = nil; submittedDraft = nil; requestedPatientID = nil; reviewed = false }
    private func fail(_ failure: Error) {
        error = failure.localizedDescription
        if let failure = failure as? APIError, [.http(401), .http(403), .http(404), .sessionExpired, .contextChanged, .invalidResponse].contains(failure) {
            patient = nil; patients = []; allergies = nil; document = nil; signatureReview?.invalidate(); signatureReview = nil; reviewed = false
        }
    }
    public func searchPatients() async {
        guard canEdit, patientQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
        busy = true; error = nil; patients = []; hasMorePatients = false
        defer { busy = false }
        do {
            try await checkContext()
            let page: PatientPage = try await api.get(["pacientes"], query: [.init(name: "busca", value: patientQuery), .init(name: "page", value: "1"), .init(name: "perPage", value: "25")])
            try await checkContext()
            guard page.total >= page.itens.count, Set(page.itens.map(\.id)).count == page.itens.count,
                  page.itens.allSatisfy({ !$0.id.isEmpty && !$0.nome.isEmpty }) else { throw APIError.invalidResponse }
            patients = page.itens; hasMorePatients = page.truncado == true || page.total > page.itens.count
        } catch { fail(error) }
    }
    public func selectPatient(_ candidate: Patient) async {
        guard canEdit else { return }; busy = true; error = nil; patient = nil; allergies = nil; reviewed = false
        defer { busy = false }
        do {
            try await checkContext()
            let current: Patient = try await api.get(["pacientes", candidate.id])
            try await checkContext()
            guard current.id == candidate.id, !current.nome.isEmpty else { throw APIError.invalidResponse }
            let records: [Allergy] = try await api.get(["pacientes", candidate.id, "alergias"])
            try await checkContext(); patient = current; allergies = records; patients = []
        } catch { fail(error) }
    }
    public func searchMedicines() async {
        guard canEdit, medicineQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
        busy = true; error = nil; medicines = []
        defer { busy = false }
        do {
            try await checkContext()
            let page: MedicineSearch = try await api.get(["medicamentos"], query: [.init(name: "busca", value: medicineQuery), .init(name: "campo", value: "nome"), .init(name: "page", value: "1"), .init(name: "perPage", value: "25")])
            try await checkContext()
            guard page.total >= page.itens.count, Set(page.itens.map(\.id)).count == page.itens.count else { throw APIError.invalidResponse }
            medicines = page.itens
        } catch { fail(error) }
    }
    public func selectMedicine(_ candidate: MedicineMatch) {
        guard canEdit, !candidate.id.isEmpty, !candidate.nomeProduto.isEmpty else { return }
        guard selectedMedicine?.id != candidate.id else { return }
        selectedMedicine = candidate; medicineControl = nil; medicines = []; reviewed = false
        // A deliberate catalog selection sets the product. Never keep a different product from the command.
        // Where no presentation is supplied, retain only the user's explicit strength for clinical review.
        let requestedStrength = command.medicineQuery.range(of: #"\b\d[\d.,]*\s*(?:mg|mcg|g|ml|ui|%)(?:\s*/\s*\d*[a-zA-Z]+)?\b"#, options: [.regularExpression, .caseInsensitive]).map { String(command.medicineQuery[$0]) }
        let requestedBase = command.medicineQuery.replacingOccurrences(of: #"\s+\d[\d.,]*\s*(?:mg|mcg|g|ml|ui|%)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive]).taskComparison
        let sameRequestedProduct = candidate.nomeProduto.taskComparison == requestedBase
        let strength = candidate.concentracao?.taskNonempty ?? (sameRequestedProduct ? requestedStrength : nil)
        var components = [candidate.nomeProduto]
        if let strength, !candidate.nomeProduto.taskComparison.contains(strength.taskComparison) { components.append(strength) }
        if let form = candidate.formaFarmaceutica?.taskNonempty, !candidate.nomeProduto.taskComparison.contains(form.taskComparison) { components.append(form) }
        medicine = components.joined(separator: " ")
        selectedMedicineText = medicine
    }
    public func checkMedicineControl() async {
        guard canEdit, let selected = selectedMedicine else { return }
        busy = true; error = nil; medicineControl = nil; reviewed = false
        defer { busy = false }
        do {
            try await checkContext()
            let key = selected.principioAtivo?.taskNonempty == nil ? "nome" : "principio"
            let value = selected.principioAtivo?.taskNonempty ?? selected.nomeProduto
            let result: PrescriptionMedicineControl = try await api.get(["medicamentos", "controle"], query: [.init(name: key, value: value)])
            try await checkContext()
            guard selectedMedicine?.id == selected.id else { throw APIError.contextChanged }
            medicineControl = result
        } catch { fail(error) }
    }
    public func createDraft() async {
        guard canCreate, let reviewedPatient = patient, let reviewedAllergies = allergies else { return }
        busy = true; error = nil; var submitted = false
        let item = PrescriptionItem(medicamento: medicine.trimmingCharacters(in: .whitespacesAndNewlines), posologia: posology.trimmingCharacters(in: .whitespacesAndNewlines), quantidade: quantity.taskNonempty, usoContinuo: continuous, duracao: duration.taskNonempty, concentracao: selectedMedicine?.concentracao, formaFarmaceutica: selectedMedicine?.formaFarmaceutica, categoriaRegulatoria: selectedMedicine?.categoriaRegulatoria)
        // The public read contract omits these fields, so the abbreviated flow does not write hidden instructions/overrides.
        let body = CreatePrescription(pacienteId: reviewedPatient.id, profissionalId: user.id, tipo: prescriptionType, itens: [item], orientacoes: nil, justificativaAlergia: nil, id: draftID, modelo: medicineControl?.modelo)
        defer { busy = false }
        do {
            try await checkContext()
            let freshPatient: Patient = try await api.get(["pacientes", reviewedPatient.id])
            try await checkContext()
            guard freshPatient.id == reviewedPatient.id else { throw APIError.invalidResponse }
            let freshAllergies: [Allergy] = try await api.get(["pacientes", reviewedPatient.id, "alergias"])
            try await checkContext()
            patient = freshPatient; allergies = freshAllergies
            guard reviewed, PrescriptionDeliveryReview(freshPatient) == PrescriptionDeliveryReview(reviewedPatient), Self.allergyFingerprint(freshAllergies) == Self.allergyFingerprint(reviewedAllergies) else {
                reviewed = false; throw DocumentReviewError.changed
            }
            requestedPatientID = freshPatient.id
            submittedDraft = body
            submitted = true; outcome = .sending
            let created: Prescription = try await api.post(["receitas"], body: body, expectedContext: context)
            try await checkContext()
            let snapshot = ClinicalDocumentSnapshot(created)
            try snapshot.validate(patientID: freshPatient.id, authorID: user.id)
            guard created.id == draftID, snapshot.canSign(user: user), try matchesSubmittedDraft(created) else { throw APIError.invalidResponse }
            try prepareSignatureReview(created); document = snapshot; outcome = .succeeded
        } catch {
            if submitted { outcome = (error as? APIError)?.statusCode == 409 ? .uncertain : WriteOutcome.afterFailure(error) }
            fail(error)
        }
    }
    public func reconcileDraft() async {
        guard active, !busy, outcome == .uncertain else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            try await checkContext()
            guard let patientID = requestedPatientID else { throw DocumentReviewError.unavailable }
            let patient: Patient = try await api.get(["pacientes", patientID])
            try await checkContext()
            guard patient.id == patientID else { throw APIError.invalidResponse }
            let documents: [Prescription] = try await api.get(["receitas"], query: [.init(name: "pacienteId", value: patient.id)])
            try await checkContext()
            guard Set(documents.map(\.id)).count == documents.count, documents.allSatisfy({ $0.pacienteId == patient.id }) else { throw APIError.invalidResponse }
            guard let raw = documents.first(where: { $0.id == draftID }) else {
                error = "O rascunho ainda não apareceu nesta leitura. O comando continua bloqueado para evitar duplicidade. Confira os documentos do paciente."; return
            }
            guard try matchesSubmittedDraft(raw) else { throw APIError.invalidResponse }
            let found = ClinicalDocumentSnapshot(raw)
            try found.validate(patientID: patient.id, authorID: user.id)
            try prepareSignatureReview(raw); self.patient = patient; document = found; outcome = .succeeded
        } catch { fail(error) }
    }
    private static func allergyFingerprint(_ items: [Allergy]) -> [String] {
        items.map { [$0.id ?? "", $0.substancia, $0.severidade, $0.tipo ?? "", $0.reacao ?? "", $0.anafilaxia.map(String.init) ?? ""].joined(separator: "\u{1f}") }.sorted()
    }
    private func prepareSignatureReview(_ document: Prescription) throws {
        guard let submittedDraft else { throw APIError.invalidResponse }
        let evidence = try PrescriptionDraftEvidence(request: submittedDraft, response: document)
        signatureReview = DocumentReview(api: api, context: context, kind: .prescription, documentID: document.id, patientID: document.pacienteId, user: user, isContextCurrent: isContextCurrent, prescriptionEvidence: evidence)
    }
    private func matchesSubmittedDraft(_ value: Prescription) throws -> Bool {
        guard let submittedDraft else { return false }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let actualItems = try encoder.encode(value.itens)
        let requestedItems = try encoder.encode(submittedDraft.itens)
        return value.id == draftID && value.pacienteId == submittedDraft.pacienteId && value.profissionalId == submittedDraft.profissionalId &&
            value.tipo == submittedDraft.tipo && actualItems == requestedItems
    }
}

private extension String {
    var taskNonempty: String? { let cleaned = trimmingCharacters(in: .whitespacesAndNewlines); return cleaned.isEmpty ? nil : cleaned }
    var taskComparison: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
