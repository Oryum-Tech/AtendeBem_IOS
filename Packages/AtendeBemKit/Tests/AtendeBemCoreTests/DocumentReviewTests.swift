import Foundation
import Testing
@testable import AtendeBemCore

private func documentUser(role: String = "fisioterapeuta", id: String = "author-fiction") throws -> User {
    try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id": id, "nome": "Profissional fictício", "email": "example@example.invalid", "papeis": [role]]))
}
private func examJSON(patient: String = "patient-fiction", author: String = "author-fiction", title: String = "Exame fictício", signed: Bool = false) throws -> String {
    var data: [String: Any] = ["id": "document-fiction", "pacienteId": patient, "pacienteNome": "Paciente fictício", "medicoId": author,
                              "tipo": "laboratorial", "itens": [["descricao": title, "tuss": "123"]], "indicacaoClinica": "Indicação fictícia",
                              "status": "solicitado", "origem": "solicitada", "criadoEm": "2026-10-02T10:00:00-03:00"]
    if signed { data["assinatura"] = ["padrao": "ICP-Brasil", "certificado": "A1", "carimboTempo": "2026-10-02T10:10:00-03:00", "validador": "Fictício", "codigoVerificacao": "fiction"] }
    return String(decoding: try JSONSerialization.data(withJSONObject: data), as: UTF8.self)
}
private actor DocumentTransport: HTTPTransport {
    struct Step: Sendable { let method: String; let body: String; var fails = false; var status = 200 }
    var steps: [Step]
    var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { Issue.record("Unexpected document request"); throw APIError.invalidResponse }
        let step = steps.removeFirst(); #expect(request.httpMethod == step.method)
        if step.fails { throw URLError(.networkConnectionLost) }
        return (Data(step.body.utf8), HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: nil)!)
    }
    func writes() -> [URLRequest] { requests.filter { $0.httpMethod == "POST" } }
    func count() -> Int { requests.count }
}
private func documentAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens, savedAt: .now)), transport: transport)
    _ = try await api.restoreSession(); return api
}
@MainActor private func documentModel(_ api: APIClient) async throws -> DocumentReview {
    DocumentReview(api: api, context: await api.requestContextID(), kind: .exam, documentID: "document-fiction", patientID: "patient-fiction", user: try documentUser())
}

@Test func documentProjectionPreservesStructuredPrescriptionAndExamFields() throws {
    let json = #"{"id":"d","pacienteId":"p","profissionalId":"a","tipo":"simples","status":"rascunho","itens":[{"medicamento":"Fictício","posologia":"Texto fictício","quantidade":"2","dose":"dose fictícia","frequencia":"frequência fictícia","duracao":"duração fictícia","instrucoes":"instruções fictícias","usoContinuo":false}]}"#
    let prescription = ClinicalDocumentSnapshot(try JSONDecoder().decode(Prescription.self, from: Data(json.utf8)))
    for value in ["Quantidade: 2", "Dose: dose fictícia", "Frequência: frequência fictícia", "Duração: duração fictícia", "Instruções: instruções fictícias", "Uso contínuo: Não"] { #expect(prescription.detail.contains(value)) }
    let exam = ClinicalDocumentSnapshot(try JSONDecoder().decode(ExamRequest.self, from: Data(try examJSON().utf8)))
    #expect(exam.detail.contains("TUSS: 123")); #expect(exam.detail.contains("Indicação clínica: Indicação fictícia"))
    #expect(throws: (any Error).self) { try exam.validate(patientID: "another-patient") }
    #expect(throws: (any Error).self) { try exam.validate(patientID: "patient-fiction", authorID: "another-author") }
}
@Test func documentSignatureRequiresLiteralClinicalRoleAuthorAndUnsignedState() throws {
    let document = ClinicalDocumentSnapshot(try JSONDecoder().decode(ExamRequest.self, from: Data(try examJSON().utf8)))
    #expect(document.canSign(user: try documentUser()))
    for role in ["admin", "gestor", "recepcao"] { #expect(!document.canSign(user: try documentUser(role: role))) }
    #expect(!document.canSign(user: try documentUser(id: "other-author")))
    let signed = ClinicalDocumentSnapshot(try JSONDecoder().decode(ExamRequest.self, from: Data(try examJSON(signed: true).utf8)))
    #expect(!signed.canSign(user: try documentUser()))
}
@Test @MainActor func documentListRejectsCrossPatientDataAndDuplicateIdentity() async throws {
    for body in ["[\(try examJSON(patient: "another-patient"))]", "[\(try examJSON()),\(try examJSON())]"] {
        let model = try await documentModel(documentAPI(DocumentTransport([.init(method: "GET", body: body)])))
        await model.load(); #expect(model.document == nil); #expect(model.error != nil); #expect(!model.canSign)
    }
}
@Test @MainActor func documentChangedSinceReviewIsNeverSigned() async throws {
    let transport = DocumentTransport([.init(method: "GET", body: "[\(try examJSON())]"), .init(method: "GET", body: "[\(try examJSON(title: "Texto alterado na web"))]")])
    let api = try await documentAPI(transport); let model = try await documentModel(api)
    await model.load(); #expect(model.canSign); await model.sign()
    #expect(await transport.writes().isEmpty); #expect(model.document?.detail.contains("Texto alterado na web") == true)
    #expect(model.error != nil); #expect(!model.canSign)
}
@Test @MainActor func documentLostSignatureResponseDoesNotReplayEvenAfterRefresh() async throws {
    let body = "[\(try examJSON())]"
    let transport = DocumentTransport([.init(method: "GET", body: body), .init(method: "GET", body: body), .init(method: "POST", body: "", fails: true), .init(method: "GET", body: body), .init(method: "GET", body: body)])
    let model = try await documentModel(documentAPI(transport))
    await model.load(); await model.sign(); await model.load(); await model.sign()
    #expect(model.outcome == .uncertain); #expect(await transport.writes().count == 1); #expect(!model.canSign)
}
@Test @MainActor func documentLostSignatureResponseReconcilesExistingSignedDocument() async throws {
    let body = "[\(try examJSON())]"
    let transport = DocumentTransport([.init(method: "GET", body: body), .init(method: "GET", body: body), .init(method: "POST", body: "", fails: true), .init(method: "GET", body: "[\(try examJSON(signed: true))]")])
    let model = try await documentModel(documentAPI(transport)); await model.load(); await model.sign()
    #expect(model.outcome == .succeeded); #expect(model.error == nil); #expect(await transport.writes().count == 1)
}
@Test @MainActor func documentContextChangePreventsFurtherReadsAndSignatureWrites() async throws {
    let transport = DocumentTransport([.init(method: "GET", body: "[\(try examJSON())]")])
    let api = try await documentAPI(transport); let model = try await documentModel(api)
    await model.load(); try await api.logout(); await model.sign()
    #expect(await transport.writes().isEmpty); #expect(await transport.count() == 1); #expect(model.error != nil)
}

@Test @MainActor func documentAcceptedSignatureRemainsUncertainWhenReconciliationIsDenied() async throws {
    let body = "[\(try examJSON())]"
    let transport = DocumentTransport([.init(method: "GET", body: body), .init(method: "GET", body: body), .init(method: "POST", body: "{}"), .init(method: "GET", body: "{}", status: 403), .init(method: "GET", body: body), .init(method: "GET", body: body)])
    let model = try await documentModel(documentAPI(transport))
    await model.load(); await model.sign(); await model.load(); await model.sign()
    #expect(model.outcome == .uncertain); #expect(await transport.writes().count == 1)
}
@Test @MainActor func documentRevokedAccessAndWrongPatientClearPreviouslyLoadedContent() async throws {
    for step in [DocumentTransport.Step(method: "GET", body: "{}", status: 403), .init(method: "GET", body: "[\(try examJSON(patient: "another-patient"))]")] {
        let transport = DocumentTransport([.init(method: "GET", body: "[\(try examJSON())]"), step])
        let model = try await documentModel(documentAPI(transport))
        await model.load(); #expect(model.document != nil); await model.load()
        #expect(model.document == nil); #expect(model.updatedAt == nil); #expect(!model.canSign)
    }
}
