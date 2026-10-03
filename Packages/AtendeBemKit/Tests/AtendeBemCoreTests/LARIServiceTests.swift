import Foundation
import Testing
@testable import AtendeBemCore

private let lariConversationFixture = #"{"id":"cnv-fixture","disclaimer":"Revisão profissional necessária."}"#
private let lariProfileFixture = #"{"id":"user-fixture","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["medico"]}"#
private let lariResponseFixture = """
event: token
data: {"texto":"Resposta fictícia."}

event: citacoes
data: {"citacoes":[]}

event: disclaimer
data: {"disclaimer":"Revisão profissional necessária."}

event: fim
data: {"conversaId":"cnv-fixture","mensagemId":"msg-fixture","ressalvaSupervisao":true}

"""

private func lariSessionFixture() throws -> StoredSession {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"lari-old","refreshToken":"lari-refresh","expiraEm":900}"#.utf8))
    return StoredSession(tokens: pair)
}

@Test func lariContinuationPreservesExistingDraftAndEntireSelectedExchange() throws {
    let original = "Minha próxima pergunta fictícia, mantendo valores 1,25 e ½.\nSegunda linha. "
    let question = "Pergunta fictícia anterior\nsem alterações."
    let answer = "Resposta fictícia\ncom instrução completa."
    let combined = try LARIContinuation.draft(question: question, reply: answer, preserving: original)
    #expect(combined.hasPrefix(original + "\n\n"))
    #expect(combined.contains(question))
    #expect(combined.hasSuffix(answer))
    #expect(original == "Minha próxima pergunta fictícia, mantendo valores 1,25 e ½.\nSegunda linha. ")
}

@Test func lariContinuationRejectsOversizeWithoutTruncatingClinicalContext() throws {
    let original = "Rascunho que deve permanecer intacto."
    let answer = String(repeating: "Valor clínico fictício 123. ", count: 200)
    do {
        _ = try LARIContinuation.draft(question: "Pergunta", reply: answer, preserving: original)
        Issue.record("Oversize context must require user selection; never truncate")
    } catch let error as LARIContinuationError {
        guard case .tooLong(let count) = error else { return }
        #expect(count > LARIContinuation.maximumCharacters)
    }
    #expect(original == "Rascunho que deve permanecer intacto.")
    let base = try LARIContinuation.draft(question: "P", reply: "R", preserving: "")
    let exact = try LARIContinuation.draft(question: "P", reply: "R" + String(repeating: "x", count: 4_000 - base.count), preserving: "")
    #expect(exact.count == 4_000)
    #expect(throws: LARIContinuationError.self) {
        try LARIContinuation.draft(question: "P", reply: "R" + String(repeating: "x", count: 4_001 - base.count), preserving: "")
    }
}

@Test func lariRenewsRejectedSessionWithoutReplayingMessageAndManualRetryUsesSameConversation() async throws {
    let transport = StubTransport { request in
        switch request.url?.path {
        case "/v1/conversas": return (lariConversationFixture, 201)
        case "/v1/auth/refresh": return (#"{"accessToken":"lari-new","refreshToken":"new-refresh","expiraEm":900}"#, 200)
        case "/v1/me":
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer lari-old" ? ("{}", 401) : (lariProfileFixture, 200)
        case "/v1/conversas/cnv-fixture/mensagens":
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            #expect(body == ["texto": "Pergunta fictícia"])
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer lari-old" ? ("{}", 401) : (lariResponseFixture, 200)
        default: Issue.record("Unexpected route"); return ("{}", 500)
        }
    }
    let api = APIClient(storage: MemoryStorage(try lariSessionFixture()), transport: transport)
    _ = try await api.restoreSession()
    let expected = await api.requestContextID()
    var preserved: LARIConversation?
    do {
        _ = try await LARIService(api: api).send(text: "Pergunta fictícia", conversation: nil, expectedContext: expected)
        Issue.record("Rejected POST must not be replayed automatically")
    } catch let failure as LARISendFailure {
        #expect(failure.sessionRenewed)
        #expect(!failure.messageMayHaveBeenReceived)
        #expect(failure.conversation?.id == "cnv-fixture")
        preserved = failure.conversation
    }
    #expect(await transport.count("/v1/conversas/cnv-fixture/mensagens") == 1)
    #expect(await transport.count("/v1/auth/refresh") == 1)
    #expect(await api.requestContextID() == expected)
    let result = try await LARIService(api: api).send(text: "Pergunta fictícia", conversation: preserved, expectedContext: expected)
    #expect(result.reply.text == "Resposta fictícia.")
    #expect(await transport.count("/v1/conversas") == 1)
    #expect(await transport.count("/v1/conversas/cnv-fixture/mensagens") == 2)
}

@Test func lariDistinguishesConversationCreationFailureFromUncertainMessage() async throws {
    for failCreating in [true, false] {
        let transport = StubTransport { request in
            if request.url?.path == "/v1/conversas", !failCreating { return (lariConversationFixture, 201) }
            return ("{}", 503)
        }
        let api = APIClient(storage: MemoryStorage(try lariSessionFixture()), transport: transport)
        _ = try await api.restoreSession()
        do {
            _ = try await LARIService(api: api).send(text: "Texto fictício", conversation: nil, expectedContext: await api.requestContextID())
            Issue.record("Expected service failure")
        } catch let failure as LARISendFailure {
            #expect(failure.messageMayHaveBeenReceived == !failCreating)
            #expect(!failure.sessionRenewed)
            #expect((failure.conversation == nil) == failCreating)
        }
        #expect(await transport.count("/v1/conversas/cnv-fixture/mensagens") == (failCreating ? 0 : 1))
    }
}

@Test func lariChecksContextBeforeCreatingOrSendingAnything() async throws {
    let transport = StubTransport { _ in Issue.record("Old context must never reach HTTP"); return ("{}", 500) }
    let api = APIClient(storage: MemoryStorage(try lariSessionFixture()), transport: transport)
    _ = try await api.restoreSession()
    let old = await api.requestContextID()
    try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        try await LARIService(api: api).send(text: "Texto fictício", conversation: nil, expectedContext: old)
    }
    #expect(await transport.all().isEmpty)
}

@Test func lariRejectsSessionChangedWhileOpeningConversationWithoutSendingPrompt() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/conversas")
        await gate.suspend()
        return (lariConversationFixture, 201)
    }
    let api = APIClient(storage: MemoryStorage(try lariSessionFixture()), transport: transport)
    _ = try await api.restoreSession()
    let expected = await api.requestContextID()
    let task = Task { try await LARIService(api: api).send(text: "Texto fictício", conversation: nil, expectedContext: expected) }
    try await gate.waitForRequest()
    try await api.logout()
    await gate.resume()
    await #expect(throws: APIError.contextChanged) { try await task.value }
    #expect(await transport.count("/v1/conversas/cnv-fixture/mensagens") == 0)
}

@Test func lariInterruptedWaitPreservesConversationAndDoesNotRetryMessage() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { request in
        if request.url?.path == "/v1/conversas" { return (lariConversationFixture, 201) }
        await gate.suspend()
        return (lariResponseFixture, 200)
    }
    let api = APIClient(storage: MemoryStorage(try lariSessionFixture()), transport: transport)
    _ = try await api.restoreSession()
    let expected = await api.requestContextID()
    let task = Task { try await LARIService(api: api).send(text: "Texto fictício", conversation: nil, expectedContext: expected) }
    try await gate.waitForRequest()
    task.cancel()
    await gate.resume()
    do {
        _ = try await task.value
        Issue.record("Expected interrupted wait")
    } catch let failure as LARISendFailure {
        #expect(failure.underlying is CancellationError)
        #expect(failure.messageMayHaveBeenReceived)
        #expect(failure.conversation?.id == "cnv-fixture")
    }
    #expect(await transport.count("/v1/conversas/cnv-fixture/mensagens") == 1)
}

@Test func lariTruncatedReplyIsUncertainAndNeverBecomesConfirmedMessage() async throws {
    let transport = StubTransport { request in
        if request.url?.path == "/v1/conversas" { return (lariConversationFixture, 201) }
        return ("event: token\ndata: {\"texto\":\"Resposta incompleta\"}\n\n", 200)
    }
    let api = APIClient(storage: MemoryStorage(try lariSessionFixture()), transport: transport)
    _ = try await api.restoreSession()
    do {
        _ = try await LARIService(api: api).send(text: "Texto fictício", conversation: nil, expectedContext: await api.requestContextID())
        Issue.record("Incomplete response must not be displayed as confirmed")
    } catch let failure as LARISendFailure {
        #expect(failure.underlying as? APIError == .invalidResponse)
        #expect(failure.messageMayHaveBeenReceived)
    }
    #expect(await transport.count("/v1/conversas/cnv-fixture/mensagens") == 1)
}
