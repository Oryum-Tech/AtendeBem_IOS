import Foundation
import Observation

public enum ClinicalDocumentKind: String, Sendable, CaseIterable, Identifiable {
    case prescription = "receitas", certificate = "atestados", exam = "exames"
    public var id: String { rawValue }
    public var title: String {
        switch self { case .prescription: "Receitas"; case .certificate: "Atestados e declarações"; case .exam: "Exames" }
    }
}

/// A reviewable projection of one server document. Identity is checked before display or signing.
public struct ClinicalDocumentSnapshot: Sendable, Identifiable, Equatable {
    public let serverID: String
    public let patientID: String
    public let authorID: String
    public let kind: ClinicalDocumentKind
    public let title: String
    public let detail: String
    public let status: String
    public let date: String?
    public let signature: DocumentSignature?
    public let reportedSigned: Bool?
    public let provenance: String?
    public var id: String { kind.rawValue + ":" + serverID }
    public var statusLabel: String {
        ["rascunho": "Rascunho", "emitida": "Emitida", "emitido": "Emitido", "assinada": "Assinada", "assinado": "Assinado", "solicitado": "Solicitado", "pendente": "Pendente", "concluido": "Concluído", "cancelada": "Cancelada", "cancelado": "Cancelado"][status] ?? status
    }
    public var signatureLabel: String {
        if provenance == "historico_importado" { return "Histórico importado. A assinatura no AtendeBem não foi confirmada." }
        guard let signature else { return "Assinatura não informada pelo serviço" }
        return signature.padrao == "ICP-Brasil" ? "Assinatura ICP-Brasil informada pelo serviço" : "Padrão de assinatura: \(signature.padrao)"
    }
    public func canSign(user: User) -> Bool {
        guard authorID == user.id, signature == nil, reportedSigned != true else { return false }
        switch kind {
        case .prescription: return user.canPrescribe && status == "rascunho" && (provenance == nil || provenance == "rascunho")
        case .exam: return provenance == "solicitada" && user.canRequestExam && ["solicitado", "pendente"].contains(status)
        case .certificate: return false
        }
    }
    /// An external result is not a requisition issued by this clinic.
    public var canOpenPDF: Bool { kind != .exam || provenance == "solicitada" }
    public func validate(patientID: String, authorID: String? = nil) throws {
        guard !serverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              self.patientID == patientID, !self.authorID.isEmpty,
              authorID == nil || self.authorID == authorID else { throw APIError.invalidResponse }
    }
    public init(_ item: Prescription) {
        serverID = item.id; patientID = item.pacienteId; authorID = item.profissionalId; kind = .prescription
        title = "Receita — " + item.tipo.replacingOccurrences(of: "_", with: " ")
        detail = item.itens.enumerated().map { index, value in
            (["\(index + 1). \(value.medicamento)", "Posologia: \(value.posologia)"] + [
                value.quantidade.map { "Quantidade: \($0)" }, value.dose.map { "Dose: \($0)" },
                value.frequencia.map { "Frequência: \($0)" }, value.duracao.map { "Duração: \($0)" },
                value.instrucoes.map { "Instruções: \($0)" }, value.usoContinuo.map { "Uso contínuo: \($0 ? "Sim" : "Não")" },
                value.concentracao.map { "Concentração: \($0)" }, value.formaFarmaceutica.map { "Forma farmacêutica: \($0)" },
                value.categoriaRegulatoria.map { "Categoria regulatória: \($0)" }
            ].compactMap { $0 }).joined(separator: "\n")
        }.joined(separator: "\n\n") + [item.orientacoes.map { "\n\nOrientações gerais: \($0)" }, item.justificativaAlergia.map { "\n\nJustificativa sobre alergia: \($0)" }].compactMap { $0 }.joined()
        status = item.status; date = item.emitidaEm; signature = item.assinatura
        reportedSigned = item.assinada; provenance = item.procedencia
    }
    public init(_ item: MedicalDocument) {
        serverID = item.id; patientID = item.pacienteId; authorID = item.profissionalId; kind = .certificate
        title = item.titulo ?? item.tipo.capitalized
        detail = [item.descricao, item.diasAfastamento.map { "Dias de afastamento: \($0)" }, item.cid.map { "CID informado: \($0)" }]
            .compactMap { $0 }.joined(separator: "\n\n")
        status = item.status; date = item.emitidoEm; signature = item.assinatura; reportedSigned = nil; provenance = nil
    }
    public init(_ item: ExamRequest) {
        serverID = item.id; patientID = item.pacienteId; authorID = item.medicoId; kind = .exam
        title = (item.origem == "externa" ? "Exame externo — " : "Exames — ") + item.tipo
        detail = item.itens.enumerated().map { index, value in
            "\(index + 1). \(value.descricao)" + (value.tuss.map { "\nTUSS: \($0)" } ?? "")
        }.joined(separator: "\n\n") + (item.indicacaoClinica.map { "\n\nIndicação clínica: \($0)" } ?? "")
        status = item.status; date = item.realizadoEm ?? item.criadoEm; signature = item.assinatura; reportedSigned = nil; provenance = item.origem
    }
}

public enum DocumentReviewError: LocalizedError {
    case changed, unavailable, certificate, notAuthorized
    public var errorDescription: String? {
        switch self {
        case .changed: "O documento mudou desde a sua revisão. Confira o conteúdo atualizado antes de assinar."
        case .unavailable: "Não foi possível localizar este documento para o paciente nesta clínica."
        case .certificate: "O serviço não confirmou um certificado ativo e apto para uso. Confira Meu certificado digital."
        case .notAuthorized: "Seu perfil não pode assinar este documento ou o documento já saiu do estado de assinatura."
        }
    }
}

/// Only a complete locally submitted payload can establish review provenance for fields omitted by the public API.
public struct PrescriptionDraftEvidence: Sendable {
    public let documentID: String
    public let patientID: String
    public let authorID: String
    public let model: String?
    public let guidance: String?
    public let allergyJustification: String?
    private let projection: ClinicalDocumentSnapshot
    private let additionalDetail: String
    public init(request: CreatePrescription, response: Prescription) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let requested = try encoder.encode(request.itens), returned = try encoder.encode(response.itens)
        guard !response.id.isEmpty, !request.pacienteId.isEmpty, !request.profissionalId.isEmpty,
              request.id == nil || request.id == response.id,
              request.pacienteId == response.pacienteId, request.profissionalId == response.profissionalId,
              request.tipo == response.tipo, !request.itens.isEmpty, requested == returned,
              response.orientacoes == nil || response.orientacoes == request.orientacoes,
              response.justificativaAlergia == nil || response.justificativaAlergia == request.justificativaAlergia else { throw APIError.invalidResponse }
        documentID = response.id; patientID = response.pacienteId; authorID = response.profissionalId
        model = request.modelo; guidance = request.orientacoes; allergyJustification = request.justificativaAlergia
        projection = ClinicalDocumentSnapshot(response)
        additionalDetail = [
            response.orientacoes == nil ? request.orientacoes.map { "Orientações gerais enviadas: \($0)" } : nil,
            response.justificativaAlergia == nil ? request.justificativaAlergia.map { "Justificativa sobre alergia enviada: \($0)" } : nil,
            request.modelo.map { "Modelo solicitado: \($0.replacingOccurrences(of: "_", with: " "))" }
        ].compactMap { $0 }.joined(separator: "\n\n")
    }
    public func matches(_ current: ClinicalDocumentSnapshot) -> Bool {
        current.kind == .prescription && current.serverID == documentID && current.patientID == patientID &&
        current.authorID == authorID && current.title == projection.title && current.detail == projection.detail
    }
    public func detail(for current: ClinicalDocumentSnapshot) -> String? {
        guard matches(current) else { return nil }
        return [current.detail, additionalDetail].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

public enum ClinicalDocuments {
    public static func list(api: APIClient, kind: ClinicalDocumentKind, patientID: String) async throws -> [ClinicalDocumentSnapshot] {
        let query = [URLQueryItem(name: "pacienteId", value: patientID)]
        let result: [ClinicalDocumentSnapshot]
        switch kind {
        case .prescription:
            let items: [Prescription] = try await api.get([kind.rawValue], query: query); result = items.map(ClinicalDocumentSnapshot.init)
        case .certificate:
            let items: [MedicalDocument] = try await api.get([kind.rawValue], query: query); result = items.map(ClinicalDocumentSnapshot.init)
        case .exam:
            let items: [ExamRequest] = try await api.get([kind.rawValue], query: query); result = items.map(ClinicalDocumentSnapshot.init)
        }
        for item in result { try item.validate(patientID: patientID) }
        guard Set(result.map(\.id)).count == result.count else { throw APIError.invalidResponse }
        return result
    }
}

@Observable @MainActor public final class DocumentReview {
    public private(set) var document: ClinicalDocumentSnapshot?
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var outcome = WriteOutcome.ready
    public private(set) var updatedAt: Date?
    public private(set) var delivery: PrescriptionDeliveryReview?
    private let api: APIClient
    private let context: UUID
    private let kind: ClinicalDocumentKind
    private let documentID: String
    private let patientID: String
    private var active = true
    private let isContextCurrent: @MainActor () -> Bool
    private let prescriptionEvidence: PrescriptionDraftEvidence?
    public let user: User
    public init(api: APIClient, context: UUID, kind: ClinicalDocumentKind, documentID: String, patientID: String, user: User, isContextCurrent: @escaping @MainActor () -> Bool = { true }, prescriptionEvidence: PrescriptionDraftEvidence? = nil) {
        self.api = api; self.context = context; self.kind = kind; self.documentID = documentID; self.patientID = patientID; self.user = user
        self.isContextCurrent = isContextCurrent
        self.prescriptionEvidence = prescriptionEvidence
    }
    public var hasCompletePrescriptionPayload: Bool { document.map { prescriptionEvidence?.matches($0) == true } == true }
    public var reviewDetail: String { document.map { prescriptionEvidence?.detail(for: $0) ?? $0.detail } ?? "" }
    public var signingUnavailableReason: String? {
        guard kind == .prescription, document?.canSign(user: user) == true, !hasCompletePrescriptionPayload else { return nil }
        return "Este rascunho está sem os dados completos da criação nesta sessão ou difere do conteúdo enviado. O serviço não retorna todos os campos necessários para conferi-lo. Conclua a assinatura pelo fluxo em que a receita foi preparada."
    }
    public var canSign: Bool { active && isContextCurrent() && !busy && error == nil && outcome.canSubmit && document?.canSign(user: user) == true && (kind != .prescription || (delivery != nil && hasCompletePrescriptionPayload)) }
    public func invalidate() { active = false; document = nil; delivery = nil; updatedAt = nil }
    private func readDelivery() async throws -> PrescriptionDeliveryReview? {
        guard kind == .prescription else { return nil }
        let before = await api.requestContextID()
        guard active, isContextCurrent(), context == before else { throw APIError.contextChanged }
        let patient: Patient = try await api.get(["pacientes", patientID])
        let after = await api.requestContextID()
        guard active, isContextCurrent(), context == after, patient.id == patientID, !patient.nome.isEmpty else { throw APIError.invalidResponse }
        return PrescriptionDeliveryReview(patient)
    }
    private func read() async throws -> ClinicalDocumentSnapshot {
        let before = await api.requestContextID()
        guard active, isContextCurrent(), context == before else { throw APIError.contextChanged }
        let items = try await ClinicalDocuments.list(api: api, kind: kind, patientID: patientID)
        let after = await api.requestContextID()
        guard active, isContextCurrent(), context == after else { throw APIError.contextChanged }
        guard let result = items.first(where: { $0.serverID == documentID }) else { throw DocumentReviewError.unavailable }
        return result
    }
    public func load() async {
        guard active, !busy else { return }; busy = true
        defer { busy = false }
        do {
            let current = try await read()
            let currentDelivery = try await readDelivery()
            document = current; delivery = currentDelivery; updatedAt = .now; error = nil
            if document?.signature != nil { outcome = .succeeded }
        } catch { clearUnavailableDocument(after: error); self.error = error.localizedDescription }
    }
    private func clearUnavailableDocument(after error: Error) {
        if let apiError = error as? APIError, [.http(401), .http(403), .http(404), .sessionExpired, .contextChanged, .invalidResponse].contains(apiError) {
            document = nil; delivery = nil; updatedAt = nil
        } else if case DocumentReviewError.unavailable = error {
            document = nil; delivery = nil; updatedAt = nil
        }
    }
    public func sign() async {
        guard canSign, let reviewed = document else { return }
        let reviewedDelivery = delivery
        busy = true; error = nil
        defer { busy = false }
        var submitted = false
        var accepted = false
        do {
            if user.canPrescribe {
                let certificate: ProfessionalCertificate = try await api.get(["certificados-medico"])
                guard certificate.readyForSignature else { throw DocumentReviewError.certificate }
            }
            let fresh = try await read()
            let freshDelivery = try await readDelivery()
            document = fresh; delivery = freshDelivery; updatedAt = .now
            guard fresh == reviewed, freshDelivery == reviewedDelivery else { throw DocumentReviewError.changed }
            guard fresh.canSign(user: user) else { throw DocumentReviewError.notAuthorized }
            guard kind != .prescription || prescriptionEvidence?.matches(fresh) == true else { throw DocumentReviewError.notAuthorized }
            // The service has no conditional signature endpoint. This is a preflight, not atomic concurrency control.
            submitted = true; outcome = .sending
            let _: EmptyResponse = try await api.post([kind.rawValue, documentID, "assinar"], body: [String: String](), expectedContext: context)
            accepted = true; outcome = .uncertain
            document = try await read(); updatedAt = .now
            if document?.signature != nil { outcome = .succeeded }
            else { error = "A solicitação foi aceita, mas a assinatura ainda não foi confirmada na leitura. Atualize este documento antes de qualquer outra ação." }
        } catch {
            if submitted && !accepted { outcome = WriteOutcome.afterFailure(error) }
            clearUnavailableDocument(after: error)
            self.error = error.localizedDescription
            if submitted {
                // A read may establish success; never replay a signature automatically after a lost response.
                do {
                    let current = try await read()
                    document = current; updatedAt = .now
                    if current.signature != nil { outcome = .succeeded; self.error = nil }
                } catch { clearUnavailableDocument(after: error) }
            }
        }
    }
}
