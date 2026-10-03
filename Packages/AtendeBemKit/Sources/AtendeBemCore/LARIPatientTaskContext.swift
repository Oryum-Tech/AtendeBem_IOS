import Foundation
import Observation

/// Shared guard for a retained native task. The UI guard also catches a destroyed clinic subtree.
@MainActor final class LARIPatientTaskContext {
    let api: APIClient
    let context: UUID
    let user: User
    let route: LARITaskRoute
    private let isContextCurrent: @MainActor () -> Bool
    private var active = true
    init(api: APIClient, context: UUID, user: User, route: LARITaskRoute, isContextCurrent: @escaping @MainActor () -> Bool) {
        self.api = api; self.context = context; self.user = user; self.route = route; self.isContextCurrent = isContextCurrent
    }
    var available: Bool { active && isContextCurrent() && route.isAllowed(for: user) }
    func check() async throws {
        let current = await api.requestContextID()
        guard available, current == context else { throw APIError.contextChanged }
        try Task.checkCancellation()
    }
    func invalidate() { active = false }
    func readPatient(_ id: String) async throws -> Patient {
        try await check()
        let patient: Patient = try await api.get(["pacientes", id])
        try await check()
        guard patient.id == id, !patient.nome.lariTrimmed.isEmpty else { throw APIError.invalidResponse }
        return patient
    }
}

@Observable @MainActor public final class LARIPatientLookup {
    public var query: String
    public private(set) var results: [Patient] = []
    public private(set) var patient: Patient?
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var searched = false
    public private(set) var hasMore = false
    private let scope: LARIPatientTaskContext
    init(query: String, scope: LARIPatientTaskContext) { self.query = query; self.scope = scope }
    public var available: Bool { scope.available && !busy }
    public func invalidate() { results = []; patient = nil; error = nil; query = ""; searched = false }
    public func clearSelection() { guard available else { return }; patient = nil; results = []; searched = false }
    public func search() async {
        guard available, query.lariTrimmed.count >= 2, query.count <= 200 else { return }
        let text = query.lariTrimmed
        busy = true; error = nil; results = []; searched = false; hasMore = false
        defer { busy = false }
        do {
            try await scope.check()
            let page: PatientPage = try await scope.api.get(["pacientes"], query: [.init(name: "busca", value: text), .init(name: "page", value: "1"), .init(name: "perPage", value: "25")])
            try await scope.check()
            guard page.total >= page.itens.count, Set(page.itens.map(\.id)).count == page.itens.count,
                  page.itens.allSatisfy({ !$0.id.isEmpty && !$0.nome.lariTrimmed.isEmpty }) else { throw APIError.invalidResponse }
            guard text == query.lariTrimmed else { return }
            results = page.itens; searched = true; hasMore = page.truncado == true || page.total > page.itens.count
        } catch { fail(error) }
    }
    public func select(_ candidate: Patient) async {
        guard available else { return }; busy = true; patient = nil; error = nil
        defer { busy = false }
        do { patient = try await scope.readPatient(candidate.id); results = [] }
        catch { fail(error) }
    }
    func update(_ patient: Patient) { self.patient = patient }
    func fail(_ failure: Error) {
        error = failure.localizedDescription
        if lariInvalidatesContent(failure) { patient = nil; results = []; searched = false }
    }
}

func lariInvalidatesContent(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    guard let api = error as? APIError else { return false }
    return [.http(401), .http(403), .http(404), .sessionExpired, .contextChanged, .invalidResponse].contains(api)
}

extension String {
    var lariTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var lariNonempty: String? { lariTrimmed.isEmpty ? nil : lariTrimmed }
}

public enum LARICommandFields {
    public static func capture(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).lariNonempty
    }
    /// A search hint only. The person must choose the exact record, even for one result.
    public static func patientQuery(from text: String, history: Bool = false) -> String {
        // After “para”, preserve the name verbatim: “Paciente” may be part of
        // the supplied name, so it must not be silently discarded as a label.
        let prefix = history
            ? #"\b(?:hist[oó]rico|prontu[aá]rio|antecedentes)\s+(?:do|da|de)\s+(?:paciente\s+)?(.+)$"#
            : #"\bpara\s+(?:(?:o|a)\s+)?(.+)$"#
        guard let tail = capture(prefix, from: text) else { return "" }
        let result = tail.replacingOccurrences(of: #"\s+(?:amanh[aã]|hoje|no\s+dia|dia\s+\d|em\s+\d|[àa]s\s+\d|com\s+(?:o|a|dr|dra)|por\s+\d|dura[cç][aã]o\s*:|indica[cç][aã]o\s*:).*$"#, with: "", options: [.regularExpression, .caseInsensitive]).lariTrimmed
        return result.count <= 200 ? result : ""
    }
}
