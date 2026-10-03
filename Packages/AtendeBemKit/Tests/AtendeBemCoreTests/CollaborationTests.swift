import Foundation
import Testing
@testable import AtendeBemCore

private let replySSE = """
event: token
data: {"texto":"Resposta de teste. "}

event: token
data: {"texto":"Revise as fontes."}

event: citacoes
data: {"citacoes":[{"fonte":"Fonte de teste","referencia":"https://example.invalid/fonte"}]}

event: disclaimer
data: {"disclaimer":"Revisão profissional necessária."}

event: fim
data: {"conversaId":"test-chat","mensagemId":"test-reply","ressalvaSupervisao":true,"custoBrl":0}

"""

@Test func lariPreservesTextCitationsAndSafetyNotice() throws {
    for source in [replySSE, replySSE.replacingOccurrences(of: "\n", with: "\r\n")] {
        let reply = try LARIReply.decodeSSE(Data(source.utf8), conversationID: "test-chat")
        #expect(reply.text == "Resposta de teste. Revise as fontes.")
        #expect(reply.disclaimer == "Revisão profissional necessária.")
        #expect(reply.citations.count == 1)
        #expect(reply.requiresSupervision)
        #expect(reply.id == "test-reply")
    }
}

@Test func lariRejectsTruncatedAndCrossConversationResponses() {
    let truncated = String(replySSE.prefix(upTo: replySSE.range(of: "event: fim")!.lowerBound))
    let noDisclaimer = replySSE.replacingOccurrences(of: "event: disclaimer\ndata: {\"disclaimer\":\"Revisão profissional necessária.\"}\n\n", with: "")
    for source in [truncated, noDisclaimer, replySSE + "\nevent: token\ndata: {\"texto\":\"late\"}\n\n", "{}", "event: token\ndata: invalid\n\n"] {
        #expect(throws: APIError.invalidResponse) { try LARIReply.decodeSSE(Data(source.utf8), conversationID: "test-chat") }
    }
    #expect(throws: APIError.invalidResponse) { try LARIReply.decodeSSE(Data(replySSE.utf8), conversationID: "other-chat") }
}

private func chatSession() throws -> StoredSession {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"test-access","refreshToken":"test-refresh","expiraEm":900}"#.utf8))
    return StoredSession(tokens: pair)
}

@Test func lariUsesAuthenticatedSSEContractAndDoesNotReplayWrites() async throws {
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/conversas/test-chat/mensagens")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
        #expect(body == ["texto": "Pergunta fictícia"])
        return ("{}", 401)
    }
    let api = APIClient(storage: MemoryStorage(try chatSession()), transport: transport)
    _ = try await api.restoreSession()
    await #expect(throws: APIError.http(401)) { try await api.lariReply(conversationID: "test-chat", text: "Pergunta fictícia") }
    #expect(await transport.all().count == 1)
}

@Test func lariDropsResponseAfterSessionChanges() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { _ in await gate.suspend(); return (replySSE, 200) }
    let api = APIClient(storage: MemoryStorage(try chatSession()), transport: transport)
    _ = try await api.restoreSession()
    let pending = Task { try await api.lariReply(conversationID: "test-chat", text: "Teste") }
    try await gate.waitForRequest()
    try await api.logout()
    await gate.resume()
    await #expect(throws: APIError.contextChanged) { try await pending.value }
}

@Test func clinicalStatisticsStayUnavailableToAccounting() throws {
    func user(_ role: String) throws -> User {
        try JSONDecoder().decode(User.self, from: Data("{\"id\":\"test\",\"nome\":\"Teste\",\"email\":\"test@example.invalid\",\"papeis\":[\"\(role)\"]}".utf8))
    }
    let accountant = try user("contabilista")
    #expect(accountant.canReadReports)
    #expect(!accountant.canReadAgenda)
    #expect(!accountant.canReadPrescriptionStatistics)
    #expect(try user("gestor").canReadPrescriptionStatistics)
    #expect(try user("dentista").canReadPrescriptionStatistics)
    #expect(try !user("recepcao").canReadPrescriptionStatistics)
}

@Test func collaborationContractsAcceptMissingOptionalFields() throws {
    let conversation = try JSONDecoder().decode(TeamConversation.self, from: Data(#"{"id":"c","outroId":"colleague","ultimaMensagem":null,"naoLidas":0,"ultimaEm":"2026-10-02T12:00:00-03:00"}"#.utf8))
    #expect(conversation.ultimaMensagem == nil)
    let post = try JSONDecoder().decode(CommunityPost.self, from: Data(#"{"id":"p","autorNome":"Anônimo","tipo":"post","conteudo":"Texto fictício","anonimo":true,"curtidas":0,"compartilhamentos":0,"curtiu":false,"salvou":false,"criadoEm":"2026-10-02T12:00:00-03:00"}"#.utf8))
    #expect(post.anonimo)
    #expect(post.original == nil)
}

@Test func patientHistoryDistinguishesUnansweredFromDeniedFalls() throws {
    for (json, label) in [("{\"quedas12m\":null}", "Não informado"), ("{\"quedas12m\":false}", "Não"), ("{\"quedas12m\":true}", "Sim")] {
        let history = try JSONDecoder().decode(PatientHistory.self, from: Data(json.utf8))
        #expect(history.fallsLabel == label)
    }
}

@Test func certificateReadinessRejectsTestExpiredAndUnknownStates() throws {
    let valid = #"{"cadastrado":true,"status":"valido","diasRestantes":90,"isTeste":false}"#
    let expiring = #"{"cadastrado":true,"status":"expirando","diasRestantes":0,"isTeste":false}"#
    for json in [valid, expiring] {
        #expect(try JSONDecoder().decode(ProfessionalCertificate.self, from: Data(json.utf8)).readyForSignature)
    }
    for json in [#"{"cadastrado":false}"#, #"{"cadastrado":true}"#,
                 valid.replacingOccurrences(of: "valido", with: "futuro"),
                 valid.replacingOccurrences(of: "90", with: "-1"),
                 valid.replacingOccurrences(of: "false", with: "true"),
                 valid.replacingOccurrences(of: ",\"isTeste\":false", with: "")] {
        #expect(try !JSONDecoder().decode(ProfessionalCertificate.self, from: Data(json.utf8)).readyForSignature)
    }
}

@Test func communityAllowsAnonymousOwnershipAndMissingConversationPeer() throws {
    let post = try JSONDecoder().decode(CommunityPost.self, from: Data(#"{"id":"p","autorNome":"Anônimo","ehAutor":true,"tipo":"post","conteudo":"Texto fictício","anonimo":true,"curtidas":0,"compartilhamentos":0,"curtiu":false,"salvou":false,"criadoEm":"2026-10-02T12:00:00-03:00"}"#.utf8))
    #expect(post.autorId == nil)
    #expect(post.ehAutor == true)
    let conversation = try JSONDecoder().decode(CommunityConversation.self, from: Data(#"{"id":"c","outro":null,"ultimaMensagem":null,"naoLidas":0,"ultimaEm":"2026-10-02T12:00:00-03:00"}"#.utf8))
    #expect(conversation.outro == nil)
}

@Test func deletingCommunityPostDoesNotReplayAfterUnauthorizedResponse() async throws {
    let transport = StubTransport { request in
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/comunidade/posts/post-fixture")
        return ("{}", 401)
    }
    let api = APIClient(storage: MemoryStorage(try chatSession()), transport: transport)
    _ = try await api.restoreSession()
    await #expect(throws: APIError.http(401)) {
        let _: EmptyResponse = try await api.delete(["comunidade", "posts", "post-fixture"])
    }
    #expect(await transport.all().count == 1)
}

@Test func pdfRequestsDocumentMediaTypeAndRejectsHTML() async throws {
    let transport = StubTransport { request in
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/pdf")
        return ("<html>Authentication expired</html>", 200)
    }
    let api = APIClient(storage: MemoryStorage(try chatSession()), transport: transport)
    _ = try await api.restoreSession()
    await #expect(throws: APIError.invalidResponse) { try await api.pdf(["receitas", "fixture", "pdf"]) }
}

@Test func timelineAccumulatesServerOrderWithoutCrossPatientOrSkippedPages() throws {
    func page(_ number: Int, patient: String = "fixture", id: String, warning: Bool = false) throws -> ClinicalTimeline {
        let warnings = warning ? #"[{"servico":"svc-exames","tiposAusentes":["exame"],"mensagem":"Fonte indisponível"}]"# : "[]"
        return try JSONDecoder().decode(ClinicalTimeline.self, from: Data("""
        {"pacienteId":"\(patient)","eventos":[{"tipo":"exame","data":"2026-10-02T12:00:00-03:00","titulo":"Registro fictício","origemId":"\(id)","origemServico":"svc-exames","metadados":{"dataEhRealizacao":false,"campoFuturo":{"valor":true}}}],"paginacao":{"page":\(number),"perPage":25,"total":3,"totalPaginas":3},"avisos":\(warnings)}
        """.utf8))
    }
    let first = try page(1, id: "a", warning: true)
    let second = try first.appending(page(2, id: "a"))
    #expect(second.eventos.count == 1)
    #expect(second.avisos.count == 1)
    #expect(second.eventos.first?.approximateDate == true)
    let third = try second.appending(page(3, id: "b"))
    #expect(third.eventos.map(\.origemId) == ["a", "b"])
    #expect(throws: APIError.invalidResponse) { try first.appending(page(3, id: "c")) }
    #expect(throws: APIError.invalidResponse) { try first.appending(page(2, patient: "other", id: "c")) }
}
