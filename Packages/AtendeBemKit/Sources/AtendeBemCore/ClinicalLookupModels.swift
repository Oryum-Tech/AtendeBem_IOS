import Foundation

public struct ClinicalCode: Decodable, Sendable, Identifiable {
    public let codigo: String
    public let descricao: String
    public var id: String { codigo }
}
public struct MedicineSearch: Decodable, Sendable {
    public let total: Int
    public let itens: [MedicineMatch]
}
public struct MedicineMatch: Decodable, Sendable, Identifiable {
    public let id: String
    public let nomeProduto: String
    public let principioAtivo: String?
    public let empresa: String?
    public let situacao: String
    public let concentracao: String?
    public let formaFarmaceutica: String?
    public let categoriaRegulatoria: String?
    public let fonte: String?
}
public struct PatientHistory: Decodable, Sendable {
    public let familiar: String?
    public let social: String?
    public let ocupacional: String?
    public let esportiva: String?
    public let quedas12m: Bool?
    public let quedasDetalhe: String?
    public let cirurgiasRegiao: String?
    public let fisioterapiaPrevia: String?
    public let dominancia: String?
    public let atualizadoEm: String?
    public var fallsLabel: String {
        switch quedas12m { case true: "Sim"; case false: "Não"; default: "Não informado" }
    }
}
