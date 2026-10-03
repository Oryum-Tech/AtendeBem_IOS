import Foundation
import Testing
@testable import AtendeBemCore

private func consultationRecord(id: String = "evo-fiction", patient: String = "patient-fiction", author: String = "author-fiction",
                                version: Int? = 1, open: Bool? = true, text: String = "Anotação fictícia",
                                sections: [[String: String]]? = nil, complaint: String? = nil) throws -> String {
    var value: [String: Any] = ["id": id, "pacienteId": patient, "profissionalId": author,
                              "data": "2026-10-02T10:00:00-03:00", "tipo": "evolucao",
                              "soap": ["s": text], "cid10": [], "assinado": false]
    if let open { value["rascunhoAutomatico"] = open }
    if let version { value["rascunhoVersao"] = version; value["rascunhoSalvoEm"] = "2026-10-02T10:00:00-03:00" }
    if let sections { value["secoes"] = sections }
    if let complaint { value["queixaPrincipal"] = complaint }
    return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
}

private func openDraft(_ json: String?) -> String { "{\"rascunho\":\(json ?? "null")}" }

private actor ConsultationTransport: HTTPTransport {
    struct Step: Sendable {
        let method: String
        let body: String
        var status = 200
        var networkFailure = false
    }
    var steps: [Step]
    private var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { Issue.record("Unexpected request: \(request.httpMethod ?? "")"); throw APIError.invalidResponse }
        let next = steps.removeFirst()
        #expect(request.httpMethod == next.method)
        if next.networkFailure { throw URLError(.networkConnectionLost) }
        return (Data(next.body.utf8), HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!)
    }
    func writes(_ method: String) -> [URLRequest] { requests.filter { $0.httpMethod == method } }
}

private func consultationAPI(transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens, savedAt: .now)), transport: transport)
    _ = try await api.restoreSession()
    return api
}

@MainActor private func consultationModel(_ api: APIClient, canWrite: Bool = true) async -> ConsultationWorkflow {
    ConsultationWorkflow(api: api, context: await api.requestContextID(), patientID: "patient-fiction", authorID: "author-fiction", canWrite: canWrite)
}

@Test func consultationSectionsPreserveSavedOrderEmptyDeclaredFieldsAndOrphanText() throws {
    let emptyLabel = NoteSection(id: "hda", sigla: "", titulo: "")
    let emptySection = NoteSection(id: "contexto", sigla: "C", titulo: "Contexto")
    let content = ConsultationContent(notes: ["hda": "Texto fictício", "p": "Plano fictício", "extra": "Texto preservado"], sections: [emptySection, emptyLabel])
    #expect(content.displayedSections.map(\.id) == ["contexto", "hda", "extra", "p"])
    #expect(content.title(for: emptyLabel) == "H — hda")
    let wire = try content.preparedForSaving()
    #expect(wire.sections?.first == emptySection)
    #expect(wire.sections?[1] == emptyLabel)
    #expect(wire.notes == content.notes)
    #expect(wire.sections?.map(\.id) == content.displayedSections.map(\.id))
}

@Test func consultationValidationCountsComplaintAndCodesButRejectsEmptyNotesAndDuplicateLabels() throws {
    #expect(throws: (any Error).self) { try ConsultationContent().preparedForSaving() }
    #expect(try ConsultationContent(complaint: " Queixa fictícia ").preparedForSaving().complaint == "Queixa fictícia")
    #expect(try ConsultationContent(codes: [" z00.0 "]).preparedForSaving().codes == ["Z00.0"])
    let s = NoteSection(id: "s", sigla: "S", titulo: "Subjetivo")
    #expect(throws: (any Error).self) { try ConsultationContent(notes: ["s": "Texto"], sections: [s, s]).preparedForSaving() }
}

@Test @MainActor func consultationSavesOnlyAfterMatchingPreflightAndKeepsServerSnapshotSeparate() async throws {
    let original = try consultationRecord()
    let updated = try consultationRecord(version: 2, text: "Edição fictícia")
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)),
                                            .init(method: "GET", body: openDraft(original)), .init(method: "PUT", body: updated)])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load()
    model.content.notes["s"] = "Edição fictícia"
    #expect(model.hasUnsavedChanges)
    await model.save()
    #expect(!model.hasUnsavedChanges)
    #expect(model.saved?.version == 2)
    model.content.complaint = "Queixa nova"
    #expect(model.saved?.content.complaint == "")
    #expect(model.hasUnsavedChanges)
    let request = try #require(await transport.writes("PUT").first)
    let requestBody = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(body["versaoBase"] as? Int == 1)
    #expect(body["sobrescreverServidor"] == nil)
}

@Test @MainActor func consultationDoesNotRecreateDraftConfirmedElsewhereBeforeSave() async throws {
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(try consultationRecord())), .init(method: "GET", body: openDraft(nil))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.content.notes["s"] = "Não perder este texto"
    await model.save()
    #expect(await transport.writes("PUT").isEmpty)
    #expect(model.content.notes["s"] == "Não perder este texto")
    #expect(model.comparison != nil && model.comparison?.server == nil)
    #expect(!model.canSave)
}

@Test @MainActor func consultationDoesNotOverwriteDraftCreatedOnWebAfterEmptyInitialLoad() async throws {
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(nil)), .init(method: "GET", body: openDraft(try consultationRecord(text: "Texto web")))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.content.notes["s"] = "Texto local"
    await model.save()
    #expect(await transport.writes("PUT").isEmpty)
    #expect(model.comparison?.server?.content.notes["s"] == "Texto web")
    #expect(model.content.notes["s"] == "Texto local")
    model.keepLocalVersion()
    #expect(model.content.notes["s"] == "Texto local")
    #expect(model.saved?.content.notes["s"] == "Texto web")
    #expect(model.hasUnsavedChanges)
}

@Test @MainActor func consultationConflictOnPutPreservesTextAndRequiresExplicitComparisonChoice() async throws {
    let original = try consultationRecord()
    let remote = try consultationRecord(version: 2, text: "Texto web")
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)),
                                            .init(method: "PUT", body: "{}", status: 409), .init(method: "GET", body: openDraft(remote))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.content.notes["s"] = "Texto local"
    await model.save(); await model.save()
    #expect(await transport.writes("PUT").count == 1)
    #expect(model.content.notes["s"] == "Texto local")
    #expect(model.comparison?.server?.content.notes["s"] == "Texto web")
    model.useServerVersion()
    #expect(model.content.notes["s"] == "Texto web")
    #expect(!model.hasUnsavedChanges)
}

@Test @MainActor func consultationReviewInvalidatesWhenEditedAndPreflightStopsChangedServer() async throws {
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(try consultationRecord())),
                                            .init(method: "GET", body: openDraft(try consultationRecord(version: 2, text: "Mudou na web")))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.prepareReview()
    #expect(model.review != nil)
    model.content.complaint = "Mudança local"
    #expect(model.review == nil)
    model.content.complaint = ""; model.prepareReview(); await model.confirmReviewed()
    #expect(await transport.writes("POST").isEmpty)
    #expect(model.comparison?.server?.version == 2)
    #expect(model.content.notes["s"] == "Anotação fictícia")
}

@Test @MainActor func consultationAcceptsConfirmedSerializerOmissionOnlyAfterOpenDraftVerification() async throws {
    let original = try consultationRecord()
    let closed = try consultationRecord(version: nil, open: nil)
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)),
                                            .init(method: "POST", body: closed), .init(method: "GET", body: openDraft(nil))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.prepareReview(); await model.confirmReviewed(); await model.confirmReviewed()
    #expect(model.phase == .confirmed)
    #expect(model.confirmed?.rascunhoAutomatico == nil)
    #expect(model.confirmed?.assinado == false)
    #expect(!model.canSave)
    #expect(await transport.writes("POST").count == 1)
    let path = try #require(await transport.writes("POST").first?.url?.path)
    #expect(path.hasSuffix("/rascunho/confirmar"))
}

@Test @MainActor func consultationRejectsContradictoryOrForeignConfirmationAndNeverReplays() async throws {
    let original = try consultationRecord()
    let invalidResults = [try consultationRecord(version: 2, open: nil), try consultationRecord(version: 2, open: true),
                          try consultationRecord(id: "other-evolution", version: nil, open: false),
                          try consultationRecord(patient: "other-patient", version: nil, open: false),
                          try consultationRecord(author: "other-author", version: nil, open: false),
                          try consultationRecord(version: nil, open: false, text: "Conteúdo diferente")]
    for invalid in invalidResults {
        let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)), .init(method: "POST", body: invalid)])
        let model = await consultationModel(try await consultationAPI(transport: transport))
        await model.load(); model.prepareReview(); await model.confirmReviewed()
        model.prepareReview(); await model.confirmReviewed(); await model.save()
        #expect(model.phase == .uncertainConfirmation)
        #expect(model.confirmed == nil)
        #expect(model.content.notes["s"] == "Anotação fictícia")
        #expect(await transport.writes("POST").count == 1)
    }
}

@Test @MainActor func consultationRejectsConfirmationWhenSameIDRemainsOpen() async throws {
    let original = try consultationRecord()
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)),
                                            .init(method: "POST", body: try consultationRecord(version: nil, open: false)), .init(method: "GET", body: openDraft(original))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.prepareReview(); await model.confirmReviewed()
    #expect(model.phase == .uncertainConfirmation)
    #expect(model.confirmed == nil)
}

@Test @MainActor func consultationNetworkAmbiguityReconcilesThroughReadsOnly() async throws {
    let original = try consultationRecord()
    let closed = try consultationRecord(version: nil, open: nil)
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)),
                                            .init(method: "POST", body: "", networkFailure: true),
                                            .init(method: "GET", body: "[\(closed)]"), .init(method: "GET", body: openDraft(nil))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.prepareReview(); await model.confirmReviewed()
    #expect(model.phase == .uncertainConfirmation)
    #expect(model.shouldProtectExit)
    await model.confirmReviewed(); await model.reconcileConfirmation()
    #expect(model.phase == .confirmed)
    #expect(await transport.writes("POST").count == 1)
}

@Test @MainActor func consultationRejectedConfirmationAllowsFreshReviewWithoutAutomaticRetry() async throws {
    let original = try consultationRecord()
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)),
                                            .init(method: "POST", body: "{}", status: 422)])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.prepareReview(); await model.confirmReviewed(); await model.confirmReviewed()
    #expect(model.phase == .ready)
    #expect(model.review == nil)
    #expect(model.canReview)
    #expect(await transport.writes("POST").count == 1)
}

@Test @MainActor func consultationForbiddenVerificationAfterPostSuccessExpiresContentWithoutReplay() async throws {
    let original = try consultationRecord()
    let closed = try consultationRecord(version: nil, open: nil)
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(original)), .init(method: "GET", body: openDraft(original)),
                                            .init(method: "POST", body: closed), .init(method: "GET", body: "{}", status: 403),
                                            .init(method: "GET", body: "[\(closed)]"), .init(method: "GET", body: openDraft(nil))])
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.prepareReview(); await model.confirmReviewed()
    #expect(model.phase == .expired)
    #expect(!model.content.hasContent)
    #expect(model.saved == nil && model.review == nil)
    #expect(!model.canReview && !model.canSave)
    model.prepareReview(); await model.confirmReviewed()
    await model.reconcileConfirmation()
    #expect(model.phase == .expired)
    #expect(await transport.writes("POST").count == 1)
}

@Test @MainActor func consultationExplicitInvalidationDuringLoadNeverResurrectsData() async throws {
    let gate = ResponseGate()
    let response = openDraft(try consultationRecord())
    let transport = StubTransport { _ in await gate.suspend(); return (response, 200) }
    let model = await consultationModel(try await consultationAPI(transport: transport))
    let operation = Task { await model.load() }
    try await gate.waitForRequest()
    model.invalidate()
    await gate.resume(); await operation.value
    #expect(model.phase == .expired)
    #expect(!model.loaded && !model.content.hasContent)
    #expect(model.saved == nil && model.confirmed == nil)
}

@Test @MainActor func consultationUIContextChangeDuringPreflightStopsWriteWithoutAPILogout() async throws {
    let original = try consultationRecord()
    let gate = ResponseGate()
    actor Count { var value = 0; func next() -> Int { value += 1; return value } }
    let count = Count()
    let transport = StubTransport { request in
        if await count.next() == 2 { await gate.suspend() }
        #expect(request.httpMethod == "GET")
        return (openDraft(original), 200)
    }
    let api = try await consultationAPI(transport: transport)
    @MainActor final class ContextValidity { var current = true }
    let validity = ContextValidity()
    let model = ConsultationWorkflow(api: api, context: await api.requestContextID(), patientID: "patient-fiction",
        authorID: "author-fiction", canWrite: true, isContextValid: { validity.current })
    await model.load(); model.prepareReview()
    let operation = Task { await model.confirmReviewed() }
    try await gate.waitForRequest(); validity.current = false
    await gate.resume(); await operation.value
    #expect(model.phase == .expired)
    #expect(!model.content.hasContent)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test @MainActor func consultationDiscardDuringSentSaveNeverRestoresAcknowledgedText() async throws {
    let original = try consultationRecord()
    let updated = try consultationRecord(version: 2, text: "Texto enviado")
    let gate = ResponseGate()
    let transport = StubTransport { request in
        if request.httpMethod == "PUT" { await gate.suspend(); return (updated, 200) }
        return (openDraft(original), 200)
    }
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.content.notes["s"] = "Texto enviado"
    let operation = Task { await model.save() }
    try await gate.waitForRequest(); model.invalidate()
    await gate.resume(); await operation.value
    #expect(model.phase == .expired)
    #expect(!model.content.hasContent && model.saved == nil)
}

@Test @MainActor func consultationSaveAcknowledgesSentSnapshotWithoutErasingNewerEditorChanges() async throws {
    let original = try consultationRecord()
    let gate = ResponseGate()
    let response = try consultationRecord(version: 2, text: "Texto enviado")
    let transport = StubTransport { request in
        if request.httpMethod == "PUT" { await gate.suspend(); return (response, 200) }
        return (openDraft(original), 200)
    }
    let model = await consultationModel(try await consultationAPI(transport: transport))
    await model.load(); model.content.notes["s"] = "Texto enviado"
    let operation = Task { await model.save() }
    try await gate.waitForRequest()
    model.content.notes["s"] = "Edição posterior ao envio"
    await gate.resume(); await operation.value
    #expect(model.saved?.content.notes["s"] == "Texto enviado")
    #expect(model.content.notes["s"] == "Edição posterior ao envio")
    #expect(model.hasUnsavedChanges)
    #expect(!model.canReview)
}

@Test @MainActor func consultationContextChangeDuringPreflightPreventsPostAndClearsPatientData() async throws {
    let original = try consultationRecord()
    let gate = ResponseGate()
    actor Counter { var count = 0; func next() -> Int { count += 1; return count } }
    let counter = Counter()
    let transport = StubTransport { request in
        if await counter.next() == 2 { await gate.suspend() }
        #expect(request.httpMethod == "GET")
        return (openDraft(original), 200)
    }
    let api = try await consultationAPI(transport: transport)
    let model = await consultationModel(api)
    await model.load(); model.prepareReview()
    let operation = Task { await model.confirmReviewed() }
    try await gate.waitForRequest(); try await api.logout(); await gate.resume(); await operation.value
    #expect(model.phase == .expired)
    #expect(model.content.notes.isEmpty)
    #expect(model.saved == nil && model.review == nil && model.confirmed == nil)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test @MainActor func consultationReadOnlyProfileCannotSaveReviewOrConfirm() async throws {
    let transport = ConsultationTransport([.init(method: "GET", body: openDraft(try consultationRecord()))])
    let model = await consultationModel(try await consultationAPI(transport: transport), canWrite: false)
    await model.load(); model.content.notes["s"] = "Texto local"
    await model.save(); model.prepareReview(); await model.confirmReviewed()
    #expect(!model.canEdit && !model.canSave && !model.canReview)
    #expect(model.review == nil)
    #expect(await transport.writes("PUT").isEmpty)
    #expect(await transport.writes("POST").isEmpty)
}
