import Foundation
import Testing
@testable import AtendeBemCore

@Test func lariPrescriptionCommandPreservesStrengthWithoutInventingDoseOrQuantity() {
    let command = LARIPrescriptionCommand(text: "emitir uma receita de Assert 100mg para o Paciente Fictício de uso contínuo para 30 dias")
    #expect(command.patientQuery == "Paciente Fictício")
    #expect(command.medicineQuery == "Assert 100mg")
    #expect(command.continuous == true)
    #expect(command.duration == "30 dias")
    #expect(command.posology.isEmpty)
    #expect(command.quantity.isEmpty)
    #expect(command.prescriptionType.isEmpty)
    #expect(LARIPrescriptionCommand.matches(command.original))
    #expect(!LARIPrescriptionCommand.matches("Me explique uma receita médica"))
}

@Test func lariPrescriptionCommandNeverResolvesIdentityFromName() {
    let command = LARIPrescriptionCommand(text: "Emitir receita para Maria")
    #expect(command.patientQuery == "Maria")
    #expect(command.medicineQuery.isEmpty)
    #expect(command.original == "Emitir receita para Maria")
}

private func taskPatient(_ phone: String = "11999990000") throws -> Patient {
    try JSONDecoder().decode(Patient.self, from: JSONSerialization.data(withJSONObject: ["id": "patient-fiction", "nome": "Paciente fictício", "telefone": phone, "email": "example@example.invalid"]))
}
private func taskUser(_ role: String = "medico") throws -> User {
    try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id": "author-fiction", "nome": "Profissional fictício", "email": "example@example.invalid", "papeis": [role]]))
}
private actor PrescriptionTaskTransport: HTTPTransport {
    struct Step: Sendable { let method: String; let suffix: String; let body: String; var status = 200; var lost = false }
    var steps: [Step]; var requests: [URLRequest] = []
    var onSend: (@Sendable (URLRequest) async -> Void)?
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        await onSend?(request)
        if request.url!.path.hasSuffix("/controle"), steps.first?.suffix != "/controle" {
            let body = #"{"controlado":false,"lista":null,"modelo":"simples","procedencia":"fora_do_catalogo_344"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        guard !steps.isEmpty else { Issue.record("Unexpected prescription task request"); throw APIError.invalidResponse }
        let step = steps.removeFirst(); #expect(request.httpMethod == step.method); #expect(request.url!.path.hasSuffix(step.suffix))
        if step.lost { throw URLError(.networkConnectionLost) }
        var response = step.body
        if request.httpMethod == "POST", let body = request.httpBody,
           let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let id = fields["id"] as? String {
            response = response.replacingOccurrences(of: "draft-fiction", with: id)
        }
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: nil)!)
    }
    func all() -> [URLRequest] { requests }
    func append(_ more: [Step]) { steps.append(contentsOf: more) }
    func observe(_ action: @escaping @Sendable (URLRequest) async -> Void) { onSend = action }
}
private func taskAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession(); return api
}
private let taskPatientJSON = #"{"id":"patient-fiction","nome":"Paciente fictício","telefone":"11999990000","email":"example@example.invalid"}"#
private let taskMedicineJSON = #"{"id":"medicine-fiction","nomeProduto":"Medicamento fictício","principioAtivo":"Substância fictícia","situacao":"ativo"}"#
private let taskDraftJSON = #"{"id":"draft-fiction","pacienteId":"patient-fiction","profissionalId":"author-fiction","tipo":"comum","status":"rascunho","itens":[{"medicamento":"Medicamento fictício 100 mg","posologia":"Posologia revisada","quantidade":"Quantidade revisada","usoContinuo":true,"duracao":"30 dias"}]}"#
@MainActor private func taskModel(_ transport: PrescriptionTaskTransport, role: String = "medico") async throws -> LARIPrescriptionTask {
    let api = try await taskAPI(transport)
    return LARIPrescriptionTask(command: "Emitir uma receita", api: api, context: await api.requestContextID(), user: try taskUser(role))
}
@MainActor private func prepareTask(_ model: LARIPrescriptionTask) async throws {
    await model.selectPatient(try taskPatient())
    model.selectMedicine(try JSONDecoder().decode(MedicineMatch.self, from: Data(taskMedicineJSON.utf8)))
    await model.checkMedicineControl()
    model.medicine = "Medicamento fictício 100 mg"; model.posology = "Posologia revisada"; model.quantity = "Quantidade revisada"
    model.prescriptionType = "comum"; model.continuous = true; model.duration = "30 dias"; model.reviewed = true
}

@Test @MainActor func lariPrescriptionTaskNeverWritesOnInitSearchOrSelection() async throws {
    let transport = PrescriptionTaskTransport([.init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]")])
    let model = try await taskModel(transport)
    #expect(await transport.all().isEmpty)
    try await prepareTask(model)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
    #expect(model.canCreate)
}

@Test @MainActor func lariPrescriptionMissingClinicalFieldsAndUnauthorizedRolePreventCreation() async throws {
    let transport = PrescriptionTaskTransport([]), model = try await taskModel(transport, role: "recepcao")
    await model.selectPatient(try taskPatient()); await model.createDraft()
    #expect(await transport.all().isEmpty)
    #expect(!model.canCreate)
    let empty = try await taskModel(PrescriptionTaskTransport([])); empty.reviewed = true
    #expect(!empty.canCreate)
}

@Test @MainActor func lariPrescriptionLostCreateResponseCannotAutomaticallyDuplicateDraft() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "POST", suffix: "/receitas", body: "", lost: true)])
    let model = try await taskModel(transport); try await prepareTask(model)
    await model.createDraft(); await model.createDraft()
    #expect(model.outcome == .uncertain); #expect(!model.canCreate)
    #expect(await transport.all().filter { $0.httpMethod == "POST" }.count == 1)
}

@Test @MainActor func lariPrescriptionCreatesOnlyDraftAndPreservesKnownFields() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "POST", suffix: "/receitas", body: taskDraftJSON)])
    let model = try await taskModel(transport); try await prepareTask(model); await model.createDraft()
    let writes = await transport.all().filter { $0.httpMethod == "POST" }
    #expect(writes.count == 1); #expect(model.document?.serverID == model.draftID); #expect(model.outcome == .succeeded)
    let body = try #require(writes.first?.httpBody)
    let decoded = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let items = try #require(decoded["itens"] as? [[String: Any]])
    #expect(items.first?["duracao"] as? String == "30 dias")
    #expect(items.first?["usoContinuo"] as? Bool == true)
    #expect(items.first?["dose"] == nil)
    #expect(!writes.contains { $0.url!.path.hasSuffix("assinar") || $0.url!.path.hasSuffix("enviar") })
}

@Test @MainActor func lariPrescriptionPatientChangeRequiresAnotherReviewWithoutWriting() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON.replacingOccurrences(of: "11999990000", with: "11888880000")), .init(method: "GET", suffix: "/alergias", body: "[]")])
    let model = try await taskModel(transport); try await prepareTask(model); await model.createDraft()
    #expect(!model.reviewed); #expect(model.error != nil); #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test func prescriptionProjectionIncludesGuidanceAndAllergyJustification() throws {
    let raw = taskDraftJSON.dropLast() + #", "orientacoes":"Orientação fictícia", "justificativaAlergia":"Justificativa fictícia"}"#
    let document = ClinicalDocumentSnapshot(try JSONDecoder().decode(Prescription.self, from: Data(raw.utf8)))
    #expect(document.detail.contains("Orientação fictícia")); #expect(document.detail.contains("Justificativa fictícia"))
}

private let taskCertificateJSON = #"{"cadastrado":true,"status":"valido","diasRestantes":30,"isTeste":false}"#
@MainActor private func prescriptionReview(_ transport: PrescriptionTaskTransport) async throws -> DocumentReview {
    let api = try await taskAPI(transport)
    let response = try JSONDecoder().decode(Prescription.self, from: Data(taskDraftJSON.utf8))
    let request = CreatePrescription(pacienteId: response.pacienteId, profissionalId: response.profissionalId, tipo: response.tipo, itens: response.itens, orientacoes: nil, justificativaAlergia: nil, id: response.id, modelo: "simples")
    let evidence = try PrescriptionDraftEvidence(request: request, response: response)
    return DocumentReview(api: api, context: await api.requestContextID(), kind: .prescription, documentID: "draft-fiction", patientID: "patient-fiction", user: try taskUser(), prescriptionEvidence: evidence)
}

@Test @MainActor func lariPrescriptionContactChangePreventsSignatureAndRequiresNewReview() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON),
        .init(method: "GET", suffix: "/certificados-medico", body: taskCertificateJSON),
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON.replacingOccurrences(of: "11999990000", with: "11888880000"))])
    let review = try await prescriptionReview(transport); await review.load(); #expect(review.canSign)
    await review.sign()
    #expect(review.error != nil); #expect(!review.canSign); #expect(review.delivery?.phone == "11888880000")
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test @MainActor func lariPrescriptionGuidanceChangePreventsSignature() async throws {
    let changed = taskDraftJSON.dropLast() + #", "orientacoes":"Orientação acrescentada pela web"}"#
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON),
        .init(method: "GET", suffix: "/certificados-medico", body: taskCertificateJSON),
        .init(method: "GET", suffix: "/receitas", body: "[\(changed)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON)])
    let review = try await prescriptionReview(transport); await review.load(); await review.sign()
    #expect(review.error != nil); #expect(review.document?.detail.contains("Orientação acrescentada pela web") == true)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test @MainActor func lariPrescriptionSignatureDoesNotSendSecondDeliveryRequest() async throws {
    let signed = taskDraftJSON.replacingOccurrences(of: #""status":"rascunho""#, with: #""status":"assinada""#).dropLast() + #", "assinatura":{"padrao":"ICP-Brasil","certificado":"A1","carimboTempo":"2026-10-03T10:00:00-03:00","validador":"Fictício","codigoVerificacao":"fiction"}}"#
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON),
        .init(method: "GET", suffix: "/certificados-medico", body: taskCertificateJSON),
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON),
        .init(method: "POST", suffix: "/assinar", body: "{}"), .init(method: "GET", suffix: "/receitas", body: "[\(signed)]")])
    let review = try await prescriptionReview(transport); await review.load(); await review.sign(); await review.sign()
    #expect(review.outcome == .succeeded)
    let writes = await transport.all().filter { $0.httpMethod == "POST" }
    #expect(writes.count == 1); #expect(writes.first?.url?.path.hasSuffix("/assinar") == true)
}

@Test @MainActor func lariPrescriptionRevokedPatientAccessClearsSigningContacts() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON),
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: "{}", status: 403)])
    let review = try await prescriptionReview(transport); await review.load(); #expect(review.delivery != nil)
    await review.load(); #expect(review.document == nil); #expect(review.delivery == nil); #expect(!review.canSign)
}

@Test @MainActor func lariPrescriptionInvalidationPreventsAnySearchOrCreation() async throws {
    let transport = PrescriptionTaskTransport([]), model = try await taskModel(transport)
    model.invalidate(); model.patientQuery = "Paciente fictício"; model.medicineQuery = "Fictício"
    await model.searchPatients(); await model.searchMedicines(); await model.selectPatient(try taskPatient()); await model.createDraft()
    #expect(await transport.all().isEmpty)
}

@Test @MainActor func lariPrescriptionCatalogSelectionReplacesDifferentProductAndPreservesItsPresentation() async throws {
    let model = try await taskModel(PrescriptionTaskTransport([]))
    model.medicine = "Produto anterior 100 mg"
    let match = try JSONDecoder().decode(MedicineMatch.self, from: Data(#"{"id":"catalog-fiction","nomeProduto":"Produto escolhido","concentracao":"50 mg","formaFarmaceutica":"comprimido","categoriaRegulatoria":"Categoria informada","situacao":"ativo"}"#.utf8))
    model.selectMedicine(match)
    #expect(model.medicine == "Produto escolhido 50 mg comprimido")
    #expect(model.medicineMatchesSelection)
    #expect(!model.reviewed)
    model.medicine = "Produto divergente 100 mg"
    #expect(!model.medicineMatchesSelection); #expect(!model.canCreate)
    #expect(model.prescriptionType.isEmpty)
}

@Test @MainActor func lariPrescriptionRequestedStrengthDoesNotMoveToDifferentProduct() async throws {
    let api = try await taskAPI(PrescriptionTaskTransport([]))
    let model = LARIPrescriptionTask(command: "Emitir receita de Produto original 100 mg para Paciente fictício", api: api, context: await api.requestContextID(), user: try taskUser())
    let match = try JSONDecoder().decode(MedicineMatch.self, from: Data(#"{"id":"catalog-fiction","nomeProduto":"Outro produto","situacao":"ativo"}"#.utf8))
    model.selectMedicine(match)
    #expect(model.medicine == "Outro produto")
    #expect(!model.medicine.contains("100"))
}

@Test @MainActor func lariPrescriptionReconciliationFindsExactClientDraftWithoutReplayingWrite() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "POST", suffix: "/receitas", body: "", lost: true)])
    let model = try await taskModel(transport); try await prepareTask(model); await model.createDraft()
    await transport.append([
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON),
        .init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON.replacingOccurrences(of: "draft-fiction", with: model.draftID))]")])
    await model.reconcileDraft(); await model.createDraft()
    #expect(model.document?.serverID == model.draftID); #expect(model.outcome == .succeeded)
    #expect(await transport.all().filter { $0.httpMethod == "POST" }.count == 1)
}

@Test func lariPrescriptionNegatedContinuousUseIsNotPreselected() {
    #expect(!LARIPrescriptionCommand(text: "Emitir receita de Produto para Paciente, sem uso contínuo").continuous)
    #expect(!LARIPrescriptionCommand(text: "Emitir receita de Produto para Paciente, não é uso contínuo").continuous)
}

@Test func lariPrescriptionUnknownAndSpecialModelsRemainBlocked() throws {
    for model in ["notificacao_a", "notificacao_b", "notificacao_b2", "retinoides", "talidomida"] {
        let control = try JSONDecoder().decode(PrescriptionMedicineControl.self, from: JSONSerialization.data(withJSONObject: ["modelo": model, "controlado": true, "lista": "sintética", "procedencia": "catalogo_344"]))
        #expect(!control.supported); #expect(!control.supports(type: "controle_especial"))
    }
    for raw in [#"{"controlado":null,"lista":null,"modelo":null,"procedencia":"principio_desconhecido"}"#, #"{"controlado":false,"lista":null,"modelo":"simples","procedencia":"principio_desconhecido"}"#] {
        #expect(!(try JSONDecoder().decode(PrescriptionMedicineControl.self, from: Data(raw.utf8))).supported)
    }
}

@Test func lariPrescriptionProjectionIncludesPresentationAndRegulatoryFields() throws {
    let raw = taskDraftJSON.replacingOccurrences(of: #""usoContinuo":true"#, with: #""usoContinuo":true,"concentracao":"100 mg","formaFarmaceutica":"comprimido","categoriaRegulatoria":"Categoria de catálogo""#)
    let snapshot = ClinicalDocumentSnapshot(try JSONDecoder().decode(Prescription.self, from: Data(raw.utf8)))
    #expect(snapshot.detail.contains("Concentração: 100 mg")); #expect(snapshot.detail.contains("Forma farmacêutica: comprimido")); #expect(snapshot.detail.contains("Categoria regulatória: Categoria de catálogo"))
    let changed = ClinicalDocumentSnapshot(try JSONDecoder().decode(Prescription.self, from: Data(raw.replacingOccurrences(of: "100 mg", with: "50 mg").utf8)))
    #expect(snapshot != changed)
}

@MainActor private final class PrescriptionContextFlag { var current = true }
@Test @MainActor func lariPrescriptionUIContextChangeDuringPreflightPreventsDraftWrite() async throws {
    let transport = PrescriptionTaskTransport([
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON), .init(method: "GET", suffix: "/alergias", body: "[]"),
        .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON)])
    let flag = PrescriptionContextFlag(), api = try await taskAPI(transport)
    let model = LARIPrescriptionTask(command: "Emitir receita", api: api, context: await api.requestContextID(), user: try taskUser(), isContextCurrent: { flag.current })
    try await prepareTask(model)
    await transport.observe { _ in await MainActor.run { flag.current = false } }
    await model.createDraft()
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" }); #expect(model.patient == nil)
}

@Test @MainActor func prescriptionWithoutCompleteLocalEvidenceCannotBeSigned() async throws {
    let transport = PrescriptionTaskTransport([.init(method: "GET", suffix: "/receitas", body: "[\(taskDraftJSON)]"), .init(method: "GET", suffix: "/patient-fiction", body: taskPatientJSON)])
    let api = try await taskAPI(transport)
    let review = DocumentReview(api: api, context: await api.requestContextID(), kind: .prescription, documentID: "draft-fiction", patientID: "patient-fiction", user: try taskUser())
    await review.load(); await review.sign()
    #expect(!review.canSign); #expect(review.signingUnavailableReason != nil)
    #expect(await transport.all().count == 2)
}

@Test func prescriptionEvidencePreservesHiddenInstructionsAndRejectsOtherContent() throws {
    let response = try JSONDecoder().decode(Prescription.self, from: Data(taskDraftJSON.utf8))
    let request = CreatePrescription(pacienteId: response.pacienteId, profissionalId: response.profissionalId, tipo: response.tipo, itens: response.itens, orientacoes: "Orientação completa fictícia", justificativaAlergia: "Justificativa completa fictícia", id: response.id, modelo: "simples")
    let evidence = try PrescriptionDraftEvidence(request: request, response: response)
    let snapshot = ClinicalDocumentSnapshot(response)
    #expect(evidence.matches(snapshot)); #expect(evidence.detail(for: snapshot)?.contains("Orientação completa fictícia") == true)
    #expect(evidence.detail(for: snapshot)?.contains("Justificativa completa fictícia") == true)
    let changed = try JSONDecoder().decode(Prescription.self, from: Data(taskDraftJSON.replacingOccurrences(of: "Posologia revisada", with: "Posologia diferente").utf8))
    #expect(!evidence.matches(ClinicalDocumentSnapshot(changed)))
    #expect(throws: APIError.self) { try PrescriptionDraftEvidence(request: request, response: changed) }
}

@Test @MainActor func lariPrescriptionAliasControlledCategoryCannotBeDowngraded() async throws {
    let model = try await taskModel(PrescriptionTaskTransport([]))
    let match = try JSONDecoder().decode(MedicineMatch.self, from: Data(#"{"id":"catalog-fiction","nomeProduto":"Produto fictício","categoriaRegulatoria":"Lista B1","situacao":"ativo"}"#.utf8))
    model.selectMedicine(match); await model.checkMedicineControl()
    #expect(model.medicineControl?.modelo == "simples")
    #expect(!model.controlMatchesCatalog); #expect(!model.canCreate)
}

@Test func lariPrescriptionControlRejectsNotificationListsWithGenericModel() throws {
    for list in ["A1", "B1", "B2", "C2", "C3", "futura"] {
        let raw = try JSONSerialization.data(withJSONObject: ["controlado": true, "lista": list, "modelo": "controle_especial", "procedencia": "catalogo_344"])
        #expect(!(try JSONDecoder().decode(PrescriptionMedicineControl.self, from: raw)).supported)
    }
}
