import AtendeBemCore
import Foundation
import Observation

@MainActor @Observable
final class AppState {
    enum Phase: Equatable {
        case loading, signedOut, ready, changePassword, recoverableError(String)
    }

    let api: APIClient
    let aiConsent = AIConsentPreferences()
    let registration = RegistrationClient()
    let consultations = ConsultationSessionStore()
    let lariTasks = LARITaskSessionStore()
    var phase: Phase = .loading
    var user: User?
    var clinics: [Clinic] = []
    var activeClinicID: String?
    var accessUpdatedAt: Date?
    var contextID = UUID() {
        didSet { if oldValue != contextID { consultations.invalidateAll(); lariTasks.invalidateAll() } }
    }
    private var operationID = UUID()

    init(api: APIClient = APIClient()) { self.api = api }

    var clinicName: String { clinics.first { $0.id == activeClinicID }?.nome ?? "Clínica ativa" }

    func consultationSession(patient: Patient) async -> ConsultationSessionStore.Entry? {
        guard phase == .ready, let user, user.canReadClinicalData, let clinicID = activeClinicID else { return nil }
        let uiContext = contextID
        let apiContext = await api.requestContextID()
        guard contextID == uiContext, phase == .ready else { return nil }
        let key = ConsultationSessionStore.Key(uiContext: uiContext, apiContext: apiContext,
            clinicID: clinicID, authorID: user.id, patientID: patient.id)
        return consultations.session(key: key, patientName: patient.nome) {
            ConsultationWorkflow(api: api, context: apiContext, patientID: patient.id, authorID: user.id,
                canWrite: user.canWriteClinicalDraft, isContextValid: { [weak self] in
                    self?.contextID == uiContext && self?.phase == .ready && self?.user?.canReadClinicalData == true
                })
        }
    }

    func start() async {
        do {
            guard try await api.restoreSession() else { phase = .signedOut; return }
            await loadContext()
        } catch { phase = .recoverableError(message(for: error)) }
    }

    func login(email: String, password: String) async throws -> String? {
        let result = try await api.login(email: email, password: password)
        switch result {
        case .mfa(let ticket): return ticket
        case .authenticated: await loadContext(); return nil
        }
    }

    func verifyMFA(ticket: String, code: String) async throws {
        try await api.verifyMFA(ticket: ticket, code: code)
        await loadContext()
    }

    func loadContext() async {
        let operation = UUID()
        operationID = operation
        phase = .loading
        contextID = UUID()
        user = nil
        clinics = []
        activeClinicID = nil
        accessUpdatedAt = nil
        do {
            let requestContext = await api.requestContextID()
            let profile: User = try await api.get(["me"])
            let memberships: [Clinic] = try await api.get(["clinicas-do-usuario"])
            let clinicID = await api.activeClinicID()
            guard operationID == operation else { return }
            guard await api.requestContextID() == requestContext else { throw APIError.contextChanged }
            guard let clinicID, memberships.contains(where: { $0.id == clinicID }) else { throw APIError.invalidResponse }
            user = profile
            clinics = memberships
            activeClinicID = clinicID
            accessUpdatedAt = .now
            phase = profile.deveTrocarSenha == true ? .changePassword : .ready
        } catch {
            guard operationID == operation else { return }
            if await api.hasSession() { phase = .recoverableError(message(for: error)) }
            else { phase = .signedOut }
        }
    }

    func switchClinic(_ clinic: Clinic) async {
        guard phase == .ready, clinic.id != activeClinicID, clinics.contains(where: { $0.id == clinic.id }) else { return }
        let operation = UUID()
        operationID = operation
        contextID = UUID()
        user = nil
        clinics = []
        activeClinicID = nil
        accessUpdatedAt = nil
        phase = .loading
        do {
            try await api.switchClinic(id: clinic.id)
            guard operationID == operation else { return }
            await loadContext()
        } catch {
            guard operationID == operation else { return }
            phase = .recoverableError(message(for: error))
        }
    }

    func signOut() async {
        operationID = UUID()
        contextID = UUID()
        user = nil
        clinics = []
        activeClinicID = nil
        accessUpdatedAt = nil
        do { try await api.logout(); phase = .signedOut }
        catch { phase = .recoverableError(message(for: error)) }
    }

    func checkSession(after error: Error) async {
        let hasSession = await api.hasSession()
        if error as? APIError == .sessionExpired || !hasSession {
            await signOut()
        }
    }
}

func message(for error: Error) -> String {
    if let api = error as? APIError { return api.localizedDescription }
    if let network = error as? URLError {
        switch network.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "Sem conexão. Seus dados serão atualizados quando a conexão voltar."
        case .timedOut: return "A conexão demorou mais que o esperado. Tente novamente."
        default: return "Não foi possível conectar ao AtendeBem. Tente novamente."
        }
    }
    return "Não foi possível concluir. Tente novamente."
}

@MainActor @Observable
final class RemoteResource<Value: Sendable> {
    var value: Value?
    var isLoading = false
    var error: String?
    var updatedAt: Date?
    private var requestID = UUID()

    func clear() {
        requestID = UUID()
        value = nil
        updatedAt = nil
        error = nil
        isLoading = false
    }

    func load(reset: Bool = false, app: AppState,
              fetch: @MainActor () async throws -> Value) async {
        let ticket = UUID()
        let context = app.contextID
        requestID = ticket
        if reset { value = nil; updatedAt = nil }
        isLoading = true
        error = nil
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            guard requestID == ticket, app.contextID == context else { return }
            value = result
            updatedAt = .now
        } catch is CancellationError {
            // A search/date change cancels the previous request without presenting an error.
        } catch {
            guard requestID == ticket, app.contextID == context else { return }
            if Task.isCancelled {
                isLoading = false
                return
            }
            self.error = message(for: error)
            if let api = error as? APIError,
               [.http(401), .http(403), .http(404), .sessionExpired, .contextChanged].contains(api) {
                value = nil
                updatedAt = nil
            }
            await app.checkSession(after: error)
        }
        if requestID == ticket { isLoading = false }
    }
}
