import Foundation
import Testing
@testable import AtendeBemCore

private let assistantFixture = #"{"soap":{"s":"Relato fictício organizado","o":"Achado fictício revisável","a":"Avaliação fictícia","p":"Plano fictício"},"cid10Candidatos":[{"codigo":"Z00.0","descricao":"Descrição fictícia","confianca":0.7}],"citacoes":[{"fonte":"Referência sintética","referencia":"https://example.invalid/reference"}],"disclaimer":"Sugestão fictícia que exige revisão profissional.","rascunho":true}"#

private func assistantAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens, savedAt: .now)), transport: transport)
    _ = try await api.restoreSession()
    return api
}

@MainActor private func assistantFixtureModel(_ api: APIClient, baseline: ConsultationContent = .init()) async -> ConsultationAssistant {
    ConsultationAssistant(api: api, context: await api.requestContextID(), patientID: "patient-fiction", baseline: baseline)
}

@MainActor private func assistantFixtureWorkflow(_ api: APIClient, baseline: ConsultationContent = .init(), canWrite: Bool = true) async -> ConsultationWorkflow {
    let workflow = ConsultationWorkflow(api: api, context: await api.requestContextID(), patientID: "patient-fiction", authorID: "author-fiction", canWrite: canWrite)
    await workflow.load()
    workflow.content = baseline
    return workflow
}

private func assistantFixtureTransport() -> StubTransport {
    StubTransport { request in
        if request.httpMethod == "GET" { return (#"{"rascunho":null}"#, 200) }
        return (assistantFixture, 200)
    }
}

@Test func assistantAppendsOnlySelectedReviewedSOAPAndPreservesClinicalSnapshot() throws {
    let sections = [NoteSection(id: "hda", sigla: "H", titulo: "História"), NoteSection(id: "s", sigla: "", titulo: "Relato"), NoteSection(id: "vazio", sigla: "V", titulo: "Campo vazio")]
    let baseline = ConsultationContent(notes: ["s": " Texto original\n", "o": "Não alterar", "hda": "História personalizada", "vazio": ""],
                                       sections: sections, complaint: "Queixa original", codes: ["Z01.0"])
    let result = try ConsultationAssistantMerge.applying(reviewed: ["s": "Texto revisado", "o": "Não escolhido", "p": "Plano revisado"],
                                                         selected: ["s", "p"], baseline: baseline, current: baseline)
    #expect(result.notes["s"] == " Texto original\n\n\nTexto revisado")
    #expect(result.notes["p"] == "Plano revisado")
    #expect(result.notes["o"] == baseline.notes["o"])
    #expect(result.notes["hda"] == baseline.notes["hda"])
    #expect(result.notes["vazio"] == "")
    #expect(result.sections == sections)
    #expect(result.complaint == baseline.complaint)
    #expect(result.codes == ["Z01.0"])
    #expect(Array(result.displayedSections.prefix(3)).map(\.id) == sections.map(\.id))
}

@Test func assistantRejectsStaleComplaintCodesTextAndSectionOrder() throws {
    let baseline = ConsultationContent(notes: ["s": "Original"], sections: [.init(id: "s", sigla: "S", titulo: "Relato"), .init(id: "p", sigla: "P", titulo: "Plano")], complaint: "Queixa", codes: ["Z00.0"])
    var cases: [ConsultationContent] = []
    var changed = baseline; changed.complaint += " alterada"; cases.append(changed)
    changed = baseline; changed.codes.append("Z01.0"); cases.append(changed)
    changed = baseline; changed.notes["s"] = "Edição posterior"; cases.append(changed)
    changed = baseline; changed.sections?.reverse(); cases.append(changed)
    for current in cases {
        #expect(throws: ConsultationAssistantFailure.staleDraft) {
            try ConsultationAssistantMerge.applying(reviewed: ["s": "Sugestão"], selected: ["s"], baseline: baseline, current: current)
        }
    }
}

@Test func assistantRequiresExplicitSelectionAndRespectsSectionLimit() throws {
    let empty = ConsultationContent()
    #expect(throws: ConsultationAssistantFailure.nothingSelected) {
        try ConsultationAssistantMerge.applying(reviewed: ["s": "Texto"], selected: [], baseline: empty, current: empty)
    }
    #expect(throws: ConsultationAssistantFailure.nothingSelected) {
        try ConsultationAssistantMerge.applying(reviewed: ["s": " \n"], selected: ["s"], baseline: empty, current: empty)
    }
    #expect(throws: ConsultationAssistantFailure.nothingSelected) {
        try ConsultationAssistantMerge.applying(reviewed: ["custom": "Texto"], selected: ["custom"], baseline: empty, current: empty)
    }
    let full = ConsultationContent(sections: (0..<10).map { NoteSection(id: "campo\($0)", sigla: "C", titulo: "Campo \($0)") })
    #expect(throws: ConsultationAssistantFailure.tooManySections) {
        try ConsultationAssistantMerge.applying(reviewed: ["s": "Texto"], selected: ["s"], baseline: full, current: full)
    }
    let unchanged = ConsultationContent(notes: ["s": "Original\n\nJá revisado"])
    #expect(try ConsultationAssistantMerge.applying(reviewed: ["s": "Já revisado"], selected: ["s"], baseline: unchanged, current: unchanged) == unchanged)
}

@Test @MainActor func assistantConsentAndRolePreventNetworkAndSnapshotCopyIsExplicit() async throws {
    let transport = assistantFixtureTransport(), api = try await assistantAPI(transport)
    let baseline = ConsultationContent(notes: ["s": "Nota fictícia", "custom": "Personalizada"], complaint: "Queixa fictícia", codes: ["Z00.0"])
    let assistant = await assistantFixtureModel(api, baseline: baseline)
    #expect(assistant.text.isEmpty)
    assistant.useCurrentNotes()
    #expect(assistant.text.contains("Queixa fictícia"))
    #expect(assistant.text.contains("Nota fictícia"))
    #expect(assistant.text.contains("Personalizada"))
    #expect(!assistant.text.contains("Z00.0"))
    await assistant.generate(canWrite: true)
    #expect(assistant.failure as? ConsultationAssistantFailure == .consentRequired)
    assistant.agreedToProcessing = true
    await assistant.generate(canWrite: false)
    #expect(assistant.failure as? ConsultationAssistantFailure == .permissionDenied)
    #expect(await transport.all().isEmpty)
    assistant.text = String(repeating: "a", count: ConsultationAssistant.maximumInputCharacters + 1)
    await assistant.generate(canWrite: true)
    #expect(assistant.failure as? ConsultationAssistantFailure == .invalidText)
    #expect(await transport.all().isEmpty)
}

@Test @MainActor func assistantSendsOnlyReviewedVisibleInputAndAppliesLocallyWithoutDiagnosesOrPersistence() async throws {
    let transport = assistantFixtureTransport(), api = try await assistantAPI(transport)
    let baseline = ConsultationContent(notes: ["s": "Original", "custom": "Manter contexto"], complaint: "Queixa", codes: ["Z01.0"])
    let workflow = await assistantFixtureWorkflow(api, baseline: baseline)
    let assistant = await assistantFixtureModel(api, baseline: baseline)
    assistant.text = "Texto fictício escolhido manualmente"; assistant.agreedToProcessing = true
    await assistant.generate(canWrite: true)
    #expect(assistant.phase == .reviewing)
    #expect(assistant.selectedSections.isEmpty)
    #expect(assistant.suggestion?.citacoes.count == 1)
    #expect(workflow.content == baseline)
    let post = try #require(await transport.all().first { $0.httpMethod == "POST" })
    let bytes = try #require(post.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: String])
    #expect(post.url?.path == "/v1/sugestoes/soap")
    #expect(body == ["transcricao": "Texto fictício escolhido manualmente"])
    assistant.reviewedNotes["s"] = "Revisado pelo profissional"
    assistant.selectedSections = ["s"]
    try await assistant.apply(to: workflow, patientID: "patient-fiction", canWrite: true)
    #expect(workflow.content.notes["s"] == "Original\n\nRevisado pelo profissional")
    #expect(workflow.content.notes["custom"] == "Manter contexto")
    #expect(workflow.content.codes == ["Z01.0"])
    #expect(workflow.content.complaint == "Queixa")
    #expect(workflow.hasUnsavedChanges)
    #expect(assistant.phase == .applied)
    #expect(await transport.all().filter { $0.httpMethod != "GET" }.count == 1)
    await #expect(throws: ConsultationAssistantFailure.alreadyApplied) {
        try await assistant.apply(to: workflow, patientID: "patient-fiction", canWrite: true)
    }
}

@Test @MainActor func assistantApplyRejectsChangedPatientDraftAndRoleWithoutChangingAnything() async throws {
    let transport = assistantFixtureTransport(), api = try await assistantAPI(transport)
    let baseline = ConsultationContent(notes: ["s": "Preservar"])
    let workflow = await assistantFixtureWorkflow(api, baseline: baseline)
    let assistant = await assistantFixtureModel(api, baseline: baseline)
    assistant.text = "Texto fictício"; assistant.agreedToProcessing = true
    await assistant.generate(canWrite: true); assistant.selectedSections = ["s"]
    await #expect(throws: ConsultationAssistantFailure.staleDraft) {
        try await assistant.apply(to: workflow, patientID: "other-fiction", canWrite: true)
    }
    #expect(workflow.content == baseline)
    await #expect(throws: ConsultationAssistantFailure.permissionDenied) {
        try await assistant.apply(to: workflow, patientID: "patient-fiction", canWrite: false)
    }
    #expect(workflow.content == baseline)
    workflow.content.notes["s"] = "Edição feita após capturar"
    let updated = workflow.content
    await #expect(throws: ConsultationAssistantFailure.staleDraft) {
        try await assistant.apply(to: workflow, patientID: "patient-fiction", canWrite: true)
    }
    #expect(workflow.content == updated)
    #expect(assistant.phase == .reviewing)
}

@Test @MainActor func assistantEditedInputOrRevokedConsentInvalidatesSuggestion() async throws {
    let transport = assistantFixtureTransport(), api = try await assistantAPI(transport)
    let assistant = await assistantFixtureModel(api)
    assistant.text = "Texto fictício"; assistant.agreedToProcessing = true
    await assistant.generate(canWrite: true); assistant.selectedSections = ["s"]
    assistant.text = "Outro texto para revisão"
    #expect(assistant.suggestion == nil && assistant.reviewedNotes.isEmpty && assistant.selectedSections.isEmpty)
    #expect(assistant.phase == .editing)
    await assistant.generate(canWrite: true); assistant.selectedSections = ["p"]
    assistant.agreedToProcessing = false
    #expect(assistant.suggestion == nil && assistant.reviewedNotes.isEmpty && assistant.selectedSections.isEmpty)
    #expect(!assistant.canGenerate)
    #expect(assistant.text == "Outro texto para revisão")
}

@Test @MainActor func assistantRejectsUnsafeResponseShapesWithoutChangingDraftOrRetrying() async throws {
    for body in [assistantFixture.replacingOccurrences(of: "\"rascunho\":true", with: "\"rascunho\":false"),
                 assistantFixture.replacingOccurrences(of: "Sugestão fictícia que exige revisão profissional.", with: " "),
                 assistantFixture.replacingOccurrences(of: "\"s\":", with: "\"hidden\":"),
                 #"{"soap":{},"cid10Candidatos":[],"citacoes":[],"disclaimer":"Revisar","rascunho":true}"#] {
        let transport = StubTransport { _ in (body, 200) }
        let assistant = await assistantFixtureModel(try await assistantAPI(transport), baseline: .init(notes: ["s": "Original"]))
        assistant.text = "Texto que permanece"; assistant.agreedToProcessing = true
        await assistant.generate(canWrite: true)
        #expect(assistant.failure as? ConsultationAssistantFailure == .invalidSuggestion)
        #expect(assistant.phase == .editing && assistant.suggestion == nil)
        #expect(assistant.text == "Texto que permanece")
        #expect(assistant.baseline.notes["s"] == "Original")
        #expect(await transport.all().count == 1)
    }
}

@Test @MainActor func assistantNetworkFailurePreservesTextAndRequiresExplicitNewRequest() async throws {
    let transport = StubTransport { _ in throw URLError(.timedOut) }
    let assistant = await assistantFixtureModel(try await assistantAPI(transport))
    assistant.text = "Não perder texto"; assistant.agreedToProcessing = true
    await assistant.generate(canWrite: true)
    #expect(assistant.phase == .editing && assistant.suggestion == nil && assistant.failure != nil)
    #expect(assistant.text == "Não perder texto")
    #expect(await transport.all().count == 1)
}

@Test @MainActor func assistantCancellationDoesNotAcceptLateResultOrOverwriteNextInput() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { _ in await gate.suspend(); return (assistantFixture, 200) }
    let assistant = await assistantFixtureModel(try await assistantAPI(transport))
    assistant.text = "Texto inicial"; assistant.agreedToProcessing = true
    let pending = Task { await assistant.generate(canWrite: true) }
    try await gate.waitForRequest()
    assistant.cancelGeneration()
    assistant.text = "Texto editado após parar"
    await gate.resume(); await pending.value
    #expect(assistant.phase == .editing && assistant.suggestion == nil)
    #expect(assistant.text == "Texto editado após parar")
    #expect(await transport.all().count == 1)
}

@Test @MainActor func assistantLogoutDiscardsLateResponseAndClearsCapturedPatientContent() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { _ in await gate.suspend(); return (assistantFixture, 200) }
    let api = try await assistantAPI(transport)
    let assistant = await assistantFixtureModel(api, baseline: .init(notes: ["s": "Snapshot sintético"]))
    assistant.text = "Texto sintético"; assistant.agreedToProcessing = true
    let pending = Task { await assistant.generate(canWrite: true) }
    try await gate.waitForRequest(); try await api.logout()
    await gate.resume(); await pending.value
    #expect(assistant.phase == .expired && assistant.suggestion == nil)
    #expect(assistant.text.isEmpty && assistant.baseline == ConsultationContent())
    #expect(!assistant.agreedToProcessing)
}

@Test @MainActor func assistantContextChangeBeforeApplyPreservesWorkflowAndClearsAssistant() async throws {
    let transport = assistantFixtureTransport(), api = try await assistantAPI(transport)
    let baseline = ConsultationContent(notes: ["s": "Original"])
    let workflow = await assistantFixtureWorkflow(api, baseline: baseline)
    let assistant = await assistantFixtureModel(api, baseline: baseline)
    assistant.text = "Texto sintético"; assistant.agreedToProcessing = true
    await assistant.generate(canWrite: true); assistant.selectedSections = ["s"]
    try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        try await assistant.apply(to: workflow, patientID: "patient-fiction", canWrite: true)
    }
    #expect(workflow.content == baseline)
    #expect(assistant.phase == .expired && assistant.text.isEmpty && assistant.baseline == ConsultationContent())
}

@Test @MainActor func assistantRenewsRejectedCredentialsWithoutReplayingSOAPAndWaitsForManualSend() async throws {
    let profile = #"{"id":"author-fiction","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["medico"]}"#
    let transport = StubTransport { request in
        let old = request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access"
        switch request.url?.path {
        case "/v1/sugestoes/soap": return old ? ("{}", 401) : (assistantFixture, 200)
        case "/v1/me": return old ? ("{}", 401) : (profile, 200)
        case "/v1/auth/refresh": return (#"{"accessToken":"synthetic-renewed","refreshToken":"synthetic-refresh-renewed","expiraEm":900}"#, 200)
        default: Issue.record("Unexpected route"); return ("{}", 500)
        }
    }
    let api = try await assistantAPI(transport)
    let context = await api.requestContextID()
    let assistant = await assistantFixtureModel(api)
    assistant.text = "Texto sintético preservado"; assistant.agreedToProcessing = true
    await assistant.generate(canWrite: true)
    #expect(assistant.phase == .editing && assistant.suggestion == nil)
    #expect(assistant.failure as? ConsultationAssistantFailure == .sessionChecked)
    #expect(assistant.text == "Texto sintético preservado")
    #expect(await transport.count("/v1/sugestoes/soap") == 1)
    #expect(await transport.count("/v1/auth/refresh") == 1)
    #expect(await api.requestContextID() == context)
    // A second user action is required; it uses the renewed credentials.
    await assistant.generate(canWrite: true)
    #expect(assistant.phase == .reviewing)
    #expect(await transport.count("/v1/sugestoes/soap") == 2)
    #expect(await transport.count("/v1/auth/refresh") == 1)
}

@Test @MainActor func assistantContextChangeDuringCredentialRecoveryClearsTextWithoutReplay() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { request in
        if request.url?.path == "/v1/sugestoes/soap" { return ("{}", 401) }
        #expect(request.url?.path == "/v1/me")
        await gate.suspend()
        return (#"{"id":"author-fiction","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["medico"]}"#, 200)
    }
    let api = try await assistantAPI(transport)
    let assistant = await assistantFixtureModel(api, baseline: .init(notes: ["s": "Snapshot sintético"]))
    assistant.text = "Texto sintético"; assistant.agreedToProcessing = true
    let pending = Task { await assistant.generate(canWrite: true) }
    try await gate.waitForRequest(); try await api.logout()
    await gate.resume(); await pending.value
    #expect(assistant.phase == .expired && assistant.suggestion == nil)
    #expect(assistant.text.isEmpty && assistant.baseline == ConsultationContent())
    #expect(await transport.count("/v1/sugestoes/soap") == 1)
}
