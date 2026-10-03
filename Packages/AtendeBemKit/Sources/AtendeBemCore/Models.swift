import Foundation

public struct TokenPair: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiraEm: TimeInterval
}

public struct StoredSession: Codable, Sendable, Equatable {
    public let tokens: TokenPair
    public let savedAt: Date

    public init(tokens: TokenPair, savedAt: Date = .now) {
        self.tokens = tokens
        self.savedAt = savedAt
    }

    public var needsRefresh: Bool {
        savedAt.addingTimeInterval(tokens.expiraEm - 60) <= .now
    }
}

public enum LoginResult: Sendable {
    case authenticated
    case mfa(ticket: String)
}

public struct User: Decodable, Sendable, Identifiable {
    public let id: String
    public let nome: String
    public let email: String
    public let papeis: [String]
    public let recursos: [String]?
    public let deveTrocarSenha: Bool?
    public let trocaSenhaObrigatoria: Bool?

    public var canReadAgenda: Bool { containsAnyRole(Self.careRoles + ["recepcao", "gestor", "admin"]) }
    public var canReadPatients: Bool { containsAnyRole(Self.careRoles + ["recepcao", "gestor", "admin"]) }
    public var canReadClinicalData: Bool { containsAnyRole(Self.careRoles) }
    public var canConfirmAppointment: Bool { containsAnyRole(Self.careRoles + ["recepcao", "admin"]) }
    public var canCreatePatient: Bool { containsAnyRole(Self.careRoles + ["recepcao", "gestor", "admin"]) }
    public var canEditPatient: Bool { containsAnyRole(Self.careRoles.filter { $0 != "enfermeiro" } + ["recepcao", "gestor", "admin"]) }
    public var canPrescribe: Bool { containsAnyRole(["medico", "dentista"]) }
    public var canIssueDocument: Bool { containsAnyRole(Self.careRoles.filter { $0 != "enfermeiro" }) }
    public var canRecordAllergy: Bool { containsAnyRole(Self.careRoles) }
    public var canRequestExam: Bool { containsAnyRole(Self.careRoles) }
    public var canWriteClinicalDraft: Bool { containsAnyRole(Self.careRoles) }
    public var canSignEvolution: Bool { canIssueDocument }
    public var needsNursingRegistrationTerm: Bool {
        papeis.contains("enfermeiro") && !containsAnyRole(Self.careRoles.filter { $0 != "enfermeiro" } + ["recepcao", "gestor", "admin"])
    }

    public func hasAnyRole(_ roles: [String]) -> Bool {
        papeis.contains("admin") || !Set(papeis).isDisjoint(with: roles)
    }

    /// Action permissions mirror the controller's positive list; platform admin is not a clinical role.
    public func containsAnyRole(_ roles: [String]) -> Bool { !Set(papeis).isDisjoint(with: roles) }

    public var roleSummary: String {
        let labels = papeis.reduce(into: [String]()) { result, role in
            let label = Self.roleLabel(role)
            if !result.contains(label) { result.append(label) }
        }
        return labels.isEmpty ? "Sem perfil atribuído nesta clínica" : labels.joined(separator: " · ")
    }

    public static func roleLabel(_ role: String) -> String {
        ["medico": "Medicina", "enfermeiro": "Enfermagem", "gestor": "Gestão", "admin": "Administração da plataforma",
         "recepcao": "Recepção", "fisioterapeuta": "Fisioterapia", "dentista": "Odontologia", "psicologo": "Psicologia",
         "fonoaudiologo": "Fonoaudiologia", "nutricionista": "Nutrição", "contabilista": "Contabilidade",
         "residente": "Residência", "preceptor": "Preceptoria"][role] ?? role
    }

    public static let careRoles = ["medico", "enfermeiro", "fisioterapeuta", "dentista", "psicologo", "fonoaudiologo", "nutricionista"]
}

public struct Clinic: Decodable, Sendable, Identifiable {
    public let clinicaId: String
    public let nome: String
    public let papeis: [String]
    public var id: String { clinicaId }
    public func renamed(_ name: String) -> Clinic { Clinic(clinicaId: clinicaId, nome: name, papeis: papeis) }
}

public struct PatientPage: Decodable, Sendable {
    public let total: Int
    public let itens: [Patient]
    public let truncado: Bool?
    public let semNascimento: Int?
}

public struct Patient: Decodable, Sendable, Identifiable {
    public let id: String
    public let nome: String
    public let cpfMascarado: String?
    public let nascimento: String?
    public let telefone: String?
    public let email: String?
    public let status: String?
    public let rascunho: Bool?
    public let alergias: [Allergy]?
    public let condicoes: [String]?
    public let sexo: String?
    public let endereco: PatientAddress?
    public let convenio: PatientInsurance?
    public let particular: Bool?
    public let estadoCivil: String?
    public let profissao: String?
    public let telefoneFixo: String?
    public let preferenciaContato: String?
    public let contatoEmergencia: PatientEmergencyContact?
    public let tipoSanguineo: String?
    public let tags: [String]?
    public let observacao: String?
}

public struct Allergy: Decodable, Sendable {
    public let id: String?
    public let substancia: String
    public let tipo: String?
    public let severidade: String
    public let anafilaxia: Bool?
    public let reacao: String?
    public let fonte: String?
    public let registradoPor: String?
    public let criadoEm: String?
}

public struct AppointmentPage: Decodable, Sendable {
    public let itens: [Appointment]
}

public struct Appointment: Decodable, Sendable, Identifiable {
    public let id: String
    public let inicio: String
    public let duracaoMin: Int
    public let pacienteId: String
    public let profissionalId: String
    public let tipo: String
    public let canal: String
    public let status: String
    public let chegadaEm: String?
    public let confirmacaoPedidaEm: String?
    public let confirmadoEm: String?
    public let confirmadoVia: String?
    public let liberacaoExcepcional: Bool?
    public let motivo: String?

    public var startDate: Date? { ClinicClock.parseInstant(inicio) }
    public var statusLabel: String {
        ["scheduled": "Agendado", "pending": "Pendente", "confirmed": "Confirmado", "waiting": "Aguardando",
         "in-progress": "Em atendimento", "completed": "Concluído", "cancelled": "Cancelado",
         "no-show": "Não compareceu"][status] ?? status
    }
}

/// The existing agenda service defines its calendar day in UTC−03:00.
public enum ClinicClock {
    public static let timeZone = TimeZone(secondsFromGMT: -3 * 60 * 60)!

    public static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func parseInstant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    public static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
