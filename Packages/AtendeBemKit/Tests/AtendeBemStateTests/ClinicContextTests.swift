import AtendeBemCore
import Foundation
import Testing
@testable import AtendeBemUI

private final class ContextMemoryStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredSession?
    init(_ value: StoredSession) { self.value = value }
    func load() throws -> StoredSession? { lock.withLock { value } }
    func save(_ session: StoredSession) throws { lock.withLock { value = session } }
    func clear() throws { lock.withLock { value = nil } }
}

private actor ContextResponseGate {
    private var reached = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        reached = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
    func waitUntilReached() async throws {
        for _ in 0..<200 {
            if reached { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw APIError.invalidResponse
    }
}

private actor ContextTransport: HTTPTransport {
    let memberships: String
    let pausedPath: String?
    let gate: ContextResponseGate?
    private var switchCount = 0
    init(memberships: String = allClinicMemberships, pausedPath: String? = nil, gate: ContextResponseGate? = nil) {
        self.memberships = memberships; self.pausedPath = pausedPath; self.gate = gate
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        if path == "/v1/auth/trocar-clinica" { switchCount += 1 }
        if path == pausedPath { await gate?.pause() }
        let body: String
        switch path {
        case "/v1/me":
            let receptionist = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(try contextToken("clinic-b"))"
            body = receptionist ? #"{"id":"fixture-user","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["recepcao"]}"#
                                : #"{"id":"fixture-user","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["medico","gestor"]}"#
        case "/v1/clinicas-do-usuario": body = memberships
        case "/v1/auth/trocar-clinica": body = try contextPairJSON("clinic-b")
        case "/v1/pacientes/fictional-patient/evolucoes/rascunho": body = #"{"rascunho":null}"#
        default: throw APIError.invalidResponse
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func switches() -> Int { switchCount }
}

private let allClinicMemberships = #"[{"clinicaId":"clinic-a","nome":"Clínica A fictícia","papeis":["medico","gestor"]},{"clinicaId":"clinic-b","nome":"Clínica B fictícia","papeis":["recepcao"]}]"#

private func contextToken(_ clinicID: String) throws -> String {
    let payload = try JSONSerialization.data(withJSONObject: ["clinicaId": clinicID]).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "fixture.\(payload).fixture"
}
private func contextPairJSON(_ clinicID: String) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["accessToken": contextToken(clinicID), "refreshToken": "fixture-refresh", "expiraEm": 900]), as: UTF8.self)
}
private func contextAPI(_ transport: ContextTransport) throws -> APIClient {
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(contextPairJSON("clinic-a").utf8))
    return APIClient(storage: ContextMemoryStorage(StoredSession(tokens: pair)), transport: transport)
}

@Test @MainActor func contextRequiresActiveClinicToBeAmongMemberships() async throws {
    let transport = ContextTransport(memberships: #"[{"clinicaId":"clinic-b","nome":"Clínica B fictícia","papeis":["recepcao"]}]"#)
    let app = AppState(api: try contextAPI(transport))
    await app.start()
    guard case .recoverableError = app.phase else { Issue.record("Expected a recoverable clinic context error"); return }
    #expect(app.user == nil)
    #expect(app.clinics.isEmpty)
    #expect(app.activeClinicID == nil)
    #expect(app.accessUpdatedAt == nil)
}

@Test @MainActor func switchingClinicReloadsRolesAndInvalidatesPreviousViewContext() async throws {
    let app = AppState(api: try contextAPI(ContextTransport()))
    await app.start()
    #expect(app.phase == .ready)
    #expect(app.activeClinicID == "clinic-a")
    #expect(app.user?.canPrescribe == true)
    let oldContext = app.contextID
    let destination = try #require(app.clinics.first { $0.id == "clinic-b" })
    await app.switchClinic(destination)
    #expect(app.phase == .ready)
    #expect(app.contextID != oldContext)
    #expect(app.activeClinicID == "clinic-b")
    #expect(app.user?.papeis == ["recepcao"])
    #expect(app.user?.canPrescribe == false)
    #expect(app.user?.canReadClinicalData == false)
    #expect(app.user?.canConfirmAppointment == true)
    #expect(app.accessUpdatedAt != nil)
}

@Test @MainActor func duplicateClinicSwitchIsIgnoredAndLateSwitchCannotUndoLogout() async throws {
    let gate = ContextResponseGate()
    let transport = ContextTransport(pausedPath: "/v1/auth/trocar-clinica", gate: gate)
    let app = AppState(api: try contextAPI(transport))
    await app.start()
    let destination = try #require(app.clinics.first { $0.id == "clinic-b" })
    let pending = Task { @MainActor in await app.switchClinic(destination) }
    try await gate.waitUntilReached()
    #expect(app.phase == .loading)
    #expect(app.user == nil)
    await app.switchClinic(destination)
    #expect(await transport.switches() == 1)
    await app.signOut()
    await gate.release()
    await pending.value
    #expect(app.phase == .signedOut)
    #expect(app.user == nil)
    #expect(app.activeClinicID == nil)
    #expect(app.clinics.isEmpty)
}

@Test @MainActor func lateInitialContextCannotRestoreAProfileAfterLogout() async throws {
    let gate = ContextResponseGate()
    let app = AppState(api: try contextAPI(ContextTransport(pausedPath: "/v1/me", gate: gate)))
    let pending = Task { @MainActor in await app.start() }
    try await gate.waitUntilReached()
    await app.signOut()
    await gate.release()
    await pending.value
    #expect(app.phase == .signedOut)
    #expect(app.user == nil)
    #expect(app.clinics.isEmpty)
}

private func consultationPatientFixture() throws -> Patient {
    try JSONDecoder().decode(Patient.self, from: Data(#"{"id":"fictional-patient","nome":"Paciente fictício"}"#.utf8))
}

@Test @MainActor func consultationSessionReusesExactWorkflowAndRetainsOnlyWithinContext() async throws {
    let app = AppState(api: try contextAPI(ContextTransport()))
    await app.start()
    let patient = try consultationPatientFixture()
    let first = try #require(await app.consultationSession(patient: patient))
    await first.workflow.load()
    first.workflow.content = ConsultationContent(notes: ["hda": "Texto fictício completo"],
        sections: [.init(id: "hda", sigla: "H", titulo: "História atual")], complaint: "Queixa fictícia", codes: ["Z00.0"])
    let second = try #require(await app.consultationSession(patient: patient))
    #expect(first.id == second.id)
    #expect(first.workflow === second.workflow)
    #expect(second.workflow.content == first.workflow.content)
    #expect(app.consultations.continuations.count == 1)
    let originalContent = first.workflow.content
    await app.loadContext()
    #expect(app.consultations.entries.isEmpty)
    #expect(first.workflow.phase == .expired)
    #expect(!first.workflow.content.hasContent)
    let new = try #require(await app.consultationSession(patient: patient))
    #expect(new.id != first.id)
    #expect(new.workflow.content != originalContent)
}

@Test @MainActor func consultationSessionsInvalidateBeforeClinicNetworkSwitchCompletes() async throws {
    let gate = ContextResponseGate()
    let app = AppState(api: try contextAPI(ContextTransport(pausedPath: "/v1/auth/trocar-clinica", gate: gate)))
    await app.start()
    let session = try #require(await app.consultationSession(patient: consultationPatientFixture()))
    await session.workflow.load()
    session.workflow.content.notes["s"] = "Texto fictício não salvo"
    let destination = try #require(app.clinics.first { $0.id == "clinic-b" })
    let task = Task { await app.switchClinic(destination) }
    try await gate.waitUntilReached()
    #expect(app.consultations.entries.isEmpty)
    #expect(session.workflow.phase == .expired)
    #expect(!session.workflow.content.hasContent)
    await gate.release(); await task.value
    let unavailable = await app.consultationSession(patient: try consultationPatientFixture())
    #expect(unavailable == nil)
}

@Test @MainActor func consultationLogoutAndExplicitDiscardInvalidateHeldReferences() async throws {
    let app = AppState(api: try contextAPI(ContextTransport()))
    await app.start()
    let patient = try consultationPatientFixture()
    let session = try #require(await app.consultationSession(patient: patient))
    await session.workflow.load()
    session.workflow.content.notes["s"] = "Texto fictício"
    #expect(app.consultations.discard(id: session.id))
    #expect(session.workflow.phase == .expired)
    #expect(app.consultations.entries.isEmpty)
    let another = try #require(await app.consultationSession(patient: patient))
    await another.workflow.load()
    another.workflow.content.notes["s"] = "Outro texto fictício"
    await app.signOut()
    #expect(another.workflow.phase == .expired)
    #expect(!another.workflow.content.hasContent)
    #expect(app.consultations.entries.isEmpty)
}

@Test @MainActor func consultationStoreSeparatesEveryIdentityDimension() throws {
    let store = ConsultationSessionStore()
    let api = try contextAPI(ContextTransport())
    let ui = UUID(), generation = UUID()
    let original = ConsultationSessionStore.Key(uiContext: ui, apiContext: generation, clinicID: "clinic-a", authorID: "author-a", patientID: "patient-a")
    let keys = [original,
        .init(uiContext: UUID(), apiContext: generation, clinicID: "clinic-a", authorID: "author-a", patientID: "patient-a"),
        .init(uiContext: ui, apiContext: UUID(), clinicID: "clinic-a", authorID: "author-a", patientID: "patient-a"),
        .init(uiContext: ui, apiContext: generation, clinicID: "clinic-b", authorID: "author-a", patientID: "patient-a"),
        .init(uiContext: ui, apiContext: generation, clinicID: "clinic-a", authorID: "author-b", patientID: "patient-a"),
        .init(uiContext: ui, apiContext: generation, clinicID: "clinic-a", authorID: "author-a", patientID: "patient-b")]
    let entries = keys.map { key in store.session(key: key, patientName: "Pessoa fictícia") {
        ConsultationWorkflow(api: api, context: key.apiContext, patientID: key.patientID, authorID: key.authorID, canWrite: true)
    } }
    #expect(Set(entries.map(\.id)).count == keys.count)
    store.invalidateAll()
    #expect(entries.allSatisfy { $0.workflow.phase == .expired })
    #expect(store.entries.isEmpty)
}

private actor ConsultationAmbiguityTransport: HTTPTransport {
    private let context = ContextTransport()
    private var posted = false
    private var reconciled = false
    private var writeCount = 0
    private let record = #"{"id":"fictional-evolution","pacienteId":"fictional-patient","profissionalId":"fixture-user","data":"2026-10-03T12:00:00-03:00","tipo":"evolucao","soap":{"s":"Texto fictício"},"cid10":[],"assinado":false"#
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let body: String
        if request.httpMethod == "POST", path.hasSuffix("/confirmar") {
            posted = true; writeCount += 1
            throw URLError(.networkConnectionLost)
        } else if path.hasSuffix("/evolucoes"), posted {
            reconciled = true; body = "[\(record)}]"
        } else if path.hasSuffix("/rascunho") {
            body = reconciled ? #"{"rascunho":null}"# : "{\"rascunho\":\(record),\"rascunhoAutomatico\":true,\"rascunhoVersao\":1}}"
        } else { return try await context.send(request) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func writes() -> Int { writeCount }
}

@Test @MainActor func consultationRetainsUncertainAttemptAndReconcilesWithoutAnotherWrite() async throws {
    let transport = ConsultationAmbiguityTransport()
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(contextPairJSON("clinic-a").utf8))
    let app = AppState(api: APIClient(storage: ContextMemoryStorage(StoredSession(tokens: pair)), transport: transport))
    await app.start()
    let patient = try consultationPatientFixture()
    let first = try #require(await app.consultationSession(patient: patient))
    await first.workflow.load(); first.workflow.prepareReview(); await first.workflow.confirmReviewed()
    #expect(first.workflow.phase == .uncertainConfirmation)
    #expect(!app.consultations.discard(id: first.id))
    let resumed = try #require(await app.consultationSession(patient: patient))
    #expect(resumed.workflow === first.workflow)
    await resumed.workflow.load(); resumed.workflow.prepareReview()
    await resumed.workflow.confirmReviewed(); await resumed.workflow.save()
    #expect(await transport.writes() == 1)
    #expect(resumed.workflow.phase == .uncertainConfirmation)
    await resumed.workflow.reconcileConfirmation()
    #expect(resumed.workflow.phase == .confirmed)
    #expect(await transport.writes() == 1)
    #expect(app.consultations.continuations.isEmpty)
}

@Test @MainActor func consultationClearedDraftStillAppearsForContinuation() async throws {
    let transport = ConsultationAmbiguityTransport()
    let pair = try JSONDecoder().decode(TokenPair.self, from: Data(contextPairJSON("clinic-a").utf8))
    let app = AppState(api: APIClient(storage: ContextMemoryStorage(StoredSession(tokens: pair)), transport: transport))
    await app.start()
    let entry = try #require(await app.consultationSession(patient: consultationPatientFixture()))
    await entry.workflow.load()
    entry.workflow.content = ConsultationContent()
    #expect(entry.workflow.hasUnsavedChanges)
    #expect(app.consultations.continuations.map(\.id) == [entry.id])
    #expect(app.consultations.discard(id: entry.id))
    #expect(app.consultations.continuations.isEmpty)
    #expect(await transport.writes() == 0)
}
