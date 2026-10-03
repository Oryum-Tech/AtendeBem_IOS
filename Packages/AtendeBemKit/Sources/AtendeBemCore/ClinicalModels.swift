import Foundation

public struct AppointmentTypeCatalog: Decodable, Sendable {
    public let escopo: String
    public let itens: [AppointmentType]
}

public struct AppointmentType: Decodable, Sendable, Identifiable {
    public let id: String
    public let rotulo: String
    public let cor: String
    public let ordem: Int
    public let ativo: Bool
    public let sistemico: Bool
    public let contaComoRetorno: Bool
}

public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

public struct SOAPNote: Codable, Sendable, Equatable {
    public let values: [String: String]
    public var s: String? { values["s"] }
    public var o: String? { values["o"] }
    public var a: String? { values["a"] }
    public var p: String? { values["p"] }
    public init(s: String, o: String, a: String, p: String) { values = ["s": s, "o": o, "a": a, "p": p] }
    public init(values: [String: String]) { self.values = values }
    public init(from decoder: any Decoder) throws { values = try decoder.singleValueContainer().decode([String: String].self) }
    public func encode(to encoder: any Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(values) }
}

public struct NoteSection: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let sigla: String
    public let titulo: String
    public init(id: String, sigla: String, titulo: String) {
        self.id = id; self.sigla = sigla; self.titulo = titulo
    }
}

public struct ConsultationDraft: Decodable, Sendable { public let rascunho: Evolution? }

public struct DraftInput: Encodable, Sendable {
    public let soap: SOAPNote
    public let secoes: [NoteSection]?
    public let queixaPrincipal: String?
    public let cid10: [String]
    public let versaoBase: Int
    public init(soap: SOAPNote, sections: [NoteSection]?, complaint: String?, codes: [String], version: Int) {
        self.soap = soap; secoes = sections; queixaPrincipal = complaint; cid10 = codes; versaoBase = version
    }
}

public struct CIDSuggestion: Decodable, Sendable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    public let descricao: String
    public let confianca: Double
}

public struct SOAPSuggestion: Decodable, Sendable {
    public let soap: SOAPNote
    public let cid10Candidatos: [CIDSuggestion]
    public let disclaimer: String
    public let rascunho: Bool
}

public struct SOAPSuggestionRequest: Encodable, Sendable {
    public let transcricao: String
    public let pacienteId: String?

    public init(transcricao: String, pacienteId: String? = nil) {
        self.transcricao = transcricao
        self.pacienteId = pacienteId
    }
}

public struct CreateEvolution: Encodable, Sendable {
    public let pacienteId: String
    public let profissionalId: String
    public let tipo: String
    public let soap: SOAPNote
    public let cid10: [String]

    public init(pacienteId: String, profissionalId: String, soap: SOAPNote, cid10: [String]) {
        self.pacienteId = pacienteId
        self.profissionalId = profissionalId
        self.tipo = "evolucao"
        self.soap = soap
        self.cid10 = cid10
    }
}

public struct Evolution: Decodable, Sendable, Identifiable {
    public let id: String
    public let pacienteId: String
    public let profissionalId: String
    public let data: String
    public let tipo: String
    public let soap: SOAPNote
    public let cid10: [String]
    public let assinado: Bool
    public let secoes: [NoteSection]?
    public let queixaPrincipal: String?
    public let rascunhoAutomatico: Bool?
    public let rascunhoVersao: Int?
    public let criadoEm: String?
    public let escritaDiasDepois: Int?
    public let rascunhoSalvoEm: String?
}

public struct PrescriptionItem: Codable, Sendable, Identifiable {
    public var id: String { medicamento + posologia }
    public let medicamento: String
    public let posologia: String
    public let quantidade: String?
    public let usoContinuo: Bool?
    public let dose: String?
    public let frequencia: String?
    public let duracao: String?
    public let instrucoes: String?
    public let concentracao: String?
    public let formaFarmaceutica: String?
    public let categoriaRegulatoria: String?

    public init(medicamento: String, posologia: String, quantidade: String? = nil, usoContinuo: Bool? = nil, dose: String? = nil, frequencia: String? = nil, duracao: String? = nil, instrucoes: String? = nil, concentracao: String? = nil, formaFarmaceutica: String? = nil, categoriaRegulatoria: String? = nil) {
        self.medicamento = medicamento
        self.posologia = posologia
        self.quantidade = quantidade
        self.usoContinuo = usoContinuo
        self.dose = dose
        self.frequencia = frequencia
        self.duracao = duracao
        self.instrucoes = instrucoes
        self.concentracao = concentracao; self.formaFarmaceutica = formaFarmaceutica; self.categoriaRegulatoria = categoriaRegulatoria
    }
}

public struct CreatePrescription: Encodable, Sendable {
    public let id: String?
    public let modelo: String?
    public let pacienteId: String
    public let profissionalId: String
    public let tipo: String
    public let itens: [PrescriptionItem]
    public let orientacoes: String?
    public let justificativaAlergia: String?

    public init(
        pacienteId: String,
        profissionalId: String,
        tipo: String,
        itens: [PrescriptionItem],
        orientacoes: String?,
        justificativaAlergia: String?,
        id: String? = nil,
        modelo: String? = nil
    ) {
        self.id = id
        self.modelo = modelo
        self.pacienteId = pacienteId
        self.profissionalId = profissionalId
        self.tipo = tipo
        self.itens = itens
        self.orientacoes = orientacoes
        self.justificativaAlergia = justificativaAlergia
    }
}

public struct Prescription: Decodable, Sendable, Identifiable {
    public let id: String
    public let pacienteId: String
    public let profissionalId: String
    public let tipo: String
    public let itens: [PrescriptionItem]
    public let status: String
    public let emitidaEm: String?
    public let assinada: Bool?
    public let assinatura: DocumentSignature?
    public let procedencia: String?
    public let podeEnviar: Bool?
    public let orientacoes: String?
    public let justificativaAlergia: String?
}

public struct CreateMedicalDocument: Encodable, Sendable {
    public let pacienteId: String
    public let profissionalId: String
    public let tipo: String
    public let titulo: String?
    public let diasAfastamento: Int?
    public let cid: String?
    public let descricao: String?

    public init(
        pacienteId: String,
        profissionalId: String,
        tipo: String,
        titulo: String?,
        diasAfastamento: Int?,
        cid: String?,
        descricao: String?
    ) {
        self.pacienteId = pacienteId
        self.profissionalId = profissionalId
        self.tipo = tipo
        self.titulo = titulo
        self.diasAfastamento = diasAfastamento
        self.cid = cid
        self.descricao = descricao
    }
}

public struct MedicalDocument: Decodable, Sendable, Identifiable {
    public let id: String
    public let pacienteId: String
    public let profissionalId: String
    public let tipo: String
    public let titulo: String?
    public let diasAfastamento: Int?
    public let cid: String?
    public let descricao: String?
    public let status: String
    public let emitidoEm: String?
    public let assinatura: DocumentSignature?
}

public struct ExamItem: Codable, Sendable, Identifiable {
    public var id: String { (tuss ?? "") + descricao }
    public let tuss: String?
    public let descricao: String

    public init(tuss: String? = nil, descricao: String) {
        self.tuss = tuss
        self.descricao = descricao
    }
}

public struct CreateExamRequest: Encodable, Sendable {
    public let pacienteId: String
    public let pacienteNome: String
    public let tipo: String
    public let itens: [ExamItem]
    public let indicacaoClinica: String?
    public let medicoNome: String?
    public let medicoCrm: String?

    public init(
        pacienteId: String,
        pacienteNome: String,
        tipo: String,
        itens: [ExamItem],
        indicacaoClinica: String?,
        medicoNome: String?,
        medicoCrm: String?
    ) {
        self.pacienteId = pacienteId
        self.pacienteNome = pacienteNome
        self.tipo = tipo
        self.itens = itens
        self.indicacaoClinica = indicacaoClinica
        self.medicoNome = medicoNome
        self.medicoCrm = medicoCrm
    }
}

public struct ExamRequest: Decodable, Sendable, Identifiable {
    public let id: String
    public let pacienteId: String
    public let pacienteNome: String
    public let medicoId: String
    public let tipo: String
    public let itens: [ExamItem]
    public let indicacaoClinica: String?
    public let status: String
    public let criadoEm: String
    public let assinatura: DocumentSignature?
    public let origem: String?
    public let clinicaId: String?
    public let realizadoEm: String?
    public let laboratorio: String?
    public let atualizadoEm: String?
    public let temResultado: Bool?
    /// Missing results are deliberately distinct from a confirmed empty list.
    public let resultados: [ExamResult]?
}

public struct ExamResult: Decodable, Sendable, Identifiable {
    public let id: String
    public let laudo: String?
    public let arquivoNome: String?
    public let arquivoTipo: String?
    public let temArquivo: Bool
    public let alterado: Bool
    public let anexadoEm: String
    public let codigoVerificacao: String?
}

public struct TelemedicineRoom: Decodable, Sendable, Identifiable {
    public let id: String
    public let agendamentoId: String
    public let status: String
    public let criptografia: String
    public let expiraEm: String
}

public struct MediaToken: Decodable, Sendable {
    public let salaId: String
    public let participante: String
    public let token: String
    public let room: String
    public let url: String?
    public let expiraEm: String
    public let ttlSeg: Int
    public let criptografia: String
}

public struct FinancialSummary: Decodable, Sendable {
    public let faturamento: Double
    public let recebido: Double
    public let aReceber: Double
    public let despesas: Double
    public let ticketMedio: Double
    public let inadimplencia: Double
}

public struct FinancialEntry: Decodable, Sendable, Identifiable {
    public let id: String
    public let data: String
    public let tipo: String
    public let categoria: String
    public let descricao: String?
    public let valor: Double
    public let forma: String?
    public let status: String
    public let pacienteId: String?
}

public struct DocumentSignature: Decodable, Sendable, Equatable {
    public let padrao: String
    public let certificado: String
    public let carimboTempo: String
    public let validador: String
    public let codigoVerificacao: String
}
