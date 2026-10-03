import Foundation

/// Values accepted by the public onboarding contract. Nursing and reception join
/// an existing clinic through its membership flow; they are not founder options.
public enum RegistrationProfession: String, CaseIterable, Sendable, Identifiable {
    case medico, fisioterapeuta, dentista, psicologo, fonoaudiologo, nutricionista, residente

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .medico: "Medicina"
        case .fisioterapeuta: "Fisioterapia"
        case .dentista: "Odontologia"
        case .psicologo: "Psicologia"
        case .fonoaudiologo: "Fonoaudiologia"
        case .nutricionista: "Nutrição"
        case .residente: "Residência"
        }
    }
    public var registrationLabel: String? {
        switch self {
        case .medico: "CRM"
        case .fisioterapeuta: "CREFITO"
        case .dentista: "CRO"
        case .psicologo: "CRP"
        case .fonoaudiologo: "CRFa"
        case .nutricionista: "CRN"
        case .residente: nil
        }
    }
}

/// Encodable only: credentials are used for one request and never persisted by
/// RegistrationClient. Descriptions deliberately omit every entered value.
public struct RegistrationRequest: Encodable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private struct Clinic: Encodable, Sendable { let nome: String }
    private struct Responsible: Encodable, Sendable {
        let nome: String
        let email: String
        let senha: String
        let profissao: String
        let crm: String?
        let crefito: String?
        let cro: String?
        let crp: String?
        let crfa: String?
        let crn: String?
        let especialidade: String?
    }
    private let clinica: Clinic
    private let responsavel: Responsible
    private let planoId: String?
    private let origem = "ios"
    public var planID: String? { planoId }
    public var description: String { "RegistrationRequest(redacted)" }
    public var debugDescription: String { description }

    public init(clinicName: String, responsibleName: String, email: String, password: String,
                profession: RegistrationProfession, professionalRegistration: String = "",
                specialty: String = "", planID: String? = nil) throws {
        let clinic = clinicName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = responsibleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (2...120).contains(clinic.utf16.count) else { throw RegistrationError.invalidField(.clinicName) }
        guard (2...120).contains(name.utf16.count) else { throw RegistrationError.invalidField(.responsibleName) }
        guard address.range(of: #"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$"#,
                            options: [.regularExpression, .caseInsensitive]) != nil,
              !address.hasPrefix("."), !address.contains(".."), !address.contains(".@") else {
            throw RegistrationError.invalidField(.email)
        }
        // Match server rules without trimming or otherwise changing a password.
        guard password.utf16.count >= 8,
              password.range(of: "[A-Za-z]", options: .regularExpression) != nil,
              password.range(of: "[0-9]", options: .regularExpression) != nil else {
            throw RegistrationError.invalidField(.password)
        }
        let registration = professionalRegistration.trimmingCharacters(in: .whitespacesAndNewlines)
        let specialty = specialty.trimmingCharacters(in: .whitespacesAndNewlines)
        if let planID, planID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RegistrationError.invalidField(.plan)
        }
        clinica = Clinic(nome: clinic)
        responsavel = Responsible(nome: name, email: address, senha: password, profissao: profession.rawValue,
            crm: profession == .medico && !registration.isEmpty ? registration : nil,
            crefito: profession == .fisioterapeuta && !registration.isEmpty ? registration : nil,
            cro: profession == .dentista && !registration.isEmpty ? registration : nil,
            crp: profession == .psicologo && !registration.isEmpty ? registration : nil,
            crfa: profession == .fonoaudiologo && !registration.isEmpty ? registration : nil,
            crn: profession == .nutricionista && !registration.isEmpty ? registration : nil,
            especialidade: specialty.isEmpty ? nil : specialty)
        planoId = planID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RegistrationPlan: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let nome: String
    public let trialDias: Int
    public let semCartao: Bool
    public let recursos: [String]

    /// The public catalog owns the duration; never infer fourteen days from a
    /// successful onboarding response, which carries no trial dates.
    public var trialDescription: String {
        if trialDias <= 0 { return "Consulte as condições deste plano." }
        return "\(trialDias) dias para experimentar" + (semCartao ? ", sem cartão." : ".")
    }
}

/// Confirmation of provisioning, not a login or authorization grant. No tokens
/// leave the client. Continue through ordinary login, including MFA if enabled.
public struct RegistrationReceipt: Sendable, Equatable {
    public let clinicID: String
    public let userID: String
    public let subscriptionID: String
    public let planID: String?
}

public enum RegistrationField: String, Sendable {
    case clinicName, responsibleName, email, password, plan
}

public enum RegistrationError: Error, LocalizedError, Sendable, Equatable {
    case invalidField(RegistrationField)
    case rejected(Int)
    case alreadySubmitting
    case alreadyCompleted
    case outcomeUnknown

    public var errorDescription: String? {
        switch self {
        case .invalidField(.clinicName): "Informe o nome da clínica com 2 a 120 caracteres."
        case .invalidField(.responsibleName): "Informe seu nome com 2 a 120 caracteres."
        case .invalidField(.email): "Confira o endereço de e-mail."
        case .invalidField(.password): "Use ao menos 8 caracteres, uma letra e um número na senha."
        case .invalidField(.plan): "Selecione um plano disponível."
        case .rejected(401): "Esse e-mail já pode estar cadastrado. Confira sua senha ou use Entrar."
        case .rejected(429): "Há muitas solicitações. Aguarde antes de tentar novamente."
        case .rejected: "O cadastro não foi aceito. Confira os dados informados."
        case .alreadySubmitting: "O cadastro está sendo enviado. Aguarde a confirmação."
        case .alreadyCompleted: "O cadastro já foi concluído. Use Entrar para acessar sua conta."
        case .outcomeUnknown: "Não foi possível confirmar o resultado do cadastro. Ele pode ter sido concluído. Use Entrar ou a recuperação de senha antes de tentar criar outra clínica."
        }
    }
}

public enum RegistrationSubmissionState: Sendable, Equatable {
    case ready, submitting, completed, outcomeUnknown
}

/// Public, single-submission workflow, isolated from APIClient's authenticated
/// requests. Keep this client alive while the registration form is reachable.
public actor RegistrationClient {
    private let baseURL: URL
    private let transport: any HTTPTransport
    public private(set) var state: RegistrationSubmissionState = .ready

    public init(baseURL: URL = APIClient.productionURL, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func plans() async throws -> [RegistrationPlan] {
        let request = try APIClient.makeRequest(baseURL: baseURL, path: ["planos"], method: "GET")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw APIError.http(response.statusCode) }
        guard let plans = try? JSONDecoder().decode([RegistrationPlan].self, from: data),
              Set(plans.map(\.id)).count == plans.count,
              plans.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.trialDias >= 0 }) else {
            throw APIError.invalidResponse
        }
        return plans
    }

    public func register(_ value: RegistrationRequest) async throws -> RegistrationReceipt {
        switch state {
        case .ready: break
        case .submitting: throw RegistrationError.alreadySubmitting
        case .completed: throw RegistrationError.alreadyCompleted
        case .outcomeUnknown: throw RegistrationError.outcomeUnknown
        }
        let request = try APIClient.makeRequest(baseURL: baseURL, path: ["onboarding"], method: "POST", body: value)
        try Task.checkCancellation()
        state = .submitting
        do {
            // No retry, authentication, token refresh, storage or response logging.
            let (data, response) = try await transport.send(request)
            if [400, 401, 403, 422, 429].contains(response.statusCode) {
                state = .ready
                throw RegistrationError.rejected(response.statusCode)
            }
            guard response.statusCode == 201,
                  let provisioned = try? JSONDecoder().decode(Provisioned.self, from: data),
                  let receipt = provisioned.validatedReceipt(expectedPlan: value.planID) else {
                throw RegistrationError.outcomeUnknown
            }
            state = .completed
            return receipt
        } catch let error as RegistrationError {
            if case .rejected = error { throw error }
            state = .outcomeUnknown
            throw RegistrationError.outcomeUnknown
        } catch {
            // A lost/cancelled response cannot prove rollback across the saga.
            state = .outcomeUnknown
            throw RegistrationError.outcomeUnknown
        }
    }

    private struct Provisioned: Decodable {
        let clinicaId: String
        let usuarioId: String
        let assinaturaId: String
        let planoId: String?
        let accessToken: String
        let refreshToken: String
        let expiraEm: Double

        func validatedReceipt(expectedPlan: String?) -> RegistrationReceipt? {
            guard [clinicaId, usuarioId, assinaturaId].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  expiraEm.isFinite, expiraEm > 0,
                  expectedPlan == nil || expectedPlan == planoId else { return nil }
            let segments = accessToken.split(separator: ".", omittingEmptySubsequences: false)
            guard segments.count == 3, segments.allSatisfy({ !$0.isEmpty }) else { return nil }
            var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            struct Claims: Decodable { let sub: String; let clinicaId: String }
            guard let bytes = Data(base64Encoded: payload),
                  let claims = try? JSONDecoder().decode(Claims.self, from: bytes),
                  claims.sub == usuarioId, claims.clinicaId == clinicaId else { return nil }
            // Structural consistency only, not cryptographic verification. The
            // token is discarded; subsequent login/server authorization is required.
            return RegistrationReceipt(clinicID: clinicaId, userID: usuarioId, subscriptionID: assinaturaId, planID: planoId)
        }
    }
}
