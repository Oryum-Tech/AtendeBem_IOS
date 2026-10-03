import Foundation
import Observation

public struct LARIAppointmentCommand: Sendable {
    public let original: String
    public let patientQuery: String
    public let requestedStart: Date?
    public let requestedDuration: Int?
    public init(text: String, now: Date = .now) {
        original = text; patientQuery = LARICommandFields.patientQuery(from: text)
        requestedDuration = LARICommandFields.capture(#"\b(?:por|dura[cç][aã]o\s*:?)\s*(\d{1,3})\s*min(?:utos)?\b"#, from: text).flatMap(Int.init)
        requestedStart = Self.explicitStart(text, now: now)
    }
    private static func explicitStart(_ text: String, now: Date) -> Date? {
        guard let time = LARICommandFields.capture(#"\b(?:[àa]s\s+|hor[aá]rio\s*:\s*)(\d{1,2}(?::\d{2}|h(?:\d{2})?))\b"#, from: text) else { return nil }
        let pieces = time.replacingOccurrences(of: "h", with: ":", options: .caseInsensitive).split(separator: ":", omittingEmptySubsequences: false)
        guard let hour = Int(pieces[0]), (0...23).contains(hour) else { return nil }
        let minute = pieces.count > 1 && !pieces[1].isEmpty ? Int(pieces[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = ClinicClock.timeZone
        let day: Date
        if let raw = LARICommandFields.capture(#"\b(\d{2}/\d{2}/\d{4})\b"#, from: text) {
            let values = raw.split(separator: "/").compactMap { Int($0) }
            var parts = DateComponents(); parts.year = values[2]; parts.month = values[1]; parts.day = values[0]
            guard let parsed = calendar.date(from: parts), calendar.component(.year, from: parsed) == values[2], calendar.component(.month, from: parsed) == values[1], calendar.component(.day, from: parsed) == values[0] else { return nil }
            day = parsed
        } else if text.range(of: #"\bamanh[aã]\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }; day = tomorrow
        } else if text.range(of: #"\bhoje\b"#, options: [.regularExpression, .caseInsensitive]) != nil { day = now }
        else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

public struct LARIAppointmentSlot: Decodable, Sendable, Identifiable, Equatable {
    public let inicio: String
    public let duracaoMin: Int
    public var id: String { inicio + ":" + String(duracaoMin) }
    public var date: Date? { ClinicClock.parseInstant(inicio) }
}

private struct LARIAppointmentInput: Encodable, Sendable {
    let id: String
    let inicio: String
    let duracaoMin: Int
    let pacienteId: String
    let profissionalId: String
    let tipo: String
    let canal: String
    func matches(_ value: Appointment) -> Bool {
        value.id == id && value.pacienteId == pacienteId && value.profissionalId == profissionalId &&
        value.startDate == ClinicClock.parseInstant(inicio) && value.duracaoMin == duracaoMin && value.tipo == tipo && value.canal == canal
    }
}

@Observable @MainActor public final class LARIAppointmentTask {
    public let command: LARIAppointmentCommand
    public let requestID = UUID().uuidString
    public let lookup: LARIPatientLookup
    public var day: Date { didSet { clearAvailability() } }
    public var professionalID = "" { didSet { if oldValue != professionalID { clearAvailability() } } }
    public var typeID = "" { didSet { reviewed = false } }
    public var channel = "" { didSet { reviewed = false } }
    public var reviewed = false
    public private(set) var professionals: [User] = []
    public private(set) var types: [AppointmentType] = []
    public private(set) var slots: [LARIAppointmentSlot] = []
    public private(set) var selectedSlot: LARIAppointmentSlot?
    public private(set) var availabilityLoaded = false
    public private(set) var appointment: Appointment?
    public private(set) var outcome = WriteOutcome.ready
    public private(set) var busy = false
    public private(set) var error: String?
    private let scope: LARIPatientTaskContext
    private let now: @Sendable () -> Date
    private var submittedInput: LARIAppointmentInput?
    public init(command: String, api: APIClient, context: UUID, user: User, now: @escaping @Sendable () -> Date = { .now }, isContextCurrent: @escaping @MainActor () -> Bool = { true }) {
        let parsed = LARIAppointmentCommand(text: command, now: now())
        self.command = parsed; self.now = now
        day = parsed.requestedStart ?? now()
        let scope = LARIPatientTaskContext(api: api, context: context, user: user, route: .appointment, isContextCurrent: isContextCurrent)
        self.scope = scope; lookup = LARIPatientLookup(query: parsed.patientQuery, scope: scope)
    }
    public var isWorking: Bool { busy || lookup.busy }
    public var canEdit: Bool { scope.available && !isWorking && outcome.canSubmit }
    public var selectedProfessional: User? { professionals.first { $0.id == professionalID } }
    public var selectedType: AppointmentType? { types.first { $0.id == typeID && $0.ativo } }
    public var canCreate: Bool {
        canEdit && reviewed && lookup.patient != nil && selectedProfessional != nil && selectedType != nil &&
        ["presencial", "teleconsulta"].contains(channel) && selectedSlot.map { slot in
            slots.contains(slot) && slot.date.map { $0 > now() } == true &&
            (command.requestedDuration == nil || command.requestedDuration == slot.duracaoMin)
        } == true
    }
    public func invalidate() { scope.invalidate(); lookup.invalidate(); slots = []; professionals = []; types = []; appointment = nil; submittedInput = nil; selectedSlot = nil; reviewed = false }
    private func clearAvailability() { slots = []; selectedSlot = nil; availabilityLoaded = false; reviewed = false }
    private func fail(_ failure: Error) {
        error = failure.localizedDescription
        if lariInvalidatesContent(failure) { lookup.invalidate(); appointment = nil; slots = []; selectedSlot = nil; reviewed = false }
    }
    public func loadOptions() async {
        guard canEdit else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            try await scope.check()
            let team: [User] = try await scope.api.get(["usuarios"])
            try await scope.check()
            let catalog: AppointmentTypeCatalog = try await scope.api.get(["agenda", "tipos-atendimento"])
            try await scope.check()
            guard Set(team.map(\.id)).count == team.count, Set(catalog.itens.map(\.id)).count == catalog.itens.count else { throw APIError.invalidResponse }
            professionals = team.filter { $0.canReadClinicalData && !$0.id.isEmpty && !$0.nome.isEmpty }
            types = catalog.itens.filter { $0.ativo && !$0.id.isEmpty }
            if !professionals.contains(where: { $0.id == professionalID }) { professionalID = "" }
            if selectedType == nil { typeID = "" }
        } catch { fail(error) }
    }
    public func searchPatients() async { guard canEdit else { return }; await lookup.search() }
    public func selectPatient(_ patient: Patient) async { guard canEdit else { return }; reviewed = false; await lookup.select(patient) }
    public func changePatient() { guard canEdit else { return }; reviewed = false; lookup.clearSelection() }
    private func readSlots(professional: String, day: String) async throws -> [LARIAppointmentSlot] {
        try await scope.check()
        let result: [LARIAppointmentSlot] = try await scope.api.get(["disponibilidade"], query: [.init(name: "profissionalId", value: professional), .init(name: "de", value: day), .init(name: "ate", value: day)])
        try await scope.check()
        guard Set(result.map(\.id)).count == result.count, result.allSatisfy({ slot in
            slot.duracaoMin > 0 && slot.duracaoMin <= 480 && slot.date.map { ClinicClock.day($0) == day } == true
        }) else { throw APIError.invalidResponse }
        return result.filter { $0.date.map { $0 > now() } == true }
    }
    public func loadAvailability() async {
        guard canEdit, selectedProfessional != nil else { return }
        let professional = professionalID, key = ClinicClock.day(day)
        busy = true; error = nil; clearAvailability()
        defer { busy = false }
        do {
            let values = try await readSlots(professional: professional, day: key)
            guard professionalID == professional, ClinicClock.day(day) == key else { throw APIError.contextChanged }
            slots = values; availabilityLoaded = true
        } catch { fail(error) }
    }
    public func selectSlot(_ slot: LARIAppointmentSlot) {
        guard canEdit, slots.contains(slot) else { return }; selectedSlot = slot; reviewed = false
    }
    public func create() async {
        guard canCreate, let patient = lookup.patient, let slot = selectedSlot, let professional = selectedProfessional, let type = selectedType else { return }
        let input = LARIAppointmentInput(id: requestID, inicio: slot.inicio, duracaoMin: slot.duracaoMin, pacienteId: patient.id, profissionalId: professional.id, tipo: type.id, canal: channel)
        busy = true; error = nil; var submitted = false
        defer { busy = false }
        do {
            let freshPatient = try await scope.readPatient(patient.id)
            guard PrescriptionDeliveryReview(freshPatient) == PrescriptionDeliveryReview(patient) else { lookup.update(freshPatient); reviewed = false; throw DocumentReviewError.changed }
            let available = try await readSlots(professional: professional.id, day: ClinicClock.day(day))
            guard available.contains(slot) else { clearAvailability(); throw APIError.http(409) }
            let catalog: AppointmentTypeCatalog = try await scope.api.get(["agenda", "tipos-atendimento"])
            try await scope.check()
            guard catalog.itens.contains(where: { $0.id == type.id && $0.ativo && $0.rotulo == type.rotulo }) else { reviewed = false; throw DocumentReviewError.changed }
            guard reviewed else { throw DocumentReviewError.changed }
            submittedInput = input; submitted = true; outcome = .sending
            let result: Appointment = try await scope.api.post(["agendamentos"], body: input, expectedContext: scope.context)
            try await scope.check()
            guard input.matches(result) else { throw APIError.invalidResponse }
            appointment = result; outcome = .succeeded
        } catch {
            if submitted { outcome = (error as? APIError)?.statusCode == 409 ? .uncertain : WriteOutcome.afterFailure(error) }
            fail(error)
        }
    }
    public func reconcile() async {
        guard scope.available, !isWorking, outcome == .uncertain, let input = submittedInput else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            try await scope.check()
            let value: Appointment = try await scope.api.get(["agendamentos", input.id])
            try await scope.check()
            guard input.matches(value) else { throw APIError.invalidResponse }
            let patient = try await scope.readPatient(input.pacienteId)
            lookup.update(patient); appointment = value; outcome = .succeeded
        } catch APIError.http(404) {
            error = "Este identificador ainda não apareceu no sistema. A tarefa continua bloqueada para evitar duplicidade. Confira a agenda antes de iniciar outro pedido."
        } catch { fail(error) }
    }
}
