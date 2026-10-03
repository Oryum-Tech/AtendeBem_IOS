import Foundation

public extension ClinicalTemplate {
    /// Usage counters and timestamps can change when registering use; compare the reviewed content itself.
    func hasSameContent(as other: ClinicalTemplate) -> Bool {
        id == other.id && tipo == other.tipo && nome == other.nome && condicao == other.condicao &&
        cid10 == other.cid10 && orientacoes == other.orientacoes &&
        sameJSON(medicamentos, other.medicamentos) && sameJSON(exames, other.exames)
    }
}

/// Editable values are separate from the server model so an interrupted edit never mutates the library.
public struct ClinicalTemplateDraft: Sendable {
    public let type: ClinicalTemplateType
    public var name: String
    public var condition: String
    public var codes: String
    public var guidance: String
    public var medicines: [TemplateMedicineDraft]
    public var exams: [TemplateExamDraft]

    public init(_ model: ClinicalTemplate) {
        type = model.tipo; name = model.nome; condition = model.condicao ?? ""
        codes = model.cid10.joined(separator: ", "); guidance = model.orientacoes ?? ""
        medicines = model.medicamentos.map(TemplateMedicineDraft.init)
        exams = model.exames.map(TemplateExamDraft.init)
    }

    public var normalizedCodes: [String] {
        codes.components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map { $0.uppercased() }.filter { !$0.isEmpty }
    }

    public var validationError: String? {
        if name.cleaned.isEmpty || name.cleaned.count > 120 { return "Informe um nome com até 120 caracteres." }
        if condition.cleaned.count > 160 { return "Use até 160 caracteres na condição." }
        if normalizedCodes.count > 10 || normalizedCodes.contains(where: { $0.range(of: #"^[A-Z]\d{2}(\.\d{1,2})?$"#, options: .regularExpression) == nil }) {
            return "Informe até 10 códigos CID-10 válidos, separados por vírgula."
        }
        if guidance.cleaned.count > 4_000 { return "Use até 4.000 caracteres nas orientações." }
        if medicines.count > 50 || exams.count > 50 { return "Cada modelo aceita até 50 medicamentos e 50 exames." }
        if let error = medicines.compactMap(\.validationError).first { return error }
        if let error = exams.compactMap(\.validationError).first { return error }
        switch type {
        case .prescription:
            if medicines.isEmpty || !exams.isEmpty { return "O modelo de receita precisa de medicamentos e não pode conter exames." }
        case .exams:
            if exams.isEmpty || !medicines.isEmpty { return "O modelo de exames precisa de exames e não pode conter medicamentos." }
        case .guidance:
            if guidance.cleaned.isEmpty || !medicines.isEmpty || !exams.isEmpty { return "O modelo de orientações precisa de texto, sem medicamentos ou exames." }
        case .protocolPlan:
            if medicines.isEmpty && exams.isEmpty && guidance.cleaned.isEmpty { return "Mantenha pelo menos um medicamento, exame ou orientação no protocolo." }
        }
        return nil
    }
}

public struct TemplateMedicineDraft: Identifiable, Sendable {
    public let id = UUID()
    public var name: String
    public var dosage: String
    public var quantity: String
    public var continuous: Bool?
    public var dose: String
    public var frequency: String
    public var duration: String
    public var instructions: String
    public var concentration: String?
    public var pharmaceuticalForm: String?
    public var regulatoryCategory: String?

    public init(_ item: PrescriptionItem = PrescriptionItem(medicamento: "", posologia: "")) {
        name = item.medicamento; dosage = item.posologia; quantity = item.quantidade ?? ""
        continuous = item.usoContinuo; dose = item.dose ?? ""; frequency = item.frequencia ?? ""
        duration = item.duracao ?? ""; instructions = item.instrucoes ?? ""
        concentration = item.concentracao; pharmaceuticalForm = item.formaFarmaceutica; regulatoryCategory = item.categoriaRegulatoria
    }
    public var item: PrescriptionItem {
        PrescriptionItem(medicamento: name.cleaned, posologia: dosage.cleaned, quantidade: quantity.optionalText,
                         usoContinuo: continuous, dose: dose.optionalText, frequencia: frequency.optionalText,
                         duracao: duration.optionalText, instrucoes: instructions.optionalText, concentracao: concentration,
                         formaFarmaceutica: pharmaceuticalForm, categoriaRegulatoria: regulatoryCategory)
    }
    public var validationError: String? {
        if name.cleaned.isEmpty || name.cleaned.count > 200 { return "Cada medicamento precisa de nome com até 200 caracteres." }
        if dosage.cleaned.isEmpty || dosage.cleaned.count > 400 { return "Cada medicamento precisa de posologia com até 400 caracteres." }
        if quantity.cleaned.count > 80 { return "Use até 80 caracteres na quantidade." }
        if [dose, frequency, duration].contains(where: { $0.cleaned.count > 120 }) { return "Use até 120 caracteres em dose, frequência e duração." }
        if instructions.cleaned.count > 300 { return "Use até 300 caracteres nas instruções de cada medicamento." }
        return nil
    }
}

public struct TemplateExamDraft: Identifiable, Sendable {
    public let id = UUID()
    public var description: String
    public var code: String
    public var reason: String
    public init(_ item: TemplateExam = TemplateExam(descricao: "")) {
        description = item.descricao; code = item.tuss ?? ""; reason = item.justificativa ?? ""
    }
    public var item: TemplateExam { TemplateExam(descricao: description.cleaned, tuss: code.optionalText, justificativa: reason.optionalText) }
    public var validationError: String? {
        if description.cleaned.isEmpty || description.cleaned.count > 200 { return "Cada exame precisa de descrição com até 200 caracteres." }
        if code.cleaned.count > 20 { return "Use até 20 caracteres no código TUSS." }
        if reason.cleaned.count > 300 { return "Use até 300 caracteres na justificativa de cada exame." }
        return nil
    }
}

/// PATCH contains only modified fields. Unedited clinical content and sharing state are omitted.
public struct ClinicalTemplatePatch: Encodable, Sendable {
    private let original: ClinicalTemplate
    private let draft: ClinicalTemplateDraft
    public init(original: ClinicalTemplate, draft: ClinicalTemplateDraft) { self.original = original; self.draft = draft }
    private var medicinesChanged: Bool { !sameJSON(original.medicamentos, draft.medicines.map(\.item)) }
    private var examsChanged: Bool { !sameJSON(original.exames, draft.exams.map(\.item)) }
    public var hasChanges: Bool {
        original.nome != draft.name.cleaned || original.condicao != draft.condition.optionalText ||
        original.cid10 != draft.normalizedCodes || original.orientacoes != draft.guidance.optionalText ||
        medicinesChanged || examsChanged
    }
    private enum CodingKeys: String, CodingKey { case nome, condicao, cid10, orientacoes, medicamentos, exames }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if original.nome != draft.name.cleaned { try values.encode(draft.name.cleaned, forKey: .nome) }
        if original.condicao != draft.condition.optionalText { try values.encode(draft.condition.optionalText, forKey: .condicao) }
        if original.cid10 != draft.normalizedCodes { try values.encode(draft.normalizedCodes, forKey: .cid10) }
        if original.orientacoes != draft.guidance.optionalText { try values.encode(draft.guidance.optionalText, forKey: .orientacoes) }
        if medicinesChanged { try values.encode(draft.medicines.map(\.item), forKey: .medicamentos) }
        if examsChanged { try values.encode(draft.exams.map(\.item), forKey: .exames) }
    }
}

private func sameJSON<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    guard let first = try? encoder.encode(lhs), let second = try? encoder.encode(rhs) else { return false }
    return first == second
}

private extension String {
    var cleaned: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var optionalText: String? { cleaned.isEmpty ? nil : cleaned }
}
