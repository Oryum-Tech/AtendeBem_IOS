import Foundation
import Observation

public enum ExternalExamPolicy {
    public static func canReceive(user: User) -> Bool {
        user.containsAnyRole(User.careRoles + ["recepcao"])
    }
}

public enum ExternalExamError: LocalizedError {
    case invalidInput, invalidDate, emptyResult, reportTooLong, unsupportedFile, fileTooLarge, bodyTooLarge
    case missingResults, forbidden, uncertainCreation, uncertainAttachment, mismatchedResult
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Confira o paciente, o tipo e a descrição dos exames. O laboratório aceita até 160 caracteres."
        case .invalidDate: "Informe uma data válida para a realização do exame, ou deixe a data desconhecida."
        case .emptyResult: "Escreva o laudo ou escolha um arquivo para anexar."
        case .reportTooLong: "O laudo aceita até 20.000 caracteres."
        case .unsupportedFile: "Escolha um arquivo PDF, PNG, JPEG ou DICOM válido. O tipo é conferido pelo conteúdo do arquivo."
        case .fileTooLarge: "O arquivo ultrapassa o limite de 20 MiB."
        case .bodyTooLarge: "O arquivo e o texto ultrapassam o limite de envio. Selecione um arquivo menor e tente novamente."
        case .missingResults: "O serviço não informou a lista de resultados. Atualize o exame antes de anexar outro resultado."
        case .forbidden: "Seu perfil nesta clínica não permite registrar exames externos ou receber resultados."
        case .uncertainCreation: "O registro pode ter sido criado. Confira os registros encontrados antes de continuar; o app não repetirá o envio."
        case .uncertainAttachment: "O resultado pode ter sido recebido. Verifique o exame antes de continuar; o app não repetirá o envio."
        case .mismatchedResult: "O serviço retornou um registro diferente do conteúdo enviado. Confira o exame antes de qualquer novo envio."
        }
    }
}

public struct ExternalExamInput: Sendable, Encodable {
    public let patientID: String
    public let patientName: String
    public let type: String
    public let items: [ExamItem]
    public let performedOn: String?
    public let laboratory: String?
    public let indication: String?
    public init(patientID: String, patientName: String, type: String, items: [ExamItem], performedOn: String? = nil,
                laboratory: String? = nil, indication: String? = nil) {
        self.patientID = patientID; self.patientName = patientName; self.type = type; self.items = items
        self.performedOn = performedOn; self.laboratory = laboratory; self.indication = indication
    }
    enum CodingKeys: String, CodingKey {
        case patientID = "pacienteId", patientName = "pacienteNome", type = "tipo", items = "itens"
        case performedOn = "realizadoEm", laboratory = "laboratorio", indication = "indicacaoClinica"
    }
    func prepared() throws -> Self {
        guard !patientID.isEmpty, !patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ["laboratorial", "imagem", "outro"].contains(type), !items.isEmpty,
              items.allSatisfy({ !$0.descricao.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.tuss?.isEmpty != true }) else {
            throw ExternalExamError.invalidInput
        }
        let lab = Self.nonempty(laboratory)
        guard (lab?.utf16.count ?? 0) <= 160 else { throw ExternalExamError.invalidInput }
        let date = Self.nonempty(performedOn)
        if let date, Self.date(date) == nil { throw ExternalExamError.invalidDate }
        return Self(patientID: patientID, patientName: patientName, type: type, items: items,
                    performedOn: date, laboratory: lab, indication: Self.nonempty(indication))
    }
    static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    static func date(_ value: String) -> Date? {
        if value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
            return date.addingTimeInterval(12 * 60 * 60)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    func matches(_ exam: ExamRequest, authorID: String) -> Bool {
        exam.pacienteId == patientID && exam.pacienteNome == patientName && exam.medicoId == authorID && exam.origem == "externa"
        && exam.tipo == type && exam.itens.count == items.count
        && zip(exam.itens, items).allSatisfy { pair in pair.0.descricao == pair.1.descricao && pair.0.tuss == pair.1.tuss }
        && Self.nonempty(exam.laboratorio) == laboratory && Self.nonempty(exam.indicacaoClinica) == indication
        && exam.realizadoEm.flatMap(Self.date) == performedOn.flatMap(Self.date)
    }
}

public struct ExamResultFile: Sendable {
    public static let maximumBytes = 20 * 1024 * 1024
    /// svc-exames accepts JSON bodies up to 25 MiB. Base64 (and JSON escaping) consume this budget too.
    public static let maximumEncodedBodyBytes = 25 * 1024 * 1024
    public let data: Data
    public let name: String
    public let contentType: String
    public var canPreview: Bool { contentType != "application/dicom" }
    public init(data: Data, name: String) throws {
        guard data.count <= Self.maximumBytes else { throw ExternalExamError.fileTooLarge }
        let type: String
        if data.starts(with: Data("%PDF-".utf8)) { type = "application/pdf" }
        else if data.starts(with: Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) { type = "image/png" }
        else if data.count > 3 && data.starts(with: Data([0xff, 0xd8, 0xff])) { type = "image/jpeg" }
        else if data.count > 132 && data.subdata(in: 128..<132) == Data("DICM".utf8) { type = "application/dicom" }
        else { throw ExternalExamError.unsupportedFile }
        let leaf = name.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        let safe = String(leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty, safe != ".", safe != "..", safe.utf16.count <= 200 else { throw ExternalExamError.invalidInput }
        self.data = data; self.name = safe; self.contentType = type
    }
}

public struct ExamResultInput: Sendable {
    public let report: String?
    public let file: ExamResultFile?
    public let altered: Bool
    public init(report: String? = nil, file: ExamResultFile? = nil, altered: Bool = false) {
        self.report = report; self.file = file; self.altered = altered
    }
    func prepared() throws -> Self {
        guard (report?.utf16.count ?? 0) <= 20_000 else { throw ExternalExamError.reportTooLong }
        let report = ExternalExamInput.nonempty(report)
        guard report != nil || file != nil else { throw ExternalExamError.emptyResult }
        let result = Self(report: report, file: file, altered: altered)
        guard try JSONEncoder().encode(ResultBody(result)).count <= ExamResultFile.maximumEncodedBodyBytes else { throw ExternalExamError.bodyTooLarge }
        return result
    }
    func matches(_ result: ExamResult) -> Bool {
        guard ExternalExamInput.nonempty(result.laudo) == report, result.alterado == altered else { return false }
        if let file {
            return result.temArquivo && result.arquivoNome == file.name && result.arquivoTipo == file.contentType
        }
        return !result.temArquivo && result.arquivoNome == nil && result.arquivoTipo == nil
    }
}

private struct ResultBody: Encodable, Sendable {
    let laudo: String?
    let arquivoBase64: String?
    let arquivoNome: String?
    let arquivoTipo: String?
    let alterado: Bool
    init(_ value: ExamResultInput) {
        laudo = value.report; arquivoBase64 = value.file?.data.base64EncodedString()
        arquivoNome = value.file?.name; arquivoTipo = value.file?.contentType; alterado = value.altered
    }
}

public struct ExternalExamService: Sendable {
    let api: APIClient
    public init(api: APIClient) { self.api = api }
    func requireContext(_ expected: UUID) async throws {
        guard expected == (await api.requestContextID()) else { throw APIError.contextChanged }
    }
    func validate(_ value: ExamRequest, patientID: String, expectedContext: UUID, examID: String? = nil) async throws {
        try await requireContext(expectedContext)
        guard !value.id.isEmpty, value.pacienteId == patientID, !value.medicoId.isEmpty,
              examID == nil || value.id == examID else { throw APIError.invalidResponse }
        if let clinicID = await api.activeClinicID(), value.clinicaId != clinicID { throw APIError.invalidResponse }
        if let results = value.resultados {
            guard results.allSatisfy({ !$0.id.isEmpty }), Set(results.map(\.id)).count == results.count else { throw APIError.invalidResponse }
        }
        try await requireContext(expectedContext)
    }
    public func list(patientID: String, expectedContext: UUID) async throws -> [ExamRequest] {
        try await requireContext(expectedContext)
        let values: [ExamRequest] = try await api.get(["exames"], query: [URLQueryItem(name: "pacienteId", value: patientID)])
        try await requireContext(expectedContext)
        guard Set(values.map(\.id)).count == values.count else { throw APIError.invalidResponse }
        for value in values { try await validate(value, patientID: patientID, expectedContext: expectedContext) }
        return values
    }
    public func detail(examID: String, patientID: String, expectedContext: UUID) async throws -> ExamRequest {
        try await requireContext(expectedContext)
        let value: ExamRequest = try await api.get(["exames", examID])
        try await validate(value, patientID: patientID, expectedContext: expectedContext, examID: examID)
        return value
    }
    public func resultFile(examID: String, resultID: String, patientID: String, expectedContext: UUID) async throws -> ExamResultFile {
        let exam = try await detail(examID: examID, patientID: patientID, expectedContext: expectedContext)
        guard let result = exam.resultados?.first(where: { $0.id == resultID }), result.temArquivo,
              let name = result.arquivoNome, let type = result.arquivoTipo else { throw APIError.invalidResponse }
        let data = try await api.examResultData(examID: examID, resultID: resultID, expectedContext: expectedContext)
        try await requireContext(expectedContext)
        let file = try ExamResultFile(data: data, name: name)
        guard file.contentType == type else { throw APIError.invalidResponse }
        return file
    }
}

/// In-memory state for one patient and clinic. Uncertain writes can only be reconciled with reads.
@Observable @MainActor public final class ExternalExamWorkflow {
    public private(set) var exam: ExamRequest?
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var creationOutcome = WriteOutcome.ready
    public private(set) var attachmentOutcome = WriteOutcome.ready
    public private(set) var creationCandidates: [ExamRequest] = []
    private let service: ExternalExamService
    private let context: UUID
    private let patientID: String
    private let patientName: String
    private let user: User
    private var examID: String?
    private var invalidated = false
    private var creationAttempt: (input: ExternalExamInput, existingIDs: Set<String>)?
    private var attachmentAttempt: (input: ExamResultInput, previous: ExamRequest, existingIDs: Set<String>)?
    public init(api: APIClient, context: UUID, patientID: String, patientName: String, user: User, examID: String? = nil) {
        service = ExternalExamService(api: api); self.context = context; self.patientID = patientID
        self.patientName = patientName; self.user = user; self.examID = examID
    }
    public var canCreate: Bool { !busy && !invalidated && examID == nil && creationOutcome == .ready && ExternalExamPolicy.canReceive(user: user) }
    public var canStartAttachment: Bool { !busy && !invalidated && exam?.resultados != nil && (attachmentOutcome == .ready || attachmentOutcome == .succeeded) && ExternalExamPolicy.canReceive(user: user) }
    public var canAttach: Bool { !busy && !invalidated && exam != nil && exam?.resultados != nil && attachmentOutcome == .ready && ExternalExamPolicy.canReceive(user: user) }
    public func invalidate() {
        invalidated = true; exam = nil; creationCandidates = []; creationAttempt = nil; attachmentAttempt = nil; error = nil
    }
    public func resetAttachment() {
        guard !busy, attachmentOutcome == .succeeded || attachmentOutcome == .ready else { return }
        attachmentOutcome = .ready; attachmentAttempt = nil; error = nil
    }
    private func requireContext() async throws {
        guard !invalidated else { throw APIError.contextChanged }
        try await service.requireContext(context)
        guard !invalidated else { throw APIError.contextChanged }
    }
    private func handle(_ failure: Error) async {
        var reportedFailure = failure
        if failure as? APIError == .http(401) {
            // Refresh only through a safe read, never replay the rejected POST.
            do {
                try await requireContext()
                let refreshed: User = try await service.api.get(["me"])
                try await requireContext()
                guard refreshed.id == user.id, ExternalExamPolicy.canReceive(user: refreshed) else {
                    invalidate(); throw ExternalExamError.forbidden
                }
            } catch { reportedFailure = error }
        }
        let currentContext = await service.api.requestContextID()
        if reportedFailure as? APIError == .contextChanged || context != currentContext {
            invalidate()
        } else if let apiError = reportedFailure as? APIError, [.http(403), .http(404), .sessionExpired, .invalidResponse].contains(apiError) {
            exam = nil; creationCandidates = []
        }
        error = reportedFailure.localizedDescription
    }
    public func load() async {
        guard !busy, !invalidated, let examID else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await service.detail(examID: examID, patientID: patientID, expectedContext: context)
            try await requireContext()
            exam = value; error = nil
        }
        catch { await handle(error) }
    }
    public func create(_ input: ExternalExamInput) async {
        guard canCreate else { return }
        busy = true; error = nil; defer { busy = false }
        var posted = false; var returned = false
        do {
            try await requireContext()
            let prepared = try input.prepared()
            guard prepared.patientID == patientID, prepared.patientName == patientName else { throw APIError.invalidResponse }
            let existing = try await service.list(patientID: patientID, expectedContext: context)
            try await requireContext()
            creationAttempt = (prepared, Set(existing.map(\.id)))
            posted = true; creationOutcome = .sending
            let result: ExamRequest = try await service.api.post(["exames", "externos"], body: prepared, expectedContext: context)
            returned = true
            try await service.validate(result, patientID: patientID, expectedContext: context)
            try await requireContext()
            guard prepared.matches(result, authorID: user.id), !Set(existing.map(\.id)).contains(result.id) else { throw ExternalExamError.mismatchedResult }
            exam = result; examID = result.id; creationOutcome = .succeeded; creationAttempt = nil
        } catch {
            if posted { creationOutcome = returned ? .uncertain : WriteOutcome.afterFailure(error) }
            if creationOutcome == .ready { creationAttempt = nil }
            await handle(error)
        }
    }
    public func reconcileCreation() async {
        guard !busy, !invalidated, creationOutcome == .uncertain, let attempt = creationAttempt else { return }
        busy = true; defer { busy = false }
        do {
            let items = try await service.list(patientID: patientID, expectedContext: context)
            try await requireContext()
            creationCandidates = items.filter { !attempt.existingIDs.contains($0.id) && attempt.input.matches($0, authorID: user.id) }
            error = ExternalExamError.uncertainCreation.localizedDescription
        } catch { await handle(error) }
    }
    /// Selection is explicit: identical records may have been created concurrently on the web.
    public func selectCreatedExam(id: String) async {
        guard !busy, !invalidated, creationOutcome == .uncertain, let attempt = creationAttempt,
              creationCandidates.contains(where: { $0.id == id }) else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await service.detail(examID: id, patientID: patientID, expectedContext: context)
            try await requireContext()
            guard !attempt.existingIDs.contains(id), attempt.input.matches(result, authorID: user.id) else { throw ExternalExamError.mismatchedResult }
            exam = result; examID = id; creationOutcome = .succeeded; creationAttempt = nil; creationCandidates = []; error = nil
        } catch { await handle(error) }
    }
    public func attach(_ input: ExamResultInput) async {
        guard canAttach, let examID else { return }
        busy = true; error = nil; defer { busy = false }
        var posted = false; var returned = false
        do {
            try await requireContext()
            let prepared = try input.prepared()
            let previous = try await service.detail(examID: examID, patientID: patientID, expectedContext: context)
            try await requireContext()
            guard let results = previous.resultados else { throw ExternalExamError.missingResults }
            exam = previous
            attachmentAttempt = (prepared, previous, Set(results.map(\.id)))
            posted = true; attachmentOutcome = .sending
            let value: ExamRequest = try await service.api.post(["exames", examID, "resultado"], body: ResultBody(prepared), expectedContext: context)
            returned = true
            try await service.validate(value, patientID: patientID, expectedContext: context, examID: examID)
            guard try await verifyAttachment(value) else { throw ExternalExamError.uncertainAttachment }
            try await requireContext()
            exam = value; attachmentOutcome = .succeeded; attachmentAttempt = nil
        } catch {
            if posted { attachmentOutcome = returned ? .uncertain : WriteOutcome.afterFailure(error) }
            if attachmentOutcome == .ready { attachmentAttempt = nil }
            await handle(error)
        }
    }
    private func verifyAttachment(_ value: ExamRequest) async throws -> Bool {
        guard let attempt = attachmentAttempt, let results = value.resultados,
              value.id == attempt.previous.id, value.pacienteId == patientID,
              value.medicoId == attempt.previous.medicoId, value.origem == attempt.previous.origem else { throw ExternalExamError.mismatchedResult }
        let matches = results.filter { !attempt.existingIDs.contains($0.id) && attempt.input.matches($0) }
        for match in matches {
            if let expected = attempt.input.file {
                let file = try await service.resultFile(examID: value.id, resultID: match.id, patientID: patientID, expectedContext: context)
                if file.data != expected.data { continue }
            }
            try await requireContext()
            return true
        }
        try await requireContext()
        return false
    }
    public func reconcileAttachment() async {
        guard !busy, !invalidated, attachmentOutcome == .uncertain, let examID else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await service.detail(examID: examID, patientID: patientID, expectedContext: context)
            try await requireContext()
            if try await verifyAttachment(value) {
                try await requireContext()
                exam = value; attachmentOutcome = .succeeded; attachmentAttempt = nil; error = nil
            } else { exam = value; error = ExternalExamError.uncertainAttachment.localizedDescription }
        } catch { await handle(error) }
    }
}
