import Foundation

public struct PatientAddress: Decodable, Sendable {
    public let logradouro: String?
    public let numero: String?
    public let complemento: String?
    public let bairro: String?
    public let cidade: String?
    public let uf: String?
    public let cep: String?
}

public struct PatientInsurance: Decodable, Sendable {
    public let operadora: String?
    public let plano: String?
    public let carteirinha: String?
    public let validade: String?
}

public struct PatientEmergencyContact: Decodable, Sendable {
    public let nome: String?
    public let parentesco: String?
    public let celular: String?
}

public protocol PatientChartEntry: Sendable { var pacienteId: String { get } }
extension Evolution: PatientChartEntry {}

/// Reject an unexpected patient's row before it can be rendered in the current chart.
public func validatedChartEntries<T: PatientChartEntry>(_ values: [T], patientID: String) throws -> [T] {
    guard values.allSatisfy({ $0.pacienteId == patientID }) else { throw APIError.invalidResponse }
    return values
}

public struct ClinicalProblem: Decodable, Sendable, Identifiable, PatientChartEntry {
    public let id: String
    public let pacienteId: String
    public let numero: Int
    public let descricao: String
    public let cid10: String?
    public let status: String
    public let inicioEm: String?
    public let resolvidoEm: String?
    public let registradoPor: String?
    public let criadoEm: String
}

public struct ClinicalVital: Decodable, Sendable, Identifiable, PatientChartEntry {
    public let id: String
    public let pacienteId: String
    public let tipo: String
    public let valor: Double
    public let unidade: String?
    public let medidoEm: String
    public var title: String {
        ["pa_sistolica": "Pressão sistólica", "pa_diastolica": "Pressão diastólica", "fc": "Frequência cardíaca",
         "fr": "Frequência respiratória", "temperatura": "Temperatura", "spo2": "Saturação de oxigênio",
         "peso": "Peso", "altura": "Altura", "glicemia": "Glicemia", "dor": "Dor"][tipo] ?? tipo
    }
}

/// Professional chart entries are not the same resource as medication reported in the patient portal.
public struct ClinicalMedication: Decodable, Sendable, Identifiable, PatientChartEntry {
    public let id: String
    public let pacienteId: String
    public let nome: String
    public let posologia: String?
    public let ativo: Bool
    public let criadoEm: String
}

public struct ReportedMedicationList: Decodable, Sendable {
    public let medicamentos: [ReportedMedication]
    public let cobertura: Coverage
    public struct Coverage: Decodable, Sendable {
        public let ativos: Int
        public let comPrincipioAtivo: Int
        public let semPrincipioAtivo: [String]
    }
}

public struct ReportedMedication: Decodable, Sendable, Identifiable, PatientChartEntry {
    public let id: String
    public let pacienteId: String
    public let nome: String
    public let concentracao: String?
    public let forma: String?
    public let via: String?
    public let esquema: String
    public let horarios: [String]
    public let unidadesPorTomada: Double?
    public let inicioEm: String?
    public let observacao: String?
    public let ativo: Bool
    public let suspensoEm: String?
    public let motivoSuspensao: String?
    public let identificacao: Identification
    public let procedencia: Provenance
    public let registradoEm: String
    public let atualizadoEm: String
    public let vistoEm: String?
    public struct Identification: Decodable, Sendable {
        public let principioAtivo: String?
        public let catalogoId: String?
        public let entraNaChecagem: Bool
    }
    public struct Provenance: Decodable, Sendable {
        public let relatadoPor: String
        public let canal: String
        public let origem: String
        public let receitaId: String?
        public let prescritoPor: String?
    }
    public var scheduleLabel: String {
        switch esquema {
        case "horarios_fixos": horarios.isEmpty ? "Horários não informados" : horarios.joined(separator: ", ")
        case "se_necessario": "Se necessário"
        case "nao_informado": "Esquema de uso não informado"
        default: "Esquema: \(esquema)"
        }
    }
}

public struct ClinicalNoteDisplaySection: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let text: String
}

public extension Evolution {
    /// Preserve the labels and order saved with the note, including renamed canonical sections.
    var displaySections: [ClinicalNoteDisplaySection] {
        var result: [ClinicalNoteDisplaySection] = []
        var seen = Set<String>()
        for section in secoes ?? [] where seen.insert(section.id).inserted {
            result.append(.init(id: section.id, title: "\(section.sigla) — \(section.titulo)", text: soap.values[section.id] ?? ""))
        }
        let canonical = ["s", "o", "a", "p"]
        let labels = ["s": "S — Subjetivo", "o": "O — Objetivo", "a": "A — Avaliação", "p": "P — Plano"]
        for key in canonical + soap.values.keys.filter({ !canonical.contains($0) }).sorted() {
            guard let text = soap.values[key], seen.insert(key).inserted else { continue }
            result.append(.init(id: key, title: labels[key] ?? key, text: text))
        }
        return result
    }
}
