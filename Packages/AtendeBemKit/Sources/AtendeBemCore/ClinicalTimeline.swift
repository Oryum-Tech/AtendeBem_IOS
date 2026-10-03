import Foundation

public struct ClinicalTimeline: Decodable, Sendable {
    public let pacienteId: String
    public let resumo: Summary?
    public var eventos: [Event]
    public let paginacao: Pagination
    public var avisos: [Warning]
    public struct Summary: Decodable, Sendable {
        public let totalConsultas: Int
        public let primeiraInteracao: String?
        public let ultimaInteracao: String?
        public let totalInternacoes: Int
        public let diasInternado: Int
        public let internacoesEmCurso: Int
        public let diagnosticosAtivos: Int
    }
    public struct Pagination: Decodable, Sendable {
        public let page: Int
        public let perPage: Int
        public let total: Int
        public let totalPaginas: Int
    }
    public struct Warning: Decodable, Sendable {
        public let servico: String
        public let tiposAusentes: [String]
        public let mensagem: String
    }
    public struct Event: Decodable, Sendable, Identifiable {
        public let tipo: String
        public let data: String
        public let dataFim: String?
        public let titulo: String
        public let descricao: String?
        public let origemId: String
        public let origemServico: String
        public let metadados: Metadata?
        public var id: String { origemServico + ":" + origemId }
        public struct Metadata: Decodable, Sendable {
            public let status: String?
            public let dataEhInicioInformado: Bool?
            public let dataEhRealizacao: Bool?
        }
        public var approximateDate: Bool {
            if tipo == "diagnostico" { return metadados?.dataEhInicioInformado == false }
            return ["procedimento", "exame"].contains(tipo) && metadados?.dataEhRealizacao == false
        }
    }

    /// Keeps server ordering and warns when any loaded page had missing sources.
    public func appending(_ next: ClinicalTimeline) throws -> ClinicalTimeline {
        guard next.pacienteId == pacienteId, next.paginacao.page == paginacao.page + 1 else { throw APIError.invalidResponse }
        var result = next
        var seen = Set(eventos.map(\.id))
        result.eventos = eventos + next.eventos.filter { seen.insert($0.id).inserted }
        result.avisos = avisos + next.avisos.filter { item in !avisos.contains { $0.servico == item.servico && $0.mensagem == item.mensagem } }
        return result
    }
}
