import Foundation

public struct LARIConversation: Decodable, Sendable {
    public let id: String
    public let disclaimer: String
}

public struct LARIReply: Sendable {
    public let id: String
    public let text: String
    public let disclaimer: String
    public let citations: [Citation]
    public let requiresSupervision: Bool

    public struct Citation: Decodable, Sendable {
        public let fonte: String
        public let referencia: String?
    }

    /// A response is complete only after the service's final event and safety notice.
    /// The current service generates the answer before emitting its SSE events.
    public static func decodeSSE(_ data: Data, conversationID: String) throws -> Self {
        guard data.count <= 2_000_000, let source = String(data: data, encoding: .utf8) else { throw APIError.invalidResponse }
        struct Token: Decodable { let texto: String }
        struct Sources: Decodable { let citacoes: [Citation] }
        struct Notice: Decodable { let disclaimer: String }
        struct End: Decodable { let conversaId: String; let mensagemId: String; let ressalvaSupervisao: Bool }
        let decoder = JSONDecoder()
        var text = "", notice = ""
        var citations: [Citation]?
        var end: End?
        for block in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            let event = lines.first { $0.hasPrefix("event:") }?.dropFirst(6).trimmingCharacters(in: .whitespaces)
            let payload = lines.filter { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            guard let event, !payload.isEmpty else { continue }
            guard end == nil else { throw APIError.invalidResponse }
            let bytes = Data(payload.utf8)
            do {
                switch event {
                case "token": text += try decoder.decode(Token.self, from: bytes).texto
                case "citacoes": citations = try decoder.decode(Sources.self, from: bytes).citacoes
                case "disclaimer": notice = try decoder.decode(Notice.self, from: bytes).disclaimer
                case "fim": end = try decoder.decode(End.self, from: bytes)
                default: throw APIError.invalidResponse
                }
            } catch { throw APIError.invalidResponse }
        }
        guard let end, end.conversaId == conversationID, !end.mensagemId.isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let citations else { throw APIError.invalidResponse }
        return Self(id: end.mensagemId, text: text, disclaimer: notice, citations: citations, requiresSupervision: end.ressalvaSupervisao)
    }
}

public struct TeamMember: Decodable, Sendable, Identifiable {
    public let id: String
    public let nome: String
    public let papeis: [String]
}
public struct TeamConversation: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let outroId: String
    public let ultimaMensagem: Preview?
    public let naoLidas: Int
    public let ultimaEm: String
    public struct Preview: Decodable, Sendable, Hashable {
        public let conteudo: String
        public let criadoEm: String
        public let minha: Bool
    }
}
public struct TeamMessage: Decodable, Sendable, Identifiable {
    public let id: String
    public let conversaId: String
    public let autorId: String
    public let conteudo: String
    public let criadoEm: String
    public let lidaEm: String?
}
public struct CommunityPost: Decodable, Sendable, Identifiable {
    public let id: String
    public let autorId: String?
    public let ehAutor: Bool?
    public let visibilidade: String?
    public let editadoEm: String?
    public let autorNome: String
    public let autorAvatarMidiaId: String?
    public let especialidade: String?
    public let titulo: String?
    public let conteudo: String
    public let tipo: String
    public let anonimo: Bool
    public let curtidas: Int
    public let compartilhamentos: Int
    public let curtiu: Bool
    public let salvou: Bool
    public let criadoEm: String
    public let midia: Media?
    public let original: Original?
    public struct Media: Decodable, Sendable { public let id: String; public let tipo: String }
    public struct Original: Decodable, Sendable {
        public let autorNome: String
        public let titulo: String?
        public let conteudo: String
    }
}

public struct CommunityProfile: Decodable, Sendable, Identifiable {
    public let usuarioId: String
    public let nome: String
    public let crm: String?
    public let especialidade: String?
    public let bio: String?
    public let redes: [String: String]
    public let avatarMidiaId: String?
    public let posts: Int
    public let seguidores: Int
    public let seguindo: Int
    public let seguidoPorMim: Bool
    public var id: String { usuarioId }
}

public struct CommunitySuggestion: Decodable, Sendable, Identifiable {
    public let usuarioId: String
    public let nome: String
    public let crm: String?
    public let especialidade: String?
    public let avatarMidiaId: String?
    public let seguidores: Int
    public var id: String { usuarioId }
}

public struct CommunityConversation: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    public let outro: Member?
    public let ultimaMensagem: TeamConversation.Preview?
    public let naoLidas: Int
    public let ultimaEm: String
    public struct Member: Decodable, Sendable, Hashable {
        public let usuarioId: String
        public let nome: String
        public let especialidade: String?
        public let avatarMidiaId: String?
    }
}

public struct ProfessionalCertificate: Decodable, Sendable {
    public let cadastrado: Bool
    public let titular: String?
    public let crm: String?
    public let tipo: String?
    public let emissor: String?
    public let validadeFim: String?
    public let diasRestantes: Int?
    public let status: String?
    public let isTeste: Bool?

    /// Missing or future/unknown states never authorize signing.
    public var readyForSignature: Bool {
        cadastrado && ["valido", "expirando"].contains(status ?? "") &&
            (diasRestantes ?? -1) >= 0 && isTeste == false
    }
}

public struct AgendaStatistics: Decodable, Sendable {
    public let mes: String
    public let total: Int
    public let concluidas: Int
    public let faltas: Int
    public let taxaFaltas: Double
    public let porSemana: [Week]
    public struct Week: Decodable, Sendable {
        public let rotulo: String
        public let total: Int
    }
}
public struct PrescriptionStatistics: Decodable, Sendable {
    public let mes: String
    public let total: Int
    public let emitidas: Int
    public let rascunhos: Int
    public let canceladas: Int
}

public extension User {
    var canReadReports: Bool { canReadAgenda || hasAnyRole(["contabilista"]) }
    var canReadPrescriptionStatistics: Bool { hasAnyRole(["medico", "dentista", "gestor"]) }
}
