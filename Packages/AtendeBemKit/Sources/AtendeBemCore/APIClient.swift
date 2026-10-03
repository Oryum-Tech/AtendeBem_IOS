import Foundation

public actor APIClient {
    private struct NoBody: Encodable {}
    public static let productionURL = URL(string: "https://api.atendebem.io/v1")!
    private let baseURL: URL
    private let storage: any SessionStorage
    private let transport: any HTTPTransport
    private var session: StoredSession?
    private var generation = UUID()
    private var refreshTask: (id: UUID, task: Task<TokenPair, Error>)?
    private var switchingClinic = false

    public init(baseURL: URL = APIClient.productionURL,
                storage: any SessionStorage = KeychainSessionStorage(),
                transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.storage = storage
        self.transport = transport
    }

    public func restoreSession() throws -> Bool {
        session = try storage.load()
        return session != nil
    }

    public func hasSession() -> Bool { session != nil }

    /// Identifies a session/clinic boundary across a sequence of related reads.
    public func requestContextID() -> UUID { generation }

    /// Display hint only. Authorization is always enforced by the gateway.
    public func activeClinicID() -> String? {
        guard let token = session?.tokens.accessToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["clinicaId"] as? String
    }

    public func login(email: String, password: String) async throws -> LoginResult {
        try logout()
        let epoch = generation
        let data = try await raw(["auth", "login"], method: "POST", body: ["email": email, "senha": password])
        try requireGeneration(epoch)
        if let pair = try? JSONDecoder().decode(TokenPair.self, from: data) {
            try install(pair)
            return .authenticated
        }
        struct MFA: Decodable { let mfaTicket: String }
        let challenge: MFA = try decode(data)
        guard !challenge.mfaTicket.isEmpty else { throw APIError.invalidResponse }
        return .mfa(ticket: challenge.mfaTicket)
    }

    public func verifyMFA(ticket: String, code: String) async throws {
        let epoch = generation
        let data = try await raw(["auth", "mfa", "verificar"], method: "POST", body: ["mfaTicket": ticket, "codigo": code])
        try requireGeneration(epoch)
        try install(decode(data))
    }

    public func requestPasswordReset(email: String) async throws {
        _ = try await raw(["auth", "senha", "solicitar"], method: "POST", body: ["email": email])
    }

    public func logout() throws {
        generation = UUID()
        refreshTask?.task.cancel()
        refreshTask = nil
        switchingClinic = false
        session = nil
        try storage.clear()
    }

    public func switchClinic(id: String) async throws {
        guard !switchingClinic else { throw APIError.contextChanged }
        let originalGeneration = generation
        let access = try await validAccessToken()
        try requireGeneration(originalGeneration)
        generation = UUID()
        let epoch = generation
        switchingClinic = true
        defer { if generation == epoch { switchingClinic = false } }
        let data = try await raw(["auth", "trocar-clinica"], method: "POST", body: ["clinicaId": id], token: access)
        try requireGeneration(epoch)
        try install(decode(data))
    }

    public func get<T: Decodable & Sendable>(_ path: [String], query: [URLQueryItem] = []) async throws -> T {
        try await request(path, method: "GET", query: query, body: Optional<NoBody>.none)
    }

    public func post<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ path: [String],
        body: Body, expectedContext: UUID? = nil
    ) async throws -> T {
        try await request(path, method: "POST", body: body, expectedContext: expectedContext)
    }

    public func post<T: Decodable & Sendable>(_ path: [String], expectedContext: UUID? = nil) async throws -> T {
        try await request(path, method: "POST", body: Optional<String>.none, expectedContext: expectedContext)
    }

    public func put<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ path: [String],
        body: Body, expectedContext: UUID? = nil
    ) async throws -> T {
        try await request(path, method: "PUT", body: body, expectedContext: expectedContext)
    }

    public func patch<T: Decodable & Sendable, Body: Encodable & Sendable>(_ path: [String], body: Body, expectedContext: UUID? = nil) async throws -> T {
        try await request(path, method: "PATCH", body: body, expectedContext: expectedContext)
    }

    public func delete<T: Decodable & Sendable>(_ path: [String], expectedContext: UUID? = nil) async throws -> T {
        try await request(path, method: "DELETE", body: Optional<NoBody>.none, expectedContext: expectedContext)
    }

    public func communityImage(id: String) async throws -> Data {
        let data = try await authorizedData(["comunidade", "midias", id], method: "GET",
            body: Optional<NoBody>.none, accept: "image/jpeg,image/png,image/webp,image/gif")
        guard !data.isEmpty, data.count <= 8_000_000 else { throw APIError.invalidResponse }
        return data
    }

    public func pdf(_ path: [String]) async throws -> Data {
        let data = try await authorizedData(path, method: "GET", body: Optional<NoBody>.none, accept: "application/pdf")
        guard data.starts(with: Data("%PDF-".utf8)) else { throw APIError.invalidResponse }
        return data
    }

    /// Fixed authenticated route; callers validate the patient/result metadata and file signature.
    public func examResultData(examID: String, resultID: String, expectedContext: UUID) async throws -> Data {
        let data = try await authorizedData(["exames", examID, "resultado", resultID, "arquivo"], method: "GET",
            body: Optional<NoBody>.none, accept: "application/pdf,image/png,image/jpeg,application/dicom",
            expectedContext: expectedContext)
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw APIError.invalidResponse }
        return data
    }

    public func lariReply(conversationID: String, text: String, expectedContext: UUID? = nil) async throws -> LARIReply {
        let data = try await authorizedData(["conversas", conversationID, "mensagens"], method: "POST",
            body: ["texto": text], accept: "text/event-stream", expectedContext: expectedContext)
        return try LARIReply.decodeSSE(data, conversationID: conversationID)
    }

    /// This GET generates content and records a LARI observation. Never replay it after a 401.
    public func lariPatientSummary(patientID: String, expectedContext: UUID) async throws -> LariSummaryResponse {
        let data = try await authorizedData(["pacientes", patientID, "resumo-prontuario"], method: "GET",
            body: Optional<NoBody>.none, expectedContext: expectedContext, replayUnauthorized: false)
        return try decode(data)
    }

    /// Audio processing may take up to 90 seconds upstream. No other request timeout changes.
    /// POST is never replayed after a 401; the user explicitly decides whether to retry.
    public func transcribeAudio(_ request: ConsultationAudioRequest, expectedContext: UUID) async throws -> ConsultationTranscription {
        let data = try await authorizedData(["sugestoes", "transcrever"], method: "POST", body: request,
            expectedContext: expectedContext, replayUnauthorized: false, timeoutInterval: 120)
        let result: ConsultationTranscription = try decode(data)
        try result.validate()
        return result
    }

    public func changePassword(current: String, new: String) async throws -> User {
        try await request(["usuarios", "me", "senha"], method: "PUT", body: ["senhaAtual": current, "novaSenha": new])
    }

    private func request<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ path: [String],
        method: String,
        query: [URLQueryItem] = [],
        body: Body? = nil, expectedContext: UUID? = nil
    ) async throws -> T {
        try decode(await authorizedData(path, method: method, query: query, body: body, expectedContext: expectedContext))
    }

    private func authorizedData<Body: Encodable & Sendable>(
        _ path: [String], method: String, query: [URLQueryItem] = [], body: Body? = nil, accept: String = "application/json", expectedContext: UUID? = nil,
        replayUnauthorized: Bool = true, timeoutInterval: TimeInterval? = nil
    ) async throws -> Data {
        guard !switchingClinic else { throw APIError.contextChanged }
        if let expectedContext { try requireGeneration(expectedContext) }
        let epoch = generation
        let access = try await validAccessToken()
        try requireGeneration(epoch)
        try Task.checkCancellation()
        do {
            let data = try await raw(path, method: method, query: query, body: body, token: access, accept: accept, timeoutInterval: timeoutInterval)
            try requireGeneration(epoch)
            try Task.checkCancellation()
            return data
        } catch APIError.http(401) {
            try requireGeneration(epoch)
            // Writes are not replayed: the person can re-read the server state first.
            guard method == "GET", replayUnauthorized else { throw APIError.http(401) }
            if session?.tokens.accessToken == access { try await refresh() }
            try requireGeneration(epoch)
            guard let renewed = session?.tokens.accessToken else { throw APIError.sessionExpired }
            do {
                let data = try await raw(path, method: method, query: query, body: Optional<NoBody>.none, token: renewed, accept: accept, timeoutInterval: timeoutInterval)
                try requireGeneration(epoch)
                try Task.checkCancellation()
                return data
            } catch APIError.http(401) {
                try requireGeneration(epoch)
                try logout()
                throw APIError.sessionExpired
            }
        }
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else { throw APIError.sessionExpired }
        if current.needsRefresh { try await refresh() }
        guard let access = session?.tokens.accessToken else { throw APIError.sessionExpired }
        return access
    }

    private func refresh() async throws {
        let epoch = generation
        let operation: (id: UUID, task: Task<TokenPair, Error>)
        if let pending = refreshTask { operation = pending }
        else {
            guard let refresh = session?.tokens.refreshToken else { throw APIError.sessionExpired }
            let task = Task<TokenPair, Error> {
                let data = try await self.raw(["auth", "refresh"], method: "POST", body: ["refreshToken": refresh])
                return try self.decode(data)
            }
            operation = (UUID(), task)
            refreshTask = operation
        }
        do {
            let pair = try await operation.task.value
            try requireGeneration(epoch)
            if refreshTask?.id == operation.id {
                try install(pair)
                refreshTask = nil
            }
        } catch {
            try requireGeneration(epoch)
            if refreshTask?.id == operation.id {
                refreshTask = nil
                if error as? APIError == .http(401) {
                    try logout()
                    throw APIError.sessionExpired
                }
            }
            throw error
        }
    }

    private func install(_ pair: TokenPair) throws {
        guard !pair.accessToken.isEmpty, !pair.refreshToken.isEmpty,
              pair.expiraEm > 0, pair.expiraEm.isFinite else { throw APIError.invalidResponse }
        let next = StoredSession(tokens: pair)
        // Clear old in-memory credentials if persisting the rotated token fails.
        do { try storage.save(next) }
        catch { session = nil; throw error }
        session = next
    }

    private func requireGeneration(_ expected: UUID) throws {
        guard generation == expected else { throw APIError.contextChanged }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }

    private func raw<Body: Encodable>(_ path: [String], method: String, query: [URLQueryItem] = [],
                                     body: Body? = nil, token: String? = nil, accept: String = "application/json", timeoutInterval: TimeInterval? = nil) async throws -> Data {
        var request = try Self.makeRequest(baseURL: baseURL, path: path, method: method, query: query, body: body, token: token)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let timeoutInterval { request.timeoutInterval = timeoutInterval }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            if [400, 402, 409, 412, 422].contains(response.statusCode),
               let problem = try? JSONDecoder().decode(ServerProblem.self, from: data),
               let detail = problem.detail, !detail.isEmpty {
                throw APIError.problem(response.statusCode, String(detail.prefix(1_000)))
            }
            throw APIError.http(response.statusCode)
        }
        return data
    }

    private struct ServerProblem: Decodable { let detail: String? }

    static func makeRequest(baseURL: URL, path: [String], method: String,
                            query: [URLQueryItem] = [], token: String? = nil) throws -> URLRequest {
        try makeRequest(baseURL: baseURL, path: path, method: method, query: query, body: Optional<NoBody>.none, token: token)
    }

    static func makeRequest<Body: Encodable>(baseURL: URL, path: [String], method: String,
                                             query: [URLQueryItem] = [], body: Body? = nil, token: String? = nil) throws -> URLRequest {
        guard baseURL.scheme == "https", baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
              !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw APIError.invalidConfiguration
        }
        var url = baseURL
        for segment in path { url.appendPathComponent(segment) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        if !query.isEmpty { components.queryItems = query }
        guard let endpoint = components.url, endpoint.host == baseURL.host else { throw APIError.invalidConfiguration }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
