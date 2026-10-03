import Foundation
import Testing
@testable import AtendeBemCore

private let externalPatientID = "patient-fiction"
private let externalAuthorID = "author-fiction"
private func externalUser(_ role: String = "recepcao") throws -> User {
    try JSONDecoder().decode(User.self, from: Data(#"{"id":"author-fiction","nome":"Equipe fictícia","email":"example@example.invalid","papeis":["\#(role)"]}"#.utf8))
}
private func externalInput() -> ExternalExamInput {
    ExternalExamInput(patientID: externalPatientID, patientName: "Paciente fictício", type: "laboratorial",
                      items: [ExamItem(tuss: "000", descricao: "Exame fictício")], performedOn: "2026-10-01", laboratory: "Laboratório fictício")
}
private func externalJSON(id: String = "exam-fiction", patient: String = externalPatientID, author: String = externalAuthorID,
                          origin: String? = "externa", results: [[String: Any]]? = [], clinic: String = "clinic-fiction") throws -> Data {
    var object: [String: Any] = ["id": id, "pacienteId": patient, "pacienteNome": "Paciente fictício", "medicoId": author,
                               "clinicaId": clinic, "tipo": "laboratorial", "itens": [["tuss": "000", "descricao": "Exame fictício"]],
                               "status": "solicitado", "criadoEm": "2026-10-02T12:00:00.000Z", "atualizadoEm": "2026-10-02T12:00:00.000Z",
                               "realizadoEm": "2026-10-01T12:00:00.000Z", "laboratorio": "Laboratório fictício"]
    object["origem"] = origin; object["resultados"] = results; object["temResultado"] = results.map { !$0.isEmpty }
    return try JSONSerialization.data(withJSONObject: object)
}
private func externalResult(id: String = "result-fiction", report: String? = "Laudo fictício", file: ExamResultFile? = nil, altered: Bool = false) -> [String: Any] {
    var value: [String: Any] = ["id": id, "temArquivo": file != nil, "alterado": altered, "anexadoEm": "2026-10-02T12:30:00.000Z"]
    value["laudo"] = report; value["arquivoNome"] = file?.name; value["arquivoTipo"] = file?.contentType
    return value
}
private func externalArray(_ elements: [Data]) -> Data {
    Data(("[" + elements.map { String(decoding: $0, as: UTF8.self) }.joined(separator: ",") + "]").utf8)
}
private actor ExternalTransport: HTTPTransport {
    struct Step: Sendable {
        let method: String
        let suffix: String
        let data: Data
        var status = 200
        var lost = false
    }
    var steps: [Step]
    var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { Issue.record("Unexpected request in synthetic exam test"); throw APIError.invalidResponse }
        let step = steps.removeFirst()
        #expect(request.httpMethod == step.method); #expect(request.url!.path.hasSuffix(step.suffix))
        if step.lost { throw URLError(.networkConnectionLost) }
        return (step.data, HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: nil)!)
    }
    func writes() -> [URLRequest] { requests.filter { $0.httpMethod == "POST" && !$0.url!.path.hasSuffix("/auth/refresh") } }
    func count() -> Int { requests.count }
}
private func externalAPI(_ transport: any HTTPTransport, clinic: String? = nil) async throws -> APIClient {
    let access: String
    if let clinic {
        let claims = try JSONSerialization.data(withJSONObject: ["clinicaId": clinic]).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        access = "synthetic.\(claims).synthetic"
    } else { access = "synthetic" }
    let pair = try JSONDecoder().decode(TokenPair.self, from: JSONSerialization.data(withJSONObject: ["accessToken": access, "refreshToken": "synthetic", "expiraEm": 900]))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: pair)), transport: transport)
    _ = try await api.restoreSession(); return api
}
@MainActor private func externalWorkflow(_ api: APIClient, examID: String? = nil, role: String = "recepcao") async throws -> ExternalExamWorkflow {
    ExternalExamWorkflow(api: api, context: await api.requestContextID(), patientID: externalPatientID,
                         patientName: "Paciente fictício", user: try externalUser(role), examID: examID)
}

@Test func externalOriginBlocksRequisitionAndSignatureEvenWhenSolicitadoAndOwned() throws {
    let clinician = try externalUser("medico")
    for origin in [nil, "externa", "desconhecida"] as [String?] {
        let snapshot = ClinicalDocumentSnapshot(try JSONDecoder().decode(ExamRequest.self, from: externalJSON(origin: origin)))
        #expect(!snapshot.canOpenPDF); #expect(!snapshot.canSign(user: clinician)); #expect(snapshot.provenance == origin)
    }
    let requested = ClinicalDocumentSnapshot(try JSONDecoder().decode(ExamRequest.self, from: externalJSON(origin: "solicitada")))
    #expect(requested.canOpenPDF); #expect(requested.canSign(user: clinician))
}
@Test func externalReceiptUsesLiteralRolesAndPreservesMissingResultMetadata() throws {
    for role in User.careRoles + ["recepcao"] { #expect(ExternalExamPolicy.canReceive(user: try externalUser(role))) }
    for role in ["admin", "gestor", "contabilista", "desconhecido"] { #expect(!ExternalExamPolicy.canReceive(user: try externalUser(role))) }
    let absent = try JSONDecoder().decode(ExamRequest.self, from: externalJSON(results: nil))
    #expect(absent.resultados == nil); #expect(absent.temResultado == nil)
    #expect(absent.realizadoEm == "2026-10-01T12:00:00.000Z"); #expect(absent.laboratorio == "Laboratório fictício")
}
@Test func externalInputValidatesCivilDatesAndDoesNotInventDateOrAuthor() throws {
    let input = try externalInput().prepared()
    #expect(input.matches(try JSONDecoder().decode(ExamRequest.self, from: externalJSON()), authorID: externalAuthorID))
    #expect(ExternalExamInput.date("2026-02-30") == nil)
    #expect(ExternalExamInput.date("2024-02-29") != nil)
    let undated = try ExternalExamInput(patientID: "p", patientName: "Paciente fictício", type: "outro", items: [ExamItem(descricao: "Exame")]).prepared()
    let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(undated)) as! [String: Any]
    #expect(body["realizadoEm"] == nil); #expect(body["medicoId"] == nil); #expect(body["medicoNome"] == nil)
    #expect(throws: (any Error).self) { try ExternalExamInput(patientID: "p", patientName: "Fictício", type: "outro", items: []).prepared() }
}
@Test func externalFilesUseBytesAndSafeNamesWithoutDicomPreview() throws {
    let pdf = try ExamResultFile(data: Data("%PDF-1.7 synthetic".utf8), name: "../folder\\laudo\n.pdf")
    #expect(pdf.name == "laudo.pdf"); #expect(pdf.contentType == "application/pdf"); #expect(pdf.canPreview)
    let png = try ExamResultFile(data: Data([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0]), name: "image.png")
    #expect(png.contentType == "image/png")
    #expect(try ExamResultFile(data: Data([0xff,0xd8,0xff,0xd9]), name: "photo.jpg").contentType == "image/jpeg")
    var dicom = Data(repeating: 0, count: 128); dicom.append(Data("DICM0".utf8))
    let medicalImage = try ExamResultFile(data: dicom, name: "exame.dcm")
    #expect(medicalImage.contentType == "application/dicom"); #expect(!medicalImage.canPreview)
    #expect(throws: (any Error).self) { try ExamResultFile(data: Data("not a PDF".utf8), name: "fake.pdf") }
    #expect(throws: (any Error).self) { try ExamResultFile(data: pdf.data, name: "..") }
    #expect(throws: (any Error).self) { try ExamResultFile(data: Data(repeating: 0, count: ExamResultFile.maximumBytes + 1), name: "large.pdf") }
}
@Test func externalResultValidatesFullEncodedSizeBeforeSending() throws {
    #expect(throws: (any Error).self) { try ExamResultInput(report: "  ").prepared() }
    #expect(throws: (any Error).self) { try ExamResultInput(report: String(repeating: "x", count: 20_001)).prepared() }
    #expect(try ExamResultInput(report: "  Laudo fictício  ").prepared().report == "Laudo fictício")
    var oversizedBody = Data("%PDF-".utf8)
    oversizedBody.append(Data(repeating: 0, count: 19 * 1024 * 1024))
    let file = try ExamResultFile(data: oversizedBody, name: "large.pdf")
    #expect(throws: (any Error).self) { try ExamResultInput(file: file).prepared() }
}
@Test @MainActor func externalCreatePreservesRecordAfterAttachmentNetworkFailureAndNeverRecreates() async throws {
    let record = try externalJSON()
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exames", data: externalArray([])),
        .init(method: "POST", suffix: "/exames/externos", data: record),
        .init(method: "GET", suffix: "/exam-fiction", data: record),
        .init(method: "POST", suffix: "/exam-fiction/resultado", data: Data(), lost: true)])
    let model = try await externalWorkflow(externalAPI(transport))
    await model.create(externalInput()); #expect(model.creationOutcome == .succeeded)
    await model.attach(ExamResultInput(report: "Laudo fictício"))
    #expect(model.exam?.id == "exam-fiction"); #expect(model.attachmentOutcome == .uncertain)
    model.resetAttachment(); await model.attach(ExamResultInput(report: "Laudo fictício")); await model.create(externalInput())
    #expect(model.attachmentOutcome == .uncertain); #expect(await transport.writes().count == 2)
}
@Test @MainActor func externalLostCreateNeedsExplicitCandidateSelectionWithoutReplay() async throws {
    let record = try externalJSON()
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exames", data: externalArray([])),
        .init(method: "POST", suffix: "/externos", data: Data(), lost: true),
        .init(method: "GET", suffix: "/exames", data: externalArray([record])),
        .init(method: "GET", suffix: "/exam-fiction", data: record)])
    let model = try await externalWorkflow(externalAPI(transport))
    await model.create(externalInput()); await model.create(externalInput()); await model.reconcileCreation()
    #expect(model.exam == nil); #expect(model.creationCandidates.count == 1); #expect(model.creationOutcome == .uncertain)
    await model.selectCreatedExam(id: "exam-fiction")
    #expect(model.exam?.id == "exam-fiction"); #expect(model.creationOutcome == .succeeded); #expect(await transport.writes().count == 1)
}
@Test @MainActor func externalPreexistingIdenticalRecordCannotResolveLostCreate() async throws {
    let record = try externalJSON()
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exames", data: externalArray([record])),
        .init(method: "POST", suffix: "/externos", data: Data(), lost: true),
        .init(method: "GET", suffix: "/exames", data: externalArray([record]))])
    let model = try await externalWorkflow(externalAPI(transport))
    await model.create(externalInput()); await model.reconcileCreation(); await model.selectCreatedExam(id: "exam-fiction")
    #expect(model.creationCandidates.isEmpty); #expect(model.creationOutcome == .uncertain); #expect(model.exam == nil)
}
@Test @MainActor func externalCreateRejectsWrongPatientAuthorOrOriginResponse() async throws {
    for record in [try externalJSON(patient: "other"), try externalJSON(author: "other"), try externalJSON(origin: "solicitada")] {
        let transport = ExternalTransport([.init(method: "GET", suffix: "/exames", data: externalArray([])), .init(method: "POST", suffix: "/externos", data: record)])
        let model = try await externalWorkflow(externalAPI(transport)); await model.create(externalInput())
        #expect(model.creationOutcome == .uncertain); #expect(model.exam == nil); #expect(!model.canCreate)
    }
}
@Test @MainActor func externalPermissionAndContextGuardsPreventWrites() async throws {
    let transport = ExternalTransport([]); let api = try await externalAPI(transport)
    let restricted = try await externalWorkflow(api, role: "admin")
    await restricted.create(externalInput()); #expect(!restricted.canCreate); #expect(await transport.count() == 0)
    let reception = try await externalWorkflow(api); try await api.logout()
    await reception.create(externalInput()); #expect(!reception.canCreate); #expect(await transport.count() == 0)
}
@Test @MainActor func externalAttachOnlyReportConfirmsNewResultAndAllowsExplicitNextResult() async throws {
    let record = try externalJSON(), updated = try externalJSON(results: [externalResult()])
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record), .init(method: "GET", suffix: "/exam-fiction", data: record),
                                      .init(method: "POST", suffix: "/resultado", data: updated)])
    let model = try await externalWorkflow(externalAPI(transport), examID: "exam-fiction")
    await model.load(); await model.attach(ExamResultInput(report: " Laudo fictício "))
    #expect(model.attachmentOutcome == .succeeded); #expect(!model.canAttach); #expect(model.canStartAttachment)
    model.resetAttachment(); #expect(model.canAttach); #expect(model.exam?.resultados?.count == 1)
    let body = try JSONSerialization.jsonObject(with: #require(await transport.writes().first?.httpBody)) as! [String: Any]
    #expect(body["laudo"] as? String == "Laudo fictício"); #expect(body["alterado"] as? Bool == false); #expect(body["arquivoBase64"] == nil)
}
@Test @MainActor func externalAttachDoesNotMistakeOldResultForNewReceipt() async throws {
    let record = try externalJSON(results: [externalResult()])
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record), .init(method: "GET", suffix: "/exam-fiction", data: record),
                                      .init(method: "POST", suffix: "/resultado", data: record)])
    let model = try await externalWorkflow(externalAPI(transport), examID: "exam-fiction")
    await model.load(); await model.attach(ExamResultInput(report: "Laudo fictício"))
    #expect(model.attachmentOutcome == .uncertain); #expect(!model.canStartAttachment)
}
@Test @MainActor func externalAcceptedFileThenDeniedReadStaysUncertainAndReconcilesBytesWithoutReplay() async throws {
    let file = try ExamResultFile(data: Data("%PDF-1.7 synthetic".utf8), name: "ficticio.pdf")
    let record = try externalJSON(), updated = try externalJSON(results: [externalResult(file: file)])
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record), .init(method: "GET", suffix: "/exam-fiction", data: record),
        .init(method: "POST", suffix: "/resultado", data: updated), .init(method: "GET", suffix: "/exam-fiction", data: Data(), status: 403),
        .init(method: "GET", suffix: "/exam-fiction", data: updated), .init(method: "GET", suffix: "/exam-fiction", data: updated),
        .init(method: "GET", suffix: "/result-fiction/arquivo", data: file.data)])
    let model = try await externalWorkflow(externalAPI(transport), examID: "exam-fiction")
    await model.load(); await model.attach(ExamResultInput(report: "Laudo fictício", file: file))
    #expect(model.attachmentOutcome == .uncertain); #expect(model.exam == nil)
    model.resetAttachment(); await model.attach(ExamResultInput(report: "Laudo fictício", file: file)); await model.reconcileAttachment()
    #expect(model.attachmentOutcome == .succeeded); #expect(model.exam?.id == "exam-fiction"); #expect(await transport.writes().count == 1)
}
@Test @MainActor func externalFileReceiptRequiresExactBytesNotOnlyNameAndMime() async throws {
    let file = try ExamResultFile(data: Data("%PDF-1.7 expected".utf8), name: "ficticio.pdf")
    let record = try externalJSON(), updated = try externalJSON(results: [externalResult(file: file)])
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record), .init(method: "GET", suffix: "/exam-fiction", data: record),
        .init(method: "POST", suffix: "/resultado", data: updated), .init(method: "GET", suffix: "/exam-fiction", data: updated),
        .init(method: "GET", suffix: "/result-fiction/arquivo", data: Data("%PDF-1.7 different".utf8))])
    let model = try await externalWorkflow(externalAPI(transport), examID: "exam-fiction")
    await model.load(); await model.attach(ExamResultInput(report: "Laudo fictício", file: file))
    #expect(model.attachmentOutcome == .uncertain); #expect(await transport.writes().count == 1)
}
@Test @MainActor func externalRejectedAttachmentLeavesExistingExamAndExplicitRetryAvailable() async throws {
    let record = try externalJSON()
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record), .init(method: "GET", suffix: "/exam-fiction", data: record),
                                      .init(method: "POST", suffix: "/resultado", data: Data(), status: 422)])
    let model = try await externalWorkflow(externalAPI(transport), examID: "exam-fiction")
    await model.load(); await model.attach(ExamResultInput(report: "Laudo fictício"))
    #expect(model.attachmentOutcome == .ready); #expect(model.exam?.id == "exam-fiction"); #expect(model.canAttach)
}
@Test @MainActor func externalResultReadRejectsWrongPatientDuplicateResultsAndOtherClinic() async throws {
    let duplicate = externalResult()
    for record in [try externalJSON(patient: "other"), try externalJSON(results: [duplicate, duplicate]), try externalJSON(clinic: "other")] {
        let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record)])
        let model = try await externalWorkflow(externalAPI(transport, clinic: "clinic-fiction"), examID: "exam-fiction")
        await model.load(); #expect(model.exam == nil); #expect(!model.canAttach); #expect(model.error != nil)
    }
}
@Test @MainActor func externalMissingResultsCannotBeOverwrittenAndContextChangeClearsData() async throws {
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: try externalJSON(results: nil))])
    let api = try await externalAPI(transport); let model = try await externalWorkflow(api, examID: "exam-fiction")
    await model.load(); #expect(model.exam != nil); #expect(!model.canAttach)
    try await api.logout(); await model.load(); #expect(model.exam == nil); #expect(await transport.count() == 1)
}
@Test @MainActor func externalDownloadRequiresPatientResultIdentityAndMatchingBytesMime() async throws {
    let file = try ExamResultFile(data: Data("%PDF-1.7 synthetic".utf8), name: "file.pdf")
    let record = try externalJSON(results: [externalResult(file: file)])
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exam-fiction", data: record),
        .init(method: "GET", suffix: "/exam-fiction", data: record), .init(method: "GET", suffix: "/result-fiction/arquivo", data: Data([0xff,0xd8,0xff,0xd9]))])
    let api = try await externalAPI(transport); let service = ExternalExamService(api: api); let context = await api.requestContextID()
    await #expect(throws: (any Error).self) { try await service.resultFile(examID: "exam-fiction", resultID: "missing", patientID: externalPatientID, expectedContext: context) }
    #expect(await transport.count() == 1)
    await #expect(throws: (any Error).self) { try await service.resultFile(examID: "exam-fiction", resultID: "result-fiction", patientID: externalPatientID, expectedContext: context) }
}
@Test @MainActor func externalPost401RecoversThroughMeAndRefreshWithoutReplay() async throws {
    let me = Data(#"{"id":"author-fiction","nome":"Equipe fictícia","email":"example@example.invalid","papeis":["recepcao"]}"#.utf8)
    let pair = Data(#"{"accessToken":"renewed-synthetic","refreshToken":"renewed-synthetic","expiraEm":900}"#.utf8)
    let transport = ExternalTransport([.init(method: "GET", suffix: "/exames", data: externalArray([])),
        .init(method: "POST", suffix: "/externos", data: Data(), status: 401),
        .init(method: "GET", suffix: "/me", data: Data(), status: 401),
        .init(method: "POST", suffix: "/auth/refresh", data: pair), .init(method: "GET", suffix: "/me", data: me)])
    let model = try await externalWorkflow(externalAPI(transport)); await model.create(externalInput())
    #expect(model.creationOutcome == .ready); #expect(model.canCreate); #expect(await transport.writes().count == 1)
}

@Test @MainActor func externalLocalInvalidationDuringCreateDoesNotRepopulatePatientData() async throws {
    let gate = ResponseGate(), record = String(decoding: try externalJSON(), as: UTF8.self)
    let transport = StubTransport { request in
        if request.httpMethod == "GET" { return ("[]", 200) }
        await gate.suspend(); return (record, 201)
    }
    let api = try await externalAPI(transport), model = try await externalWorkflow(api)
    let context = await api.requestContextID()
    let operation = Task { await model.create(externalInput()) }
    try await gate.waitForRequest(); model.invalidate(); await gate.resume(); await operation.value
    #expect(await api.requestContextID() == context)
    #expect(model.exam == nil); #expect(model.creationCandidates.isEmpty); #expect(!model.canCreate); #expect(!model.canAttach)
}

@Test @MainActor func externalLocalInvalidationDuringReadOrPreflightDoesNotRestoreDataOrWrite() async throws {
    for existing in [false, true] {
        let gate = ResponseGate(), record = String(decoding: try externalJSON(), as: UTF8.self)
        let transport = StubTransport { _ in await gate.suspend(); return (existing ? record : "[]", 200) }
        let api = try await externalAPI(transport), model = try await externalWorkflow(api, examID: existing ? "exam-fiction" : nil)
        let operation = Task { if existing { await model.load() } else { await model.create(externalInput()) } }
        try await gate.waitForRequest(); model.invalidate(); await gate.resume(); await operation.value
        #expect(model.exam == nil); #expect(!model.canCreate); #expect(!model.canAttach)
        #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
    }
}
