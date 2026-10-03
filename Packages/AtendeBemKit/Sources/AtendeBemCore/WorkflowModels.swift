import Foundation

/// A failed response to a write is not proof that the server rejected it.
public enum WriteOutcome: Equatable, Sendable {
    case ready, sending, succeeded, uncertain

    public var canSubmit: Bool { self == .ready }

    public static func afterFailure(_ error: Error) -> Self {
        if let code = (error as? APIError)?.statusCode,
           [400, 401, 402, 403, 404, 409, 412, 422, 429].contains(code) { return .ready }
        return .uncertain
    }
}

public enum AppointmentAction: String, CaseIterable, Identifiable, Sendable {
    case confirm, checkIn, start, complete, cancel, noShow
    public var id: Self { self }
    public var title: String {
        switch self {
        case .confirm: "Confirmar agendamento"
        case .checkIn: "Registrar chegada"
        case .start: "Iniciar atendimento"
        case .complete: "Concluir atendimento"
        case .cancel: "Cancelar agendamento"
        case .noShow: "Registrar não comparecimento"
        }
    }
    public var resultingStatus: String {
        switch self {
        case .confirm: "confirmed"
        case .checkIn: "waiting"
        case .start: "in-progress"
        case .complete: "completed"
        case .cancel: "cancelled"
        case .noShow: "no-show"
        }
    }
    public func allowed(for appointment: Appointment, user: User) -> Bool {
        guard user.canConfirmAppointment else { return false }
        switch self {
        case .confirm: return ["scheduled", "pending"].contains(appointment.status)
        case .checkIn: return ["scheduled", "pending", "confirmed"].contains(appointment.status)
        case .start: return user.canReadClinicalData && ["confirmed", "waiting"].contains(appointment.status)
        case .complete: return user.canReadClinicalData && appointment.status == "in-progress"
        case .cancel: return ["scheduled", "pending", "confirmed", "waiting", "in-progress"].contains(appointment.status)
        case .noShow: return ["scheduled", "pending", "confirmed", "waiting"].contains(appointment.status)
        }
    }
}

public struct AppointmentInput: Encodable, Sendable {
    public var inicio: String
    public var duracaoMin: Int
    public var pacienteId: String
    public var profissionalId: String
    public var tipo: String
    public var canal: String
    public init(date: Date, duration: Int, patientID: String, professionalID: String, type: String, channel: String) {
        inicio = ISO8601DateFormatter().string(from: date)
        duracaoMin = duration; pacienteId = patientID; profissionalId = professionalID
        tipo = type; canal = channel
    }
}

/// Rescheduling changes only the time and duration, preserving financial and clinical fields.
public struct RescheduleInput: Encodable, Sendable {
    public let inicio: String
    public let duracaoMin: Int
    public init(date: Date, duration: Int) {
        inicio = ISO8601DateFormatter().string(from: date)
        duracaoMin = duration
    }
}

public struct PatientInput: Encodable, Sendable {
    public var nome: String
    public var cpf: String?
    public var nascimento: String?
    public var telefone: String?
    public var email: String?
    public var termoCadastroAceito: Bool?
    public init(name: String, cpf: String? = nil, birth: String? = nil, phone: String? = nil,
                email: String? = nil, nursingTerm: Bool? = nil) {
        nome = name; self.cpf = cpf; nascimento = birth; telefone = phone
        self.email = email; termoCadastroAceito = nursingTerm
    }
}

public struct AllergyInput: Encodable, Sendable {
    public var substancia: String
    public var tipo: String
    public var severidade: String
    public var anafilaxia: Bool
    public var reacao: String?
    public init(substance: String, type: String, severity: String, anaphylaxis: Bool, reaction: String?) {
        substancia = substance; tipo = type; severidade = severity
        anafilaxia = anaphylaxis; reacao = reaction
    }
}

public enum WorkspacePolicy {
    public static func tabs(_ saved: [String], user: User) -> [String] {
        let allowed = ["today"] + (user.canReadAgenda ? ["agenda"] : []) + (user.canReadPatients ? ["patients"] : [])
        var tabs = saved.filter { allowed.contains($0) }.reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }
        if tabs.isEmpty { tabs = ["today"] }
        return Array(tabs.prefix(3)) + ["more"]
    }
}

public struct AppointmentService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func perform(_ action: AppointmentAction, id: String, user: User, expectedAppointment: Appointment? = nil) async throws -> Appointment {
        let context = await api.requestContextID()
        let current: Appointment = try await api.get(["agendamentos", id])
        guard current.id == id else { throw APIError.invalidResponse }
        if let expected = expectedAppointment {
            guard expected.id == current.id, expected.pacienteId == current.pacienteId,
                  expected.profissionalId == current.profissionalId else { throw APIError.invalidResponse }
            guard expected.inicio == current.inicio, expected.duracaoMin == current.duracaoMin,
                  expected.status == current.status else { throw APIError.http(409) }
        }
        guard action.allowed(for: current, user: user) else { throw APIError.http(409) }
        let result: Appointment
        switch action {
        case .confirm: result = try await api.post(["agendamentos", id, "confirmar"], expectedContext: context)
        case .checkIn: result = try await api.post(["agendamentos", id, "checkin"], expectedContext: context)
        case .start: result = try await api.post(["agendamentos", id, "iniciar"], body: [String: String](), expectedContext: context)
        case .complete, .cancel, .noShow:
            result = try await api.patch(["agendamentos", id], body: ["status": action.resultingStatus], expectedContext: context)
        }
        guard result.id == current.id, result.pacienteId == current.pacienteId,
              result.profissionalId == current.profissionalId, result.status == action.resultingStatus else { throw APIError.invalidResponse }
        return result
    }

    public func reschedule(_ appointment: Appointment, date: Date, duration: Int, user: User) async throws -> Appointment {
        guard user.canConfirmAppointment else { throw APIError.http(403) }
        let context = await api.requestContextID()
        let current: Appointment = try await api.get(["agendamentos", appointment.id])
        guard current.id == appointment.id, current.inicio == appointment.inicio, current.status == appointment.status else {
            throw APIError.http(409)
        }
        return try await api.patch(["agendamentos", appointment.id], body: RescheduleInput(date: date, duration: duration), expectedContext: context)
    }
}
