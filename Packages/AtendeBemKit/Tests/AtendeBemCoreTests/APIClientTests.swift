import Foundation
import Testing
@testable import AtendeBemCore

final class MemoryStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredSession?
    init(_ value: StoredSession? = nil) { self.value = value }
    func load() throws -> StoredSession? { lock.withLock { value } }
    func save(_ session: StoredSession) throws { lock.withLock { value = session } }
    func clear() throws { lock.withLock { value = nil } }
}

actor StubTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> (String, Int)
    private var requests: [URLRequest] = []
    private let handler: Handler
    init(_ handler: @escaping Handler) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (body, status) = try await handler(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func count(_ path: String) -> Int { requests.filter { $0.url?.path == path }.count }
    func all() -> [URLRequest] { requests }
}

actor ResponseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrived = false
    func suspend() async {
        arrived = true
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func waitForRequest() async throws {
        for _ in 0..<200 {
            if arrived { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw APIError.invalidResponse
    }
}

private let profileJSON = #"{"id":"user-test","nome":"Pessoa de Teste","email":"test@example.invalid","papeis":["medico"]}"#
private let rotatedJSON = #"{"accessToken":"access-new","refreshToken":"refresh-new","expiraEm":900}"#

private func stored(expired: Bool = false) throws -> StoredSession {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"access-old","refreshToken":"refresh-old","expiraEm":900}"#.utf8))
    return StoredSession(tokens: tokens, savedAt: expired ? .distantPast : .now)
}

@Test func writesFromPreviousContextNeverReachTransport() async throws {
    let transport = StubTransport { _ in ("{}", 200) }
    let api = APIClient(storage: MemoryStorage(try stored()), transport: transport)
    _ = try await api.restoreSession()
    let oldContext = await api.requestContextID()
    try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        let _: EmptyResponse = try await api.post(["agendamentos", "synthetic", "checkin"], expectedContext: oldContext)
    }
    await #expect(throws: APIError.contextChanged) {
        let _: EmptyResponse = try await api.patch(["agendamentos", "synthetic"], body: ["status": "waiting"], expectedContext: oldContext)
    }
    await #expect(throws: APIError.contextChanged) {
        _ = try await api.lariReply(conversationID: "synthetic", text: "Pergunta fictícia", expectedContext: oldContext)
    }
    #expect(await transport.all().isEmpty)
}

@Test func loginSupportsMFAWithoutCreatingSession() async throws {
    let storage = MemoryStorage()
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/auth/login")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        #expect(body == ["email": "test@example.invalid", "senha": "test-password"])
        return (#"{"mfaTicket":"ticket-test","metodos":["totp"]}"#, 200)
    }
    let api = APIClient(storage: storage, transport: transport)
    let result = try await api.login(email: "test@example.invalid", password: "test-password")
    guard case .mfa(let ticket) = result else { Issue.record("Expected MFA challenge"); return }
    #expect(ticket == "ticket-test")
    #expect(try storage.load() == nil)
    #expect(await api.hasSession() == false)
}

@Test func concurrentExpiredRequestsShareOneRefresh() async throws {
    let storage = MemoryStorage(try stored(expired: true))
    let transport = StubTransport { request in
        if request.url?.path == "/v1/auth/refresh" {
            try await Task.sleep(for: .milliseconds(50))
            return (rotatedJSON, 200)
        }
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-new")
        return (profileJSON, 200)
    }
    let api = APIClient(storage: storage, transport: transport)
    #expect(try await api.restoreSession())
    try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<12 { group.addTask { let me: User = try await api.get(["me"]); return me.id } }
        for try await id in group { #expect(id == "user-test") }
    }
    #expect(await transport.count("/v1/auth/refresh") == 1)
    #expect(try storage.load()?.tokens.refreshToken == "refresh-new")
}

@Test func concurrentUnauthorizedReadsRefreshOnlyOnce() async throws {
    let transport = StubTransport { request in
        if request.url?.path == "/v1/auth/refresh" {
            try await Task.sleep(for: .milliseconds(50))
            return (rotatedJSON, 200)
        }
        return request.value(forHTTPHeaderField: "Authorization") == "Bearer access-old" ? ("{}", 401) : (profileJSON, 200)
    }
    let api = APIClient(storage: MemoryStorage(try stored()), transport: transport)
    _ = try await api.restoreSession()
    try await withThrowingTaskGroup(of: User.self) { group in
        for _ in 0..<8 { group.addTask { try await api.get(["me"]) } }
        for try await me in group { #expect(me.id == "user-test") }
    }
    #expect(await transport.count("/v1/auth/refresh") == 1)
}

@Test func transientRefreshFailurePreservesCredentials() async throws {
    let original = try stored(expired: true)
    let storage = MemoryStorage(original)
    let api = APIClient(storage: storage, transport: StubTransport { _ in ("{}", 503) })
    _ = try await api.restoreSession()
    await #expect(throws: APIError.http(503)) { let _: User = try await api.get(["me"]) }
    #expect(await api.hasSession())
    #expect(try storage.load() == original)
}

@Test func rejectedRefreshClearsSession() async throws {
    let storage = MemoryStorage(try stored(expired: true))
    let api = APIClient(storage: storage, transport: StubTransport { _ in ("{}", 401) })
    _ = try await api.restoreSession()
    await #expect(throws: APIError.sessionExpired) { let _: User = try await api.get(["me"]) }
    #expect(await api.hasSession() == false)
    #expect(try storage.load() == nil)
}

@Test func logoutDiscardsLateResponse() async throws {
    let gate = ResponseGate()
    let api = APIClient(storage: MemoryStorage(try stored()), transport: StubTransport { _ in
        await gate.suspend()
        return (profileJSON, 200)
    })
    _ = try await api.restoreSession()
    let pending = Task<User, Error> { try await api.get(["me"]) }
    try await gate.waitForRequest()
    try await api.logout()
    await gate.resume()
    await #expect(throws: APIError.contextChanged) { try await pending.value }
    #expect(await api.hasSession() == false)
}

@Test func clinicSwitchDiscardsPreviousClinicResponse() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { request in
        if request.url?.path == "/v1/auth/trocar-clinica" { return (rotatedJSON, 200) }
        await gate.suspend()
        return (profileJSON, 200)
    }
    let api = APIClient(storage: MemoryStorage(try stored()), transport: transport)
    _ = try await api.restoreSession()
    let pending = Task<User, Error> { try await api.get(["me"]) }
    try await gate.waitForRequest()
    try await api.switchClinic(id: "clinic-b")
    await gate.resume()
    await #expect(throws: APIError.contextChanged) { try await pending.value }
    #expect(await transport.count("/v1/auth/trocar-clinica") == 1)
}

@Test func writesAreNeverAutomaticallyReplayed() async throws {
    let transport = StubTransport { _ in ("{}", 503) }
    let api = APIClient(storage: MemoryStorage(try stored()), transport: transport)
    _ = try await api.restoreSession()
    await #expect(throws: APIError.http(503)) {
        let _: Appointment = try await api.patch(["agendamentos", "appointment-test"], body: ["status": "confirmed"])
    }
    #expect(await transport.count("/v1/agendamentos/appointment-test") == 1)
}

@Test func invalidAndInsecureEndpointsAreRejected() throws {
    #expect(throws: APIError.invalidConfiguration) {
        try APIClient.makeRequest(baseURL: URL(string: "http://example.invalid/v1")!, path: ["me"], method: "GET")
    }
    #expect(throws: APIError.invalidConfiguration) {
        try APIClient.makeRequest(baseURL: APIClient.productionURL, path: ["..", "interno"], method: "GET")
    }
    #expect(throws: APIError.invalidConfiguration) {
        try APIClient.makeRequest(baseURL: APIClient.productionURL, path: ["pacientes", "a/b"], method: "GET")
    }
}

@Test func searchQueryIsEncodedWithoutChangingRoute() throws {
    let search = "Ana & João ? # /"
    let request = try APIClient.makeRequest(baseURL: APIClient.productionURL, path: ["pacientes"], method: "GET",
                                           query: [.init(name: "busca", value: search)])
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
    #expect(components.path == "/v1/pacientes")
    #expect(components.queryItems?.first?.value == search)
    #expect(components.fragment == nil)
}

@Test func unavailableClinicalInformationIsNotDecodedAsEmpty() throws {
    let patient = try JSONDecoder().decode(Patient.self, from: Data(#"{"id":"patient-test","nome":"Paciente de Teste"}"#.utf8))
    #expect(patient.alergias == nil)
    #expect(patient.condicoes == nil)
}

@Test func administrativeRoleCannotConfirmAppointmentsOrReadClinicalData() throws {
    let user = try JSONDecoder().decode(User.self, from: Data(#"{"id":"manager-test","nome":"Gestão","email":"manager@example.invalid","papeis":["gestor"]}"#.utf8))
    #expect(user.canReadAgenda)
    #expect(user.canReadPatients)
    #expect(!user.canConfirmAppointment)
    #expect(!user.canReadClinicalData)
}

@Test func clinicDayUsesServerTimeZoneAcrossMidnight() throws {
    let instant = try #require(ClinicClock.parseInstant("2026-09-30T01:30:00.000Z"))
    #expect(ClinicClock.day(instant) == "2026-09-29")
    #expect(ClinicClock.time(instant) == "22:30")
    #expect(ClinicClock.parseInstant("2026-09-29T22:30:00-03:00") == instant)
}
