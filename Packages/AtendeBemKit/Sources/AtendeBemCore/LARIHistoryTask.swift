import Foundation
import Observation

@Observable @MainActor public final class LARIHistoryTask {
    public let command: String
    public let lookup: LARIPatientLookup
    public private(set) var timeline: ClinicalTimeline?
    public private(set) var antecedents: PatientHistory?
    public private(set) var allergies: [Allergy]?
    public private(set) var sourceWarnings: [String] = []
    public private(set) var updatedAt: Date?
    public private(set) var busy = false
    public private(set) var error: String?
    private let scope: LARIPatientTaskContext
    public init(command: String, api: APIClient, context: UUID, user: User, isContextCurrent: @escaping @MainActor () -> Bool = { true }) {
        self.command = command
        let scope = LARIPatientTaskContext(api: api, context: context, user: user, route: .patientHistory, isContextCurrent: isContextCurrent)
        self.scope = scope; lookup = LARIPatientLookup(query: LARICommandFields.patientQuery(from: command, history: true), scope: scope)
    }
    public var isWorking: Bool { busy || lookup.busy }
    public var available: Bool { scope.available && !isWorking }
    public func invalidate() { scope.invalidate(); lookup.invalidate(); clear() }
    private func clear() { timeline = nil; antecedents = nil; allergies = nil; sourceWarnings = []; updatedAt = nil; error = nil }
    public func searchPatients() async { guard available else { return }; await lookup.search() }
    public func selectPatient(_ patient: Patient) async {
        guard available else { return }; clear(); await lookup.select(patient)
        if lookup.patient != nil { await load() }
    }
    public func changePatient() { guard available else { return }; clear(); lookup.clearSelection() }
    public func load(more: Bool = false) async {
        guard available, let patient = lookup.patient else { return }
        let previous = more ? timeline : nil
        let page = (previous?.paginacao.page ?? 0) + 1
        if !more { clear() }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await scope.check()
            do {
                let value: ClinicalTimeline = try await scope.api.get(["pacientes", patient.id, "ficha"], query: [.init(name: "page", value: String(page)), .init(name: "perPage", value: "25")])
                try await scope.check()
                guard value.pacienteId == patient.id, value.paginacao.page == page, value.paginacao.total >= value.eventos.count, Set(value.eventos.map(\.id)).count == value.eventos.count else { throw APIError.invalidResponse }
                timeline = try previous?.appending(value) ?? value
            } catch {
                if lariInvalidatesContent(error) { throw error }
                sourceWarnings.append("Linha do tempo indisponível nesta consulta. Os registros não foram considerados vazios.")
            }
            if !more {
                do {
                    let value: PatientHistory = try await scope.api.get(["pacientes", patient.id, "antecedentes"])
                    try await scope.check()
                    antecedents = value
                } catch {
                    if lariInvalidatesContent(error) { throw error }
                    sourceWarnings.append("Antecedentes indisponíveis nesta consulta.")
                }
                do {
                    let value: [Allergy] = try await scope.api.get(["pacientes", patient.id, "alergias"])
                    try await scope.check(); allergies = value
                } catch {
                    if lariInvalidatesContent(error) { throw error }
                    sourceWarnings.append("Alergias indisponíveis: a ausência de dados não indica ausência de alergia.")
                }
            }
            try await scope.check(); updatedAt = .now
        } catch {
            clear(); lookup.fail(error); self.error = error.localizedDescription
        }
    }
}
