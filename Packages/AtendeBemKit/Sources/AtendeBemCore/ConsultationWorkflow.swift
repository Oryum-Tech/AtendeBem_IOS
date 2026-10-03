import Foundation
import Observation

/// A value snapshot, independent of the editor and the last acknowledged server revision.
public struct ConsultationContent: Equatable, Sendable {
    public var notes: [String: String]
    public var sections: [NoteSection]?
    public var complaint: String
    public var codes: [String]

    public init(notes: [String: String] = [:], sections: [NoteSection]? = nil,
                complaint: String = "", codes: [String] = []) {
        self.notes = notes; self.sections = sections; self.complaint = complaint; self.codes = codes
    }

    public init(_ evolution: Evolution) {
        self.init(notes: evolution.soap.values, sections: evolution.secoes,
                  complaint: evolution.queixaPrincipal ?? "", codes: evolution.cid10)
    }

    private static let standard: [NoteSection] = [
        .init(id: "s", sigla: "S", titulo: "Subjetivo"), .init(id: "o", sigla: "O", titulo: "Objetivo"),
        .init(id: "a", sigla: "A", titulo: "Avaliação"), .init(id: "p", sigla: "P", titulo: "Plano")
    ]

    /// Saved order and empty declared sections survive. Orphan text is never hidden.
    public var displayedSections: [NoteSection] {
        var result = sections?.isEmpty == false ? sections! : Self.standard
        var ids = Set<String>()
        result = result.filter { ids.insert($0.id).inserted }
        for key in notes.keys.sorted() where !ids.contains(key) && notes[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            result.append(Self.standard.first { $0.id == key } ?? NoteSection(id: key, sigla: String(key.prefix(1)).uppercased(), titulo: String(key.prefix(40))))
        }
        return result
    }

    public var hasContent: Bool {
        notes.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || codes.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public func title(for section: NoteSection) -> String {
        let fallback = Self.standard.first { $0.id == section.id }
        let title = section.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviation = section.sigla.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(abbreviation.isEmpty ? (fallback?.sigla ?? String(section.id.prefix(1)).uppercased()) : abbreviation) — \(title.isEmpty ? (fallback?.titulo ?? section.id) : title)"
    }

    /// Canonicalizes only wire-equivalent empty/optional fields; clinical text stays verbatim.
    public var normalized: ConsultationContent {
        .init(notes: notes.filter { !$0.value.isEmpty }, sections: sections?.isEmpty == true ? nil : sections?.map {
            NoteSection(id: $0.id, sigla: $0.sigla.trimmingCharacters(in: .whitespacesAndNewlines), titulo: $0.titulo.trimmingCharacters(in: .whitespacesAndNewlines))
        },
              complaint: complaint.trimmingCharacters(in: .whitespacesAndNewlines),
              codes: codes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
    }

    public func preparedForSaving() throws -> ConsultationContent {
        var content = normalized
        guard content.hasContent, content.complaint.utf16.count <= 300 else { throw ConsultationFailure.invalidContent }
        let reserved = Set(["s", "o", "a", "p"])
        if content.sections != nil || content.notes.contains(where: { !reserved.contains($0.key) && !$0.value.isEmpty }) {
            // Preserve even empty declared sections; supply labels for legacy orphan text.
            let original = content.sections ?? []
            guard Set(original.map(\.id)).count == original.count else { throw ConsultationFailure.invalidSections }
            content.sections = content.displayedSections
            guard let sections = content.sections, (1...10).contains(sections.count), sections.allSatisfy({
                $0.id.range(of: "^[a-z][a-z0-9_]{0,23}$", options: .regularExpression) != nil
                    && $0.sigla.utf16.count <= 2 && $0.titulo.utf16.count <= 40
            }) else { throw ConsultationFailure.invalidSections }
        }
        return content
    }

    func input(version: Int) -> DraftInput {
        DraftInput(soap: SOAPNote(values: notes), sections: sections, complaint: complaint.isEmpty ? nil : complaint,
                   codes: codes, version: version)
    }
}

public enum ConsultationFailure: Error, LocalizedError, Sendable {
    case invalidContent, invalidSections, changedOnServer, notConfirmed, permissionDenied
    public var errorDescription: String? {
        switch self {
        case .invalidContent: "Escreva uma anotação, uma queixa ou um CID. A queixa pode ter até 300 caracteres."
        case .invalidSections: "As seções recebidas precisam ser conferidas: use até 10 seções, cada uma com identificador único, título de até 40 caracteres e sigla de até 2. Seu texto foi preservado."
        case .changedOnServer: "O rascunho mudou em outro dispositivo. Compare as versões antes de continuar. Seu texto foi preservado."
        case .notConfirmed: "Não foi possível comprovar a confirmação. Confira a evolução no servidor antes de repetir qualquer registro."
        case .permissionDenied: "Seu perfil nesta clínica não permite registrar evoluções."
        }
    }
}

public struct ConsultationSnapshot: Sendable {
    public let evolution: Evolution
    public var content: ConsultationContent { ConsultationContent(evolution).normalized }
    public var version: Int { evolution.rascunhoVersao ?? 0 }
    func matches(_ other: ConsultationSnapshot) -> Bool {
        evolution.id == other.evolution.id && version == other.version && content == other.content
    }
}

public struct ConsultationComparison: Sendable {
    public let server: ConsultationSnapshot?
}

/// No background writes, persisted local PHI, signature, or appointment completion.
/// POST confirmation has no atomic CAS in the current service; preflight reduces, not eliminates, races.
@MainActor @Observable
public final class ConsultationWorkflow {
    public enum Phase: Equatable, Sendable {
        case ready, loading, saving, confirming, uncertainSave, uncertainConfirmation, confirmed, expired
    }
    public var content = ConsultationContent() {
        didSet { if oldValue != content { review = nil } }
    }
    public private(set) var phase = Phase.ready
    public private(set) var loaded = false
    public private(set) var saved: ConsultationSnapshot?
    public private(set) var review: ConsultationSnapshot?
    public private(set) var comparison: ConsultationComparison?
    public private(set) var confirmed: Evolution?
    public private(set) var failure: (any Error)?
    public private(set) var notice: String?
    private let api: APIClient
    private let context: UUID
    private let patientID: String
    private let authorID: String
    private let canWrite: Bool
    private let isContextValid: @MainActor () -> Bool
    private var confirmationAttempt: ConsultationSnapshot?

    public init(api: APIClient, context: UUID, patientID: String, authorID: String, canWrite: Bool,
                isContextValid: @escaping @MainActor () -> Bool = { true }) {
        self.api = api; self.context = context; self.patientID = patientID; self.authorID = authorID; self.canWrite = canWrite
        self.isContextValid = isContextValid
    }

    public var isBusy: Bool { [.loading, .saving, .confirming].contains(phase) }
    public var hasUnsavedChanges: Bool { loaded && content.normalized != (saved?.content ?? ConsultationContent()) }
    public var canEdit: Bool { loaded && canWrite && [.ready, .uncertainSave].contains(phase) }
    public var canSave: Bool { loaded && canWrite && phase == .ready && comparison == nil && content.hasContent }
    public var canReview: Bool { canSave && !hasUnsavedChanges && saved != nil }
    public var shouldProtectExit: Bool { isBusy || hasUnsavedChanges || phase == .uncertainSave || phase == .uncertainConfirmation }
    private var draftPath: [String] { ["pacientes", patientID, "evolucoes", "rascunho"] }

    public func load() async {
        guard !loaded, !isBusy, phase != .expired else { return }
        phase = .loading; failure = nil
        do {
            try await requireContext()
            let current = try await readOpenDraft()
            saved = current; content = current?.content ?? ConsultationContent(); loaded = true; phase = .ready
        } catch { await fail(error, phase: .ready) }
    }

    public func save() async {
        guard canSave else { return }
        phase = .saving; failure = nil; notice = nil; review = nil
        var sent = false
        do {
            try await requireContext()
            guard canWrite else { throw ConsultationFailure.permissionDenied }
            let edited = content
            let payload = try edited.preparedForSaving()
            let base = saved
            let latest = try await readOpenDraft()
            let sameBase = base.map { previous in latest.map { previous.matches($0) } ?? false } ?? (latest == nil)
            guard sameBase else {
                comparison = ConsultationComparison(server: latest)
                throw ConsultationFailure.changedOnServer
            }
            guard content == edited else { throw ConsultationFailure.changedOnServer }
            let expectedID = base?.evolution.id
            sent = true
            let result: Evolution = try await api.put(draftPath, body: payload.input(version: base?.version ?? 0), expectedContext: context)
            try await requireContext()
            let current = try snapshot(result)
            guard current.content == payload, current.version > (base?.version ?? 0),
                  expectedID == nil || current.evolution.id == expectedID else { throw APIError.invalidResponse }
            saved = current
            if content == edited { content = payload }
            comparison = nil; phase = .ready
            notice = hasUnsavedChanges ? "A versão enviada foi salva. Há novas alterações nesta tela que ainda precisam ser salvas." : "Rascunho salvo no servidor."
        } catch {
            let next: Phase = sent && WriteOutcome.afterFailure(error) == .uncertain ? .uncertainSave : .ready
            await fail(error, phase: next)
            if phase != .expired, (error as? APIError)?.statusCode == 409 {
                // Reading never replaces the editor. Choosing either version is explicit.
                await compareWithServer()
            }
        }
    }

    public func prepareReview() {
        guard canReview, let saved else { return }
        review = saved; failure = nil
    }
    public func cancelReview() { review = nil }

    public func confirmReviewed() async {
        guard phase == .ready, canWrite, let reviewed = review, let saved,
              saved.matches(reviewed), content.normalized == reviewed.content else { return }
        phase = .confirming; failure = nil; notice = nil
        var posted = false
        var postReturned = false
        do {
            try await requireContext()
            let latest = try await readOpenDraft()
            guard let latest, reviewed.matches(latest) else {
                comparison = ConsultationComparison(server: latest); review = nil
                throw ConsultationFailure.changedOnServer
            }
            // The UI also freezes editing during preflight. Recheck for programmatic changes/reentrancy.
            guard review?.matches(reviewed) == true, content.normalized == reviewed.content else {
                throw ConsultationFailure.changedOnServer
            }
            try await requireContext()
            confirmationAttempt = reviewed; posted = true
            let result: Evolution = try await api.post(draftPath + ["confirmar"], body: reviewed.content.input(version: reviewed.version), expectedContext: context)
            postReturned = true
            try await requireContext()
            try validateConfirmed(result, against: reviewed)
            try await verifyNoLongerOpen(reviewed.evolution.id)
            confirmed = result; phase = .confirmed; review = nil; comparison = nil
            notice = "Evolução registrada. A assinatura e o agendamento não foram alterados."
        } catch {
            review = nil
            // A rejected verification GET after POST success is not a rejected write.
            let rejected = !postReturned && WriteOutcome.afterFailure(error) == .ready
            if rejected { confirmationAttempt = nil }
            await fail(error, phase: posted && !rejected ? .uncertainConfirmation : .ready)
            if phase != .expired, !postReturned, (error as? APIError)?.statusCode == 409 { await compareWithServer() }
        }
    }

    /// Reconciliation is GET-only. A missing timeline entry is not proof that POST failed.
    public func reconcileConfirmation() async {
        guard phase == .uncertainConfirmation, let attempted = confirmationAttempt else { return }
        phase = .loading; failure = nil
        do {
            try await requireContext()
            let values: [Evolution] = try await api.get(["pacientes", patientID, "evolucoes"], query: [URLQueryItem(name: "perPage", value: "100")])
            try await requireContext()
            guard let value = values.first(where: { $0.id == attempted.evolution.id }) else { throw ConsultationFailure.notConfirmed }
            try validateConfirmed(value, against: attempted)
            try await verifyNoLongerOpen(attempted.evolution.id)
            confirmed = value; phase = .confirmed; comparison = nil
            notice = "A evolução confirmada foi encontrada no servidor. Nenhum novo registro foi enviado."
        } catch { await fail(error, phase: .uncertainConfirmation) }
    }

    public func compareWithServer() async {
        guard loaded, [.ready, .uncertainSave].contains(phase) else { return }
        let previous = phase
        phase = .loading; failure = nil; review = nil
        do {
            try await requireContext()
            let latest = try await readOpenDraft()
            comparison = ConsultationComparison(server: latest)
            phase = previous
            if latest == nil { notice = "Não há rascunho aberto no servidor. Confira a linha do tempo antes de criar outro registro." }
        } catch { await fail(error, phase: previous) }
    }

    /// Invoked only after the comparison and an explicit destructive confirmation in the UI.
    public func useServerVersion() {
        guard !isBusy, let latest = comparison?.server, [.ready, .uncertainSave].contains(phase) else { return }
        saved = latest; content = latest.content; comparison = nil; phase = .ready; failure = nil; notice = "Versão do servidor carregada."
    }

    /// Keeps all local text and adopts the reviewed server version as the next PUT base.
    /// It never sends sobrescreverServidor. Preflight and server version checks are not atomic CAS.
    public func keepLocalVersion() {
        guard !isBusy, let latest = comparison?.server, [.ready, .uncertainSave].contains(phase),
              saved == nil || saved?.evolution.id == latest.evolution.id else { return }
        saved = latest; comparison = nil; phase = .ready; failure = nil
        notice = "Seu texto foi mantido. Salve para atualizar o rascunho que acabou de revisar."
    }
    public var canKeepLocalVersion: Bool {
        guard let latest = comparison?.server else { return false }
        return saved == nil || saved?.evolution.id == latest.evolution.id
    }

    public func invalidate() {
        content = ConsultationContent(); saved = nil; comparison = nil; review = nil; confirmed = nil
        confirmationAttempt = nil; loaded = false; phase = .expired; failure = APIError.contextChanged; notice = nil
    }

    private func readOpenDraft() async throws -> ConsultationSnapshot? {
        let response: ConsultationDraft = try await api.get(draftPath)
        try await requireContext()
        return try response.rascunho.map(snapshot)
    }
    private func snapshot(_ value: Evolution) throws -> ConsultationSnapshot {
        guard value.pacienteId == patientID, value.profissionalId == authorID, !value.id.isEmpty,
              !value.assinado, value.rascunhoAutomatico == true, let version = value.rascunhoVersao, version > 0 else { throw APIError.invalidResponse }
        return ConsultationSnapshot(evolution: value)
    }
    private func validateConfirmed(_ value: Evolution, against reviewed: ConsultationSnapshot) throws {
        guard value.id == reviewed.evolution.id, value.pacienteId == patientID, value.profissionalId == authorID,
              !value.assinado,
              // The service deliberately omits all three draft fields for a closed evolution.
              // A missing Boolean alone is insufficient: reject contradictory metadata too.
              value.rascunhoAutomatico != true, value.rascunhoVersao == nil, value.rascunhoSalvoEm == nil,
              ConsultationContent(value).normalized == reviewed.content else { throw ConsultationFailure.notConfirmed }
    }
    private func verifyNoLongerOpen(_ id: String) async throws {
        let open = try await readOpenDraft()
        guard open?.evolution.id != id else { throw ConsultationFailure.notConfirmed }
    }
    private func requireContext() async throws {
        guard phase != .expired, isContextValid() else { throw APIError.contextChanged }
        let current = await api.requestContextID()
        guard phase != .expired, isContextValid(), current == context else { throw APIError.contextChanged }
    }
    private func fail(_ error: any Error, phase next: Phase) async {
        let current = await api.requestContextID()
        let apiError = error as? APIError
        if phase == .expired || !isContextValid() || current != context || apiError == .contextChanged {
            // Discard patient data immediately across a session/clinic boundary.
            invalidate()
        } else if let apiError, [.http(401), .http(403), .http(404), .sessionExpired].contains(apiError) {
            invalidate(); failure = apiError
        } else { phase = next; failure = error }
    }
}
