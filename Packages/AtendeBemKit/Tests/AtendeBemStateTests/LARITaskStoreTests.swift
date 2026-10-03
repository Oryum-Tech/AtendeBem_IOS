import AtendeBemCore
import Foundation
import Testing
@testable import AtendeBemUI

@Test @MainActor func lariTaskOwnerRetainsOperationIdentityAcrossChatPresentations() {
    let owner = LARITaskSessionStore(), context = UUID()
    let first = owner.request(command: "Agendar consulta para Paciente Fictício", route: .appointment, context: context)
    // A new chat view reads the same app-owned store instead of allocating a fresh operation.
    let reopened = owner.request(command: " Agendar consulta para Paciente Fictício ", route: .appointment, context: context)
    #expect(first.id == reopened.id); #expect(owner.requests.count == 1)
    let second = owner.request(command: first.command, route: .appointment, context: UUID())
    #expect(second.id != first.id)
}

@Test @MainActor func contextChangeClearsLARITasksEvenWhenChatIsNotVisible() {
    let app = AppState()
    _ = app.lariTasks.request(command: "Preparar receita", route: .prescription, context: app.contextID)
    _ = app.lariTasks.request(command: "Solicitar exames", route: .examRequest, context: app.contextID)
    #expect(app.lariTasks.requests.count == 2)
    app.contextID = UUID()
    #expect(app.lariTasks.requests.isEmpty)
}

@Test @MainActor func newConversationDiscardsAudioWithoutLosingClinicalOperationHistory() {
    let owner = LARITaskSessionStore(), context = UUID()
    let prescription = owner.request(command: "Preparar receita", route: .prescription, context: context)
    _ = owner.request(command: "Transcrever consulta", route: .transcription, context: context)
    owner.discardAudioSessions()
    #expect(owner.requests.map(\.id) == [prescription.id])
}

private final class LARIStoreStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredSession?
    init(_ value: StoredSession) { self.value = value }
    func load() throws -> StoredSession? { lock.withLock { value } }
    func save(_ session: StoredSession) throws { lock.withLock { value = session } }
    func clear() throws { lock.withLock { value = nil } }
}
private let storePatientJSON = #"{"id":"patient-fiction","nome":"Paciente Fictício","nascimento":"1980-01-01"}"#
private actor LARIStoreAmbiguityTransport: HTTPTransport {
    private var count = 0
    private let loseResponse: Bool
    init(loseResponse: Bool = true) { self.loseResponse = loseResponse }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.httpMethod == "POST", request.url!.path.hasSuffix("/exames") {
            count += 1
            if loseResponse { throw URLError(.networkConnectionLost) }
            let requestBody = try #require(request.httpBody)
            var body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String:Any])
            body["id"] = "exam-fiction"; body["medicoId"] = "doctor-fiction"; body["status"] = "solicitado"
            body["criadoEm"] = "2030-01-01T00:00:00Z"; body["origem"] = "solicitada"
            return (try JSONSerialization.data(withJSONObject:body), HTTPURLResponse(url:request.url!, statusCode:201, httpVersion:nil, headerFields:nil)!)
        }
        guard request.httpMethod == "GET", request.url!.path.hasSuffix("/pacientes/patient-fiction") else { throw APIError.invalidResponse }
        return (Data(storePatientJSON.utf8), HTTPURLResponse(url:request.url!, statusCode:200, httpVersion:nil, headerFields:nil)!)
    }
    func writes() -> Int { count }
}

@Test @MainActor func uncertainExamIsRetainedAcrossChatRecreationAndClearedAtClinicBoundary() async throws {
    let transport = LARIStoreAmbiguityTransport()
    let tokens = try JSONDecoder().decode(TokenPair.self, from:Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage:LARIStoreStorage(StoredSession(tokens:tokens)), transport:transport)
    _ = try await api.restoreSession()
    let app = AppState(api:api)
    let user = try JSONDecoder().decode(User.self, from:Data(#"{"id":"doctor-fiction","nome":"Profissional Fictício","email":"doctor@example.invalid","papeis":["medico"]}"#.utf8))
    app.user = user; app.phase = .ready
    let context = app.contextID
    let request = app.lariTasks.request(command:"Solicitar exames de Exame fictício para Paciente Fictício", route:.examRequest, context:context)
    let task = LARIExamRequestTask(command:request.command, api:api, context:await api.requestContextID(), user:user,
        isContextCurrent:{ [weak app] in app?.contextID == context && app?.user?.id == user.id })
    app.lariTasks.examTasks[request.id] = task
    let patient = try JSONDecoder().decode(Patient.self, from:Data(storePatientJSON.utf8))
    await task.selectPatient(patient); task.type = "laboratorial"; task.reviewed = true; await task.create()
    #expect(task.outcome == .uncertain)
    #expect(app.lariTasks.progress(for: request).title == "Conferir resultado")
    #expect(app.lariTasks.progress(for: request).needsAttention)
    #expect(!app.lariTasks.canStartAnother(after:request) && app.lariTasks.startAnother(after:request) == nil)
    // Reconstructing the chat accesses the app-owned request and the same task, not a new POST state machine.
    let reopened = app.lariTasks.request(command:request.command, route:.examRequest, context:context)
    let retained = try #require(app.lariTasks.examTasks[reopened.id])
    #expect(retained === task && retained.outcome == .uncertain && !retained.canCreate)
    #expect(app.lariTasks.progress(for: reopened) == app.lariTasks.progress(for: request))
    await retained.create(); #expect(await transport.writes() == 1)
    app.contextID = UUID()
    #expect(app.lariTasks.examTasks.isEmpty && app.lariTasks.requests.isEmpty)
    #expect(app.lariTasks.progress(for: request).title == "Sessão encerrada")
    #expect(task.lookup.patient == nil && task.items.isEmpty)
    await task.create(); #expect(await transport.writes() == 1)
}


@Test @MainActor func completedLARITaskStartsAnotherOnlyByExplicitGestureWithoutAnotherPOST() async throws {
    let transport = LARIStoreAmbiguityTransport(loseResponse:false)
    let tokens = try JSONDecoder().decode(TokenPair.self, from:Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage:LARIStoreStorage(StoredSession(tokens:tokens)), transport:transport)
    _ = try await api.restoreSession()
    let store = LARITaskSessionStore(), context = UUID()
    let user = try JSONDecoder().decode(User.self, from:Data(#"{"id":"doctor-fiction","nome":"Profissional Fictício","email":"doctor@example.invalid","papeis":["medico"]}"#.utf8))
    let first = store.request(command:"Solicitar exames de Exame fictício para Paciente Fictício", route:.examRequest, context:context)
    let task = LARIExamRequestTask(command:first.command, api:api, context:await api.requestContextID(), user:user)
    store.examTasks[first.id] = task
    let patient = try JSONDecoder().decode(Patient.self, from:Data(storePatientJSON.utf8))
    await task.selectPatient(patient); task.type = "laboratorial"; task.reviewed = true; await task.create()
    #expect(task.outcome == .succeeded && store.canStartAnother(after:first))
    #expect(store.progress(for: first).title == "Conferir assinatura")
    #expect(store.progress(for: first).needsAttention)
    #expect(store.request(command:first.command, route:.examRequest, context:context).id == first.id)
    let second = try #require(store.startAnother(after:first))
    #expect(second.id != first.id && store.requests.count == 2)
    #expect(store.examTasks[second.id] == nil && store.examTasks[first.id] === task)
    #expect(store.progress(for: second).title == "Retomar preparação")
    #expect(store.request(command:first.command, route:.examRequest, context:context).id == second.id)
    #expect(await transport.writes() == 1)
}
