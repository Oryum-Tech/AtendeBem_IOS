import Foundation

public enum PrescriptionFontSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case standard = "padrao", large = "grande", extraLarge = "muito_grande"
    public var id: String { rawValue }
    public var title: String {
        switch self { case .standard: "Padrão (10,5 pt)"; case .large: "Grande (12 pt)"; case .extraLarge: "Muito grande (14 pt)" }
    }
}

public struct PrescriptionPreferences: Decodable, Sendable {
    public let tamanhoFonte: PrescriptionFontSize
    public let configurado: Bool
    public func needsSave(_ selection: PrescriptionFontSize) -> Bool { !configurado || selection != tamanhoFonte }
}

public struct ClinicDetails: Decodable, Sendable {
    public let id: String
    public let nome: String
    public let cnpj: String?
    public let cnes: String?
    public let telefone: String?
    public let endereco: Address
    public let especialidades: [String]
    public struct Address: Decodable, Sendable {
        public let logradouro: String?
        public let cidade: String?
        public let uf: String?
        public let cep: String?
    }
}

public enum ClinicalTemplateType: String, Codable, CaseIterable, Sendable, Identifiable {
    case prescription = "receita", exams = "exames", protocolPlan = "protocolo", guidance = "orientacoes"
    public var id: String { rawValue }
    public var title: String {
        switch self { case .prescription: "Receitas"; case .exams: "Exames"; case .protocolPlan: "Protocolos"; case .guidance: "Orientações" }
    }
}

public struct TemplateExam: Codable, Sendable {
    public let descricao: String
    public let tuss: String?
    public let justificativa: String?
    public init(descricao: String, tuss: String? = nil, justificativa: String? = nil) {
        self.descricao = descricao; self.tuss = tuss; self.justificativa = justificativa
    }
}

public struct ClinicalTemplate: Decodable, Sendable, Identifiable {
    public let id: String
    public let tipo: ClinicalTemplateType
    public let nome: String
    public let condicao: String?
    public let cid10: [String]
    public let compartilhado: Bool
    public let medicamentos: [PrescriptionItem]
    public let exames: [TemplateExam]
    public let orientacoes: String?
    public let usos: Int
    public let meu: Bool
    public let atualizadoEm: String

    // A mixed protocol must never be applied to a form that would silently drop half its content.
    public func canApply(to type: ClinicalTemplateType) -> Bool {
        guard tipo == type else { return false }
        switch type {
        case .prescription: return !medicamentos.isEmpty && exames.isEmpty
        case .exams: return !exames.isEmpty && medicamentos.isEmpty
        case .protocolPlan, .guidance: return false
        }
    }

    public var examIndication: String {
        ([orientacoes].compactMap { $0 } + exames.compactMap { item in
            item.justificativa.map { "\(item.descricao): \($0)" }
        }).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public struct CreateClinicalTemplate: Encodable, Sendable {
    public let tipo: ClinicalTemplateType
    public let nome: String
    public let compartilhado: Bool
    public let medicamentos: [PrescriptionItem]
    public let exames: [TemplateExam]
    public let orientacoes: String?
    public init(type: ClinicalTemplateType, name: String, medicines: [PrescriptionItem] = [], exams: [TemplateExam] = [], guidance: String? = nil) {
        tipo = type; nome = name; compartilhado = false
        medicamentos = medicines; exames = exams; orientacoes = guidance
    }
}

public enum AgendaPresentation {
    /// Both boundaries use the clinic's timezone, independently of the device timezone.
    public static func hour(of appointment: Appointment) -> Int? {
        guard let date = appointment.startDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ClinicClock.timeZone
        return calendar.component(.hour, from: date)
    }
    public static func hours(for appointments: [Appointment]) -> [Int] {
        let values = appointments.compactMap(hour)
        return Array(min(8, values.min() ?? 8)...max(18, values.max() ?? 18))
    }
}
