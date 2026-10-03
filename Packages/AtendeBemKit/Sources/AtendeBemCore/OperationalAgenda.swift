import Foundation
import Observation

public enum OperationalAgendaPolicy {
    public static func canFilterTeam(_ user: User) -> Bool { user.containsAnyRole(["recepcao", "gestor", "admin"]) }
    /// Conservative native scope for all care roles; the observed backend enforces this automatically for doctors.
    public static func professionalID(user: User, selected: String?) throws -> String? {
        guard user.canReadAgenda else { throw APIError.http(403) }
        return canFilterTeam(user) ? selected : user.id
    }
}

public struct OperationalQueueSnapshot: Sendable {
    public let queue: WaitingQueue
    public let patientNames: [String: String]
    public let professionals: [TeamMember]
    public let namesUnavailable: Bool
    public let teamUnavailable: Bool
}

public struct OperationalQueueService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }
    private func requireContext(_ context: UUID) async throws {
        guard context == (await api.requestContextID()) else { throw APIError.contextChanged }
        try Task.checkCancellation()
    }
    public func load(day: String, user: User, professionalID: String? = nil, context: UUID) async throws -> OperationalQueueSnapshot {
        try await requireContext(context)
        let scope = try OperationalAgendaPolicy.professionalID(user: user, selected: professionalID)
        var query = [URLQueryItem(name: "dia", value: day)]
        if let scope { query.append(URLQueryItem(name: "profissionalId", value: scope)) }
        let queue: WaitingQueue = try await api.get(["agendamentos", "fila"], query: query)
        try await requireContext(context)
        let items = queue.itens + queue.emAtendimento
        guard queue.dia == day, ClinicClock.parseInstant(queue.geradoEm) != nil,
              queue.totalAguardando == queue.itens.count,
              Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.id.isEmpty && !$0.pacienteId.isEmpty && !$0.profissionalId.isEmpty && $0.esperaMin >= 0
                  && (scope == nil || $0.profissionalId == scope) }) else { throw APIError.invalidResponse }
        // No sorting or local priority calculation: position and sequence belong to the server.
        var names: [String: String] = [:]
        var unavailable = false
        let ids = Array(Set(items.map(\.pacienteId))).sorted()
        for offset in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[offset..<min(offset + 100, ids.count)])
            do {
                let page: PatientPage = try await api.get(["pacientes"], query: [
                    .init(name: "ids", value: batch.joined(separator: ",")), .init(name: "perPage", value: "100"), .init(name: "page", value: "1")])
                try await requireContext(context)
                guard page.itens.allSatisfy({ batch.contains($0.id) }), Set(page.itens.map(\.id)).count == page.itens.count else { throw APIError.invalidResponse }
                page.itens.forEach { names[$0.id] = $0.nome }
                unavailable = unavailable || page.itens.count != batch.count
            } catch let error as APIError where [.sessionExpired, .contextChanged, .http(403), .invalidResponse].contains(error) { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { unavailable = true }
        }
        var team: [TeamMember] = []
        var teamUnavailable = false
        if OperationalAgendaPolicy.canFilterTeam(user) {
            do {
                let members: [TeamMember] = try await api.get(["usuarios"])
                try await requireContext(context)
                guard Set(members.map(\.id)).count == members.count, members.allSatisfy({ !$0.id.isEmpty }) else { throw APIError.invalidResponse }
                team = members.filter { !Set($0.papeis).isDisjoint(with: User.careRoles) }.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
            } catch let error as APIError where [.sessionExpired, .contextChanged, .invalidResponse].contains(error) { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { teamUnavailable = true }
        }
        try await requireContext(context)
        return OperationalQueueSnapshot(queue: queue, patientNames: names, professionals: team, namesUnavailable: unavailable, teamUnavailable: teamUnavailable)
    }
}

public enum AppointmentConfirmationState: Sendable, Equatable {
    case notRequested, awaiting, noConfirmation, patient, team, unknownOrigin, invalidRequestDate
    public var label: String {
        switch self {
        case .notRequested: "Confirmação ainda não solicitada"
        case .awaiting: "Aguardando confirmação do paciente"
        case .noConfirmation: "Sem confirmação registrada após 24 h"
        case .patient: "Confirmado pelo paciente"
        case .team: "Confirmação registrada pela equipe"
        case .unknownOrigin: "Confirmado · origem não informada"
        case .invalidRequestDate: "Pedido com data indisponível"
        }
    }
    public static func resolve(_ appointment: Appointment, now: Date = .now) -> Self? {
        if appointment.status == "confirmed" {
            switch appointment.confirmadoVia {
            case "paciente": return .patient
            case "equipe": return .team
            default: return .unknownOrigin
            }
        }
        guard ["scheduled", "pending"].contains(appointment.status) else { return nil }
        guard let requested = appointment.confirmacaoPedidaEm else { return .notRequested }
        guard let date = ClinicClock.parseInstant(requested) else { return .invalidRequestDate }
        return now.timeIntervalSince(date) >= 24 * 3600 ? .noConfirmation : .awaiting
    }
    public static func canRequest(_ appointment: Appointment, user: User, now: Date = .now) -> Bool {
        guard user.canConfirmAppointment, !appointment.pacienteId.isEmpty,
              ["scheduled", "pending"].contains(appointment.status), let start = appointment.startDate, start > now else { return false }
        if let requested = appointment.confirmacaoPedidaEm {
            guard let date = ClinicClock.parseInstant(requested), now.timeIntervalSince(date) >= 12 * 3600 else { return false }
        }
        return true
    }
}

public enum AppointmentConfirmationError: LocalizedError {
    case changed, notEligible, uncertain
    public var errorDescription: String? {
        switch self {
        case .changed: "O agendamento mudou. Confira novamente o paciente, o horário e a situação antes de pedir confirmação."
        case .notEligible: "Não é possível pedir confirmação agora. O agendamento deve ser futuro, ainda não confirmado e sem outro pedido nas últimas 12 horas."
        case .uncertain: "Não foi possível confirmar o registro do pedido. Consulte a situação antes de agir; o aplicativo não repetirá o envio."
        }
    }
}

/// One deliberate request, scoped to the appointment shown to the person. Never retries a POST.
@MainActor @Observable public final class AppointmentConfirmationWorkflow {
    public private(set) var appointment: Appointment?
    public private(set) var outcome = WriteOutcome.ready
    public private(set) var busy = false
    public private(set) var error: String?
    private let original: Appointment
    private let api: APIClient
    private let user: User
    private let context: UUID
    private var invalidated = false
    private var requestedBeforeAttempt: String?
    private let now: @Sendable () -> Date
    public init(appointment: Appointment, user: User, api: APIClient, context: UUID, now: @escaping @Sendable () -> Date = { .now }) {
        self.appointment = appointment; original = appointment; self.user = user
        self.api = api; self.context = context; self.now = now
    }
    public var canRequest: Bool {
        guard let appointment else { return false }
        return !invalidated && !busy && outcome == .ready && AppointmentConfirmationState.canRequest(appointment, user: user, now: now())
    }
    public func invalidate() { invalidated = true; appointment = nil; error = nil }
    private func requireContext() async throws {
        guard !invalidated, context == (await api.requestContextID()) else { throw APIError.contextChanged }
        guard !invalidated else { throw APIError.contextChanged }
        try Task.checkCancellation()
    }
    private func validate(_ value: Appointment) throws {
        guard value.id == original.id, value.pacienteId == original.pacienteId, value.profissionalId == original.profissionalId else { throw APIError.invalidResponse }
    }
    private func newRequestObserved(_ value: Appointment) -> Bool {
        guard let valueDate = value.confirmacaoPedidaEm.flatMap(ClinicClock.parseInstant) else { return false }
        guard let previous = requestedBeforeAttempt else { return true }
        guard let oldDate = ClinicClock.parseInstant(previous) else { return false }
        return valueDate > oldDate
    }
    private func handle(_ failure: Error) async {
        var reported = failure
        if failure as? APIError == .http(401) {
            do {
                try await requireContext()
                let current: User = try await api.get(["me"])
                try await requireContext()
                guard current.id == user.id, current.canConfirmAppointment else { throw APIError.http(403) }
            } catch { reported = error }
        }
        let currentContext = await api.requestContextID()
        if invalidated || context != currentContext { invalidate(); return }
        if let failure = reported as? APIError, [.contextChanged, .sessionExpired, .http(403), .http(404), .invalidResponse].contains(failure) { invalidate() }
        error = reported.localizedDescription
    }
    public func request() async {
        guard canRequest, let reviewed = appointment else { return }
        busy = true; error = nil; defer { busy = false }
        var posted = false
        var responded = false
        do {
            try await requireContext()
            let current: Appointment = try await api.get(["agendamentos", original.id])
            try await requireContext(); try validate(current)
            guard current.inicio == reviewed.inicio, current.duracaoMin == reviewed.duracaoMin,
                  current.status == reviewed.status, current.confirmacaoPedidaEm == reviewed.confirmacaoPedidaEm else {
                appointment = current; throw AppointmentConfirmationError.changed
            }
            guard AppointmentConfirmationState.canRequest(current, user: user, now: now()) else { throw AppointmentConfirmationError.notEligible }
            requestedBeforeAttempt = current.confirmacaoPedidaEm
            posted = true; outcome = .sending
            let result: Appointment = try await api.post(["agendamentos", original.id, "pedir-confirmacao"], expectedContext: context)
            responded = true
            try await requireContext(); try validate(result)
            guard result.inicio == current.inicio, newRequestObserved(result) else { throw AppointmentConfirmationError.uncertain }
            appointment = result; outcome = .succeeded
        } catch {
            if posted { outcome = responded ? .uncertain : WriteOutcome.afterFailure(error) }
            await handle(error)
        }
    }
    public func reconcile() async {
        guard !invalidated, !busy, outcome == .uncertain else { return }
        busy = true; defer { busy = false }
        do {
            try await requireContext()
            let current: Appointment = try await api.get(["agendamentos", original.id])
            try await requireContext(); try validate(current)
            appointment = current
            if newRequestObserved(current) { outcome = .succeeded; error = nil }
            else { error = AppointmentConfirmationError.uncertain.localizedDescription }
        } catch { await handle(error) }
    }
}
