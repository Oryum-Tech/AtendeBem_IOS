import Foundation
import Observation

public struct ConsultationAssistantSuggestion: Decodable, Sendable {
    public let soap: SOAPNote
    public let cid10Candidatos: [CIDSuggestion]
    public let citacoes: [LARIReply.Citation]
    public let disclaimer: String
    public let rascunho: Bool

    func validate() throws {
        let keys = Set(ConsultationAssistantMerge.sectionIDs)
        guard rascunho, !disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              soap.values.keys.allSatisfy(keys.contains),
              soap.values.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              soap.values.values.reduce(0, { $0 + $1.utf16.count }) <= 80_000 else {
            throw ConsultationAssistantFailure.invalidSuggestion
        }
    }
}

public enum ConsultationAssistantFailure: Error, LocalizedError, Equatable, Sendable {
    case consentRequired, permissionDenied, invalidText, invalidSuggestion, nothingSelected, staleDraft, tooManySections, alreadyApplied, sessionChecked
    public var errorDescription: String? {
        switch self {
        case .consentRequired: "Autorize o processamento antes de enviar suas anotações à LARI."
        case .permissionDenied: "Seu perfil nesta clínica não permite editar esta consulta."
        case .invalidText: "Revise o texto a enviar. Use entre 1 e 20.000 caracteres; nenhum trecho será cortado automaticamente."
        case .invalidSuggestion: "A resposta não trouxe um rascunho SOAP válido com aviso de revisão. Suas anotações foram preservadas."
        case .nothingSelected: "Selecione ao menos uma seção com texto revisado para acrescentar à consulta."
        case .staleDraft: "A consulta mudou desde a abertura da assistência. Suas alterações foram preservadas. Volte à consulta e abra a assistência novamente para revisar a versão atual."
        case .tooManySections: "Esta aplicação ultrapassaria o limite de 10 seções da nota. Selecione somente campos que já existam ou reorganize a consulta antes de continuar."
        case .alreadyApplied: "Esta sugestão já foi aplicada. Confira as anotações na consulta antes de pedir outra."
        case .sessionChecked: "Sua sessão foi conferida. O texto foi preservado; toque em Gerar sugestão SOAP para tentar novamente."
        }
    }
}

/// Local-only application. No suggestion can replace clinical text or add a diagnosis.
public enum ConsultationAssistantMerge {
    public static let sectionIDs = ["s", "o", "a", "p"]
    public static func applying(reviewed: [String: String], selected: Set<String>, baseline: ConsultationContent,
                                current: ConsultationContent) throws -> ConsultationContent {
        guard current == baseline else { throw ConsultationAssistantFailure.staleDraft }
        guard !selected.isEmpty, selected.isSubset(of: Set(sectionIDs)), selected.allSatisfy({
            reviewed[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) else { throw ConsultationAssistantFailure.nothingSelected }
        guard selected.reduce(0, { $0 + (reviewed[$1]?.utf16.count ?? 0) }) <= 80_000 else {
            throw ConsultationAssistantFailure.invalidSuggestion
        }
        var result = current
        for key in sectionIDs where selected.contains(key) {
            let addition = reviewed[key]!
            let existing = result.notes[key] ?? ""
            // Do not erase formatting in the original note or duplicate an already appended block.
            if existing == addition || existing.hasSuffix("\n\n" + addition) { continue }
            result.notes[key] = existing.isEmpty ? addition : existing + "\n\n" + addition
        }
        guard result.displayedSections.count <= 10 else { throw ConsultationAssistantFailure.tooManySections }
        return result
    }
}

@MainActor @Observable
public final class ConsultationAssistant {
    public enum Phase: Equatable, Sendable { case editing, generating, reviewing, applied, expired }
    public static let maximumInputCharacters = 20_000
    public var text = "" {
        didSet { if oldValue != text { clearSuggestion() } }
    }
    public var agreedToProcessing = false {
        didSet { if !agreedToProcessing { clearSuggestion() } }
    }
    public var reviewedNotes: [String: String] = [:]
    public var selectedSections: Set<String> = []
    public private(set) var phase = Phase.editing
    public private(set) var suggestion: ConsultationAssistantSuggestion?
    public private(set) var failure: (any Error)?
    public private(set) var baseline: ConsultationContent
    private let api: APIClient
    private let context: UUID
    private let patientID: String
    private var operationID: UUID?

    public init(api: APIClient, context: UUID, patientID: String, baseline: ConsultationContent) {
        self.api = api; self.context = context; self.patientID = patientID; self.baseline = baseline
    }

    public var canGenerate: Bool {
        agreedToProcessing && [.editing, .reviewing].contains(phase)
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= Self.maximumInputCharacters
    }
    public var availableSectionIDs: [String] {
        ConsultationAssistantMerge.sectionIDs.filter { suggestion?.soap.values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }
    public func title(for key: String) -> String {
        ["s": "Subjetivo", "o": "Objetivo", "a": "Avaliação", "p": "Plano"][key] ?? key
    }
    public func destinationTitle(for key: String) -> String {
        if let section = baseline.displayedSections.first(where: { $0.id == key }) { return baseline.title(for: section) }
        return "\(key.uppercased()) — \(title(for: key))"
    }
    public func isCurrent(_ content: ConsultationContent) -> Bool { content == baseline }

    /// An explicit copy for the editable input. Nothing is fetched or transmitted by this action.
    public func useCurrentNotes() {
        guard phase != .generating, phase != .expired, phase != .applied else { return }
        var blocks: [String] = []
        if !baseline.complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("Queixa principal:\n" + baseline.complaint)
        }
        for section in baseline.displayedSections {
            guard let value = baseline.notes[section.id], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            blocks.append(baseline.title(for: section) + ":\n" + value)
        }
        text = blocks.joined(separator: "\n\n")
    }

    public func generate(canWrite: Bool) async {
        guard phase != .generating, phase != .expired, phase != .applied else { return }
        guard canWrite else { failure = ConsultationAssistantFailure.permissionDenied; return }
        guard agreedToProcessing else { failure = ConsultationAssistantFailure.consentRequired; return }
        guard canGenerate else { failure = ConsultationAssistantFailure.invalidText; return }
        let operation = UUID()
        operationID = operation
        let input = text
        suggestion = nil; reviewedNotes = [:]; selectedSections = []; failure = nil; phase = .generating
        do {
            try await requireContext()
            try Task.checkCancellation()
            guard operationID == operation, phase == .generating, text == input, agreedToProcessing else { return }
            // Only this visible text is sent. Omitting pacienteId avoids an automatic chart lookup.
            let response: ConsultationAssistantSuggestion = try await api.post(["sugestoes", "soap"],
                body: ["transcricao": input], expectedContext: context)
            try await requireContext()
            try Task.checkCancellation()
            guard operationID == operation, text == input, agreedToProcessing else { return }
            try response.validate()
            suggestion = response; reviewedNotes = response.soap.values; selectedSections = []
            phase = .reviewing; operationID = nil
        } catch {
            if await api.requestContextID() != context || phase == .expired { invalidate(); return }
            guard operationID == operation else { return }
            var reportedError: any Error = error
            if error as? APIError == .http(401) {
                do {
                    try Task.checkCancellation()
                    // GET can renew rejected credentials; the SOAP POST is never replayed here.
                    let _: User = try await api.get(["me"])
                    try await requireContext()
                    try Task.checkCancellation()
                    reportedError = ConsultationAssistantFailure.sessionChecked
                } catch { reportedError = error }
            }
            if await api.requestContextID() != context || phase == .expired { invalidate(); return }
            guard operationID == operation else { return }
            operationID = nil; phase = .editing; failure = reportedError
        }
    }

    public func apply(to workflow: ConsultationWorkflow, patientID currentPatientID: String, canWrite: Bool) async throws {
        guard phase != .applied else { throw ConsultationAssistantFailure.alreadyApplied }
        try await requireContext()
        guard canWrite, workflow.canEdit, workflow.phase == .ready, workflow.comparison == nil else { throw ConsultationAssistantFailure.permissionDenied }
        guard currentPatientID == patientID, workflow.content == baseline else { throw ConsultationAssistantFailure.staleDraft }
        guard agreedToProcessing else { throw ConsultationAssistantFailure.consentRequired }
        guard phase == .reviewing, let suggestion else { throw ConsultationAssistantFailure.invalidSuggestion }
        try suggestion.validate()
        guard selectedSections.isSubset(of: Set(availableSectionIDs)) else { throw ConsultationAssistantFailure.nothingSelected }
        let merged = try ConsultationAssistantMerge.applying(reviewed: reviewedNotes, selected: selectedSections,
                                                           baseline: baseline, current: workflow.content)
        // No suspension between validation and this local assignment. No endpoint persists the result.
        workflow.content = merged
        phase = .applied; selectedSections = []
    }

    public func cancelGeneration() {
        guard phase == .generating else { return }
        operationID = nil; phase = .editing; failure = CancellationError()
    }
    public func invalidate() {
        operationID = nil; baseline = ConsultationContent(); text = ""; agreedToProcessing = false
        suggestion = nil; reviewedNotes = [:]; selectedSections = []; phase = .expired; failure = APIError.contextChanged
    }
    private func clearSuggestion() {
        suggestion = nil; reviewedNotes = [:]; selectedSections = []; operationID = nil
        if phase != .expired && phase != .applied { phase = .editing }
    }
    private func requireContext() async throws {
        guard phase != .expired, await api.requestContextID() == context else {
            invalidate()
            throw APIError.contextChanged
        }
    }
}
