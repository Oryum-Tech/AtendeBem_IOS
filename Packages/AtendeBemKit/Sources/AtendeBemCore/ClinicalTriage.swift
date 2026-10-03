import Foundation

/// A recorded triage and its own measurements, never an aggregate of unrelated vital signs.
public struct ClinicalTriage: Decodable, Sendable, Identifiable, PatientChartEntry {
    public let id: String
    public let pacienteId: String
    public let atendimentoId: String?
    public let queixaPrincipal: String
    public let classificacaoRisco: String
    public let observacoes: String?
    public let imc: Double?
    public let triadoPor: String
    public let triadaEm: String
    public let criadoEm: String
    public let sinaisVitais: [ClinicalVital]

    /// Preserve unknown classifications without assigning a clinical meaning or a priority.
    public var recordedRiskLabel: String {
        switch classificacaoRisco {
        case "vermelho": "Vermelho"
        case "laranja": "Laranja"
        case "amarelo": "Amarelo"
        case "verde": "Verde"
        case "azul": "Azul"
        default: classificacaoRisco.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Não informada" : classificacaoRisco
        }
    }
}

/// Validate the nested measurements as well as the containing record before displaying either.
public func validatedTriages(_ values: [ClinicalTriage], patientID: String) throws -> [ClinicalTriage] {
    _ = try validatedChartEntries(values, patientID: patientID)
    for value in values {
        _ = try validatedChartEntries(value.sinaisVitais, patientID: patientID)
    }
    return values
}
