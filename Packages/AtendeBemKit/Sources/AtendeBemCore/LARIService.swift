import Foundation

public struct LARIExchange: Sendable {
    public let conversation: LARIConversation
    public let reply: LARIReply
}

/// Keeps a rejected or uncertain write separate from a confirmed assistant reply.
public struct LARISendFailure: Error, Sendable {
    public let conversation: LARIConversation?
    public let underlying: any Error
    public let sessionRenewed: Bool
    public let messageMayHaveBeenReceived: Bool
}

public enum LARIContinuationError: Error, LocalizedError, Equatable, Sendable {
    case tooLong(characterCount: Int)
    public var errorDescription: String? {
        switch self {
        case .tooLong(let count):
            "O contexto com seu rascunho teria \(count) caracteres, acima do limite de 4.000. Nenhum texto foi alterado ou cortado. Selecione ou resuma apenas o contexto necessário antes de enviar."
        }
    }
}

public enum LARIContinuation {
    public static let maximumCharacters = 4_000

    /// An explicit, editable addition. It never truncates clinical text or sends a request.
    public static func draft(question: String, reply: String, preserving existing: String) throws -> String {
        let context = "Contexto anterior selecionado para revisão:\nPergunta anterior:\n\(question)\nResposta anterior da LARI:\n\(reply)"
        let combined = existing.isEmpty ? context : existing + "\n\n" + context
        guard combined.count <= maximumCharacters else { throw LARIContinuationError.tooLong(characterCount: combined.count) }
        return combined
    }
}

public struct LARIService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func send(text: String, conversation: LARIConversation?, expectedContext: UUID) async throws -> LARIExchange {
        var current = conversation
        var messageStarted = false
        do {
            try await requireContext(expectedContext)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidResponse }
            if current == nil {
                current = try await api.post(["conversas"], body: [String: String](), expectedContext: expectedContext)
            }
            try await requireContext(expectedContext)
            guard let current, !current.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !current.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidResponse }
            messageStarted = true
            let reply = try await api.lariReply(conversationID: current.id, text: text, expectedContext: expectedContext)
            try await requireContext(expectedContext)
            return LARIExchange(conversation: current, reply: reply)
        } catch {
            // Never carry an old conversation or text into another clinic/session.
            let actualContext = await api.requestContextID()
            if error as? APIError == .contextChanged || actualContext != expectedContext { throw APIError.contextChanged }
            if error as? APIError == .sessionExpired { throw error }
            if error as? APIError == .http(401) {
                do {
                    // GET uses the existing refresh path. The rejected POST is never replayed here.
                    let _: User = try await api.get(["me"])
                    try await requireContext(expectedContext)
                } catch {
                    let actualContext = await api.requestContextID()
                    if error as? APIError == .contextChanged || actualContext != expectedContext { throw APIError.contextChanged }
                    throw LARISendFailure(conversation: current, underlying: error, sessionRenewed: false, messageMayHaveBeenReceived: false)
                }
                throw LARISendFailure(conversation: current, underlying: APIError.http(401), sessionRenewed: true, messageMayHaveBeenReceived: false)
            }
            let rejected = (error as? APIError)?.statusCode.map { [400, 402, 403, 404, 409, 412, 422, 429].contains($0) } ?? false
            throw LARISendFailure(conversation: current, underlying: error, sessionRenewed: false,
                                  messageMayHaveBeenReceived: messageStarted && !rejected)
        }
    }

    private func requireContext(_ expected: UUID) async throws {
        try Task.checkCancellation()
        guard await api.requestContextID() == expected else { throw APIError.contextChanged }
    }
}
