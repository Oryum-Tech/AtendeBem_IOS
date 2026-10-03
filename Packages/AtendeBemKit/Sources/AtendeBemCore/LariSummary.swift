import Foundation
import Observation

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public struct LariSummarySource: Decodable, Sendable, Equatable, Hashable {
    public let servico: String
    public let tabela: String
    public let id: String
    public var title: String {
        ["problemas": "Lista de problemas", "evolucoes": "Evolução", "medicacoes_uso": "Medicações em uso",
         "cirurgias": "Cirurgias", "vacinas": "Vacinas", "sinais_vitais": "Sinais vitais"][tabela] ?? "Origem: \(tabela)"
    }
    var isValid: Bool { servico == "prontuario" && tabela.trimmedOrNil != nil && id.trimmedOrNil != nil }
}

public enum LariSummaryCategory: String, Decodable, Sendable, CaseIterable {
    case condicao, medicacao, procedimento, imunizacao, medida, pendencia
    public var title: String {
        switch self {
        case .condicao: "Condições"
        case .medicacao: "Medicações em uso"
        case .procedimento: "Procedimentos"
        case .imunizacao: "Imunizações"
        case .medida: "Medidas"
        case .pendencia: "Pendências"
        }
    }
}

public struct LariSummaryFact: Decodable, Sendable, Identifiable, Equatable {
    public let ref: String
    public let categoria: LariSummaryCategory
    public let rotulo: String
    public let detalhe: String?
    public let data: String?
    public let fonte: LariSummarySource
    public var id: String { ref }
}

public struct LariSummaryExcerpt: Decodable, Sendable, Identifiable, Equatable {
    public let ref: String
    public let secaoId: String
    public let secaoTitulo: String?
    public let texto: String
    public let data: String
    public let profissionalId: String
    public let assinado: Bool
    public let tipo: String
    public let fonte: LariSummarySource
    public var id: String { ref }
}

public struct LariSummaryActivity: Decodable, Sendable {
    public let totalEvolucoes: Int
    public let naoAssinadas: Int
    public let primeiraEm: String?
    public let ultimaEm: String?
}

public struct LariSummarySentence: Decodable, Sendable {
    public let texto: String
    public let refs: [String]
    public let fontes: [LariSummarySource]
}

public struct LariSummaryNarrative: Decodable, Sendable {
    public let frases: [LariSummarySentence]
}

public struct LariSummaryUnavailable: Decodable, Sendable {
    public let motivo: String
    public var message: String {
        switch motivo {
        case "sem-fatos": "Não há fatos estruturados neste extrato para gerar a narrativa. Confira os trechos retornados abaixo; isso não significa ausência de histórico."
        case "modelo-indisponivel": "A assistente não respondeu. Os fatos e trechos retornados do prontuário continuam disponíveis abaixo."
        case "nao-verificada": "A narrativa não passou na conferência do serviço e foi descartada. Confira os fatos e trechos de origem abaixo."
        default: "A narrativa está indisponível por um motivo não reconhecido pelo aplicativo. Confira os dados de origem abaixo."
        }
    }
}

public struct LariSummaryResponse: Decodable, Sendable {
    public let pacienteId: String
    public let geradoEm: String
    public let atividade: LariSummaryActivity
    public let fatos: [LariSummaryFact]
    public let trechos: [LariSummaryExcerpt]
    public let narrativa: LariSummaryNarrative?
    public let narrativaIndisponivel: LariSummaryUnavailable?
    public let disclaimer: String
    public let geradoPorIa: Bool
    public let registroClinico: Bool

    public func validate(patientID: String) throws {
        let refs = fatos.map(\.ref) + trechos.map(\.ref)
        guard !patientID.isEmpty, pacienteId == patientID, geradoPorIa, !registroClinico,
              ClinicClock.parseInstant(geradoEm) != nil, disclaimer.trimmedOrNil != nil,
              atividade.totalEvolucoes >= 0, atividade.naoAssinadas >= 0,
              atividade.naoAssinadas <= atividade.totalEvolucoes,
              Set(refs).count == refs.count, refs.allSatisfy({ $0.trimmedOrNil != nil }),
              fatos.allSatisfy({ $0.fonte.isValid && $0.rotulo.trimmedOrNil != nil }),
              trechos.allSatisfy({ $0.fonte.isValid && $0.secaoId.trimmedOrNil != nil && $0.texto.trimmedOrNil != nil })
        else { throw LariSummaryFailure.invalidResponse }
    }

    /// Match both reference and resolved anchor; a returned citation is not clinical verification.
    public func facts(for sentence: LariSummarySentence) -> [LariSummaryFact]? {
        guard sentence.texto.trimmedOrNil != nil, !sentence.refs.isEmpty,
              Set(sentence.refs).count == sentence.refs.count,
              sentence.fontes.count == sentence.refs.count else { return nil }
        let matched = sentence.refs.compactMap { reference in fatos.first { $0.ref == reference } }
        guard matched.count == sentence.refs.count, matched.map(\.fonte) == sentence.fontes else { return nil }
        return matched
    }

    public var hasMatchedNarrative: Bool {
        guard narrativaIndisponivel == nil, let narrativa, !narrativa.frases.isEmpty else { return false }
        return narrativa.frases.allSatisfy { facts(for: $0) != nil }
    }
    public var narrativeNotice: String? {
        if hasMatchedNarrative { return nil }
        if narrativa == nil, let narrativaIndisponivel { return narrativaIndisponivel.message }
        return "A narrativa foi ocultada porque suas referências não puderam ser conferidas com os fatos retornados. Os fatos e trechos de origem foram preservados."
    }
    public var returnedEvolutionCount: Int { Set(trechos.map(\.fonte.id)).count }
}

public enum LariSummaryPolicy {
    public static func canGenerate(_ user: User) -> Bool { user.containsAnyRole(User.careRoles) }
}

public enum LariSummaryFailure: Error, LocalizedError, Equatable {
    case consentRequired, permissionDenied, invalidResponse, sourceUnavailable, interrupted, sessionChecked
    public var errorDescription: String? {
        switch self {
        case .consentRequired: "Autorize o processamento antes de gerar o resumo."
        case .permissionDenied: "Seu perfil nesta clínica não permite consultar este resumo."
        case .invalidResponse: "Não foi possível conferir o paciente ou a procedência dos dados. O resumo não será exibido."
        case .sourceUnavailable: "Não foi possível consultar o prontuário para preparar o resumo. Isso não significa que o histórico esteja vazio. Abra os registros do paciente diretamente."
        case .interrupted: "A espera foi interrompida. O serviço ainda pode concluir o processamento; nenhuma solicitação será repetida automaticamente."
        case .sessionChecked: "A sessão foi conferida. Autorize novamente e escolha gerar se quiser iniciar outra solicitação."
        }
    }
}

/// One presentation, no persistence or shared cache. Every generation requires a user gesture.
@MainActor @Observable
public final class LariSummarySession {
    public enum Phase: Equatable { case ready, generating, reviewing, sessionRejected, checkingSession, expired }
    public var agreedToProcessing = false {
        didSet {
            if !agreedToProcessing {
                operationID = nil; summary = nil
                if phase == .generating || phase == .reviewing { phase = .ready }
            }
        }
    }
    public private(set) var phase = Phase.ready
    public private(set) var summary: LariSummaryResponse?
    public private(set) var failure: (any Error)?
    public private(set) var hasRequested = false
    private let api: APIClient
    private let context: UUID
    private let patientID: String
    private let userID: String
    private var operationID: UUID?

    public init(api: APIClient, context: UUID, patientID: String, userID: String) {
        self.api = api; self.context = context; self.patientID = patientID; self.userID = userID
    }
    public var canGenerate: Bool { agreedToProcessing && (phase == .ready || phase == .reviewing) }

    public func generate(patientID currentPatientID: String, user: User) async {
        guard phase == .ready || phase == .reviewing else { return }
        guard currentPatientID == patientID, user.id == userID else { invalidate(); return }
        guard LariSummaryPolicy.canGenerate(user) else { invalidate(); failure = LariSummaryFailure.permissionDenied; return }
        guard agreedToProcessing else { failure = LariSummaryFailure.consentRequired; return }
        let operation = UUID()
        operationID = operation; summary = nil; failure = nil; phase = .generating
        do {
            try await requireContext()
            try Task.checkCancellation()
            guard operationID == operation, phase == .generating, agreedToProcessing else { return }
            hasRequested = true
            let result = try await api.lariPatientSummary(patientID: patientID, expectedContext: context)
            try await requireContext()
            try Task.checkCancellation()
            guard operationID == operation, phase == .generating, agreedToProcessing else { return }
            try result.validate(patientID: patientID)
            summary = result; phase = .reviewing; operationID = nil
        } catch {
            if await api.requestContextID() != context || phase == .expired { invalidate(); return }
            guard operationID == operation else { return }
            operationID = nil; agreedToProcessing = false
            phase = error as? APIError == .http(401) ? .sessionRejected : .ready
            failure = error as? APIError == .http(503) ? LariSummaryFailure.sourceUnavailable : error
        }
    }

    /// Separate explicit action. Credential recovery must not repeat the generating GET.
    public func checkSession() async {
        guard phase == .sessionRejected else { return }
        let operation = UUID()
        operationID = operation; phase = .checkingSession; failure = nil
        do {
            try await requireContext()
            try Task.checkCancellation()
            guard operationID == operation, phase == .checkingSession else { return }
            let profile: User = try await api.get(["me"])
            try await requireContext()
            try Task.checkCancellation()
            guard operationID == operation, phase == .checkingSession else { return }
            guard profile.id == userID, LariSummaryPolicy.canGenerate(profile) else {
                invalidate(); failure = LariSummaryFailure.permissionDenied; return
            }
            operationID = nil; agreedToProcessing = false; phase = .ready; failure = LariSummaryFailure.sessionChecked
        } catch {
            if await api.requestContextID() != context || phase == .expired { invalidate(); return }
            guard operationID == operation else { return }
            operationID = nil; phase = .sessionRejected; failure = error
        }
    }

    public func stopWaiting() {
        guard phase == .generating else { return }
        operationID = nil; agreedToProcessing = false; phase = .ready; summary = nil
        failure = LariSummaryFailure.interrupted
    }
    public func invalidate() {
        operationID = nil; phase = .expired; agreedToProcessing = false; summary = nil; failure = APIError.contextChanged
    }
    private func requireContext() async throws {
        let current = await api.requestContextID()
        guard phase != .expired, current == context else { invalidate(); throw APIError.contextChanged }
    }
}
