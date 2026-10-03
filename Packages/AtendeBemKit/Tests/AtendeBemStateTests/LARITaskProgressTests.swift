import AtendeBemCore
import Foundation
import Testing
@testable import AtendeBemUI

private final class ProgressStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var session: StoredSession?
    init(_ session: StoredSession) { self.session = session }
    func load() throws -> StoredSession? { lock.withLock { session } }
    func save(_ value: StoredSession) throws { lock.withLock { session = value } }
    func clear() throws { lock.withLock { session = nil } }
}

private actor ProgressTransport: HTTPTransport {
    struct Step: Sendable {
        let method: String
        let suffix: String
        let json: String
        var status = 200
        var lost = false
    }
    private var steps: [Step]
    private var requests: [URLRequest] = []
    private var createdID = ""
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { Issue.record("Unexpected progress fixture request"); throw APIError.invalidResponse }
        let step = steps.removeFirst()
        #expect(request.httpMethod == step.method)
        #expect(request.url!.path.hasSuffix(step.suffix))
        if step.lost { throw URLError(.networkConnectionLost) }
        if request.httpMethod == "POST", let body = request.httpBody,
           let value = try JSONSerialization.jsonObject(with: body) as? [String: Any], let id = value["id"] as? String { createdID = id }
        let json = step.json.replacingOccurrences(of: "$ID", with: createdID)
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: nil)!)
    }
    func postCount() -> Int { requests.filter { $0.httpMethod == "POST" }.count }
    func remaining() -> Int { steps.count }
    func append(_ next: [Step]) { steps.append(contentsOf: next) }
}

private let progressPatient = #"{"id":"patient-fiction","nome":"Paciente Fictício","telefone":"11999990000"}"#
private let progressDoctor = #"{"id":"doctor-fiction","nome":"Profissional Fictício","email":"doctor@example.invalid","papeis":["medico"]}"#
private let progressSignature = #"{"padrao":"ICP-Brasil","certificado":"A1","carimboTempo":"2030-01-01T00:00:00Z","validador":"Fictício","codigoVerificacao":"fiction"}"#
private let progressPrescription = #"{"id":"$ID","pacienteId":"patient-fiction","profissionalId":"doctor-fiction","tipo":"comum","status":"rascunho","itens":[{"medicamento":"Medicamento Fictício","posologia":"Posologia revisada","quantidade":"Quantidade revisada","usoContinuo":false}]}"#
private let progressExam = #"{"id":"exam-fiction","pacienteId":"patient-fiction","pacienteNome":"Paciente Fictício","medicoId":"doctor-fiction","tipo":"laboratorial","itens":[{"descricao":"Exame fictício"}],"status":"solicitado","criadoEm":"2030-01-01T00:00:00Z","origem":"solicitada"}"#
private let progressTimeline = #"{"pacienteId":"patient-fiction","eventos":[],"paginacao":{"page":1,"perPage":25,"total":0,"totalPaginas":0},"avisos":[]}"#

private func progressAPI(_ transport: ProgressTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage: ProgressStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession()
    return api
}
private func progressUser() throws -> User { try JSONDecoder().decode(User.self, from: Data(progressDoctor.utf8)) }
private func progressPerson() throws -> Patient { try JSONDecoder().decode(Patient.self, from: Data(progressPatient.utf8)) }

@Test @MainActor func readOnlyTasksWithoutRetainedResultsNeverClaimCompletion() {
    let store = LARITaskSessionStore(), context = UUID()
    for route in [LARITaskRoute.financial, .analytics, .interactions, .medicineReference] {
        let request = store.request(command: route.starter, route: route, context: context)
        let progress = store.progress(for: request)
        #expect(progress.title == "Abrir consulta" && !progress.isWorking && !progress.needsAttention)
        #expect(progress.detail.contains("não fica retido"))
    }
    store.invalidateAll()
    #expect(store.requests.isEmpty)
}

@Test(arguments: [false, true]) @MainActor
func prescriptionProgressDistinguishesSavedDraftFromConfirmedOrUncertainSignature(confirmSignature: Bool) async throws {
    let afterSigning = confirmSignature
        ? String(progressPrescription.dropLast()) + #", "assinatura":"# + progressSignature + "}"
        : progressPrescription
    let transport = ProgressTransport([
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/alergias", json: "[]"),
        .init(method: "GET", suffix: "/controle", json: #"{"controlado":false,"lista":null,"modelo":"simples","procedencia":"fora_do_catalogo_344"}"#),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/alergias", json: "[]"),
        .init(method: "POST", suffix: "/receitas", json: progressPrescription),
        .init(method: "GET", suffix: "/receitas", json: "[\(progressPrescription)]"),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/certificados-medico", json: #"{"cadastrado":true,"status":"valido","diasRestantes":30,"isTeste":false}"#),
        .init(method: "GET", suffix: "/receitas", json: "[\(progressPrescription)]"),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "POST", suffix: "/assinar", json: "{}"),
        .init(method: "GET", suffix: "/receitas", json: "[\(afterSigning)]")
    ])
    let api = try await progressAPI(transport), store = LARITaskSessionStore()
    let request = store.request(command: "Preparar receita", route: .prescription, context: UUID())
    let task = LARIPrescriptionTask(command: request.command, api: api, context: await api.requestContextID(), user: try progressUser())
    store.prescriptionTasks[request.id] = task
    await task.selectPatient(try progressPerson())
    let medicine = try JSONDecoder().decode(MedicineMatch.self, from: Data(#"{"id":"medicine-fiction","nomeProduto":"Medicamento Fictício","principioAtivo":"Princípio fictício","situacao":"ativo"}"#.utf8))
    task.selectMedicine(medicine); await task.checkMedicineControl()
    task.posology = "Posologia revisada"; task.quantity = "Quantidade revisada"; task.prescriptionType = "comum"; task.reviewed = true
    #expect(task.canCreate)
    await task.createDraft()
    #expect(task.outcome == .succeeded)
    #expect(store.progress(for: request).title == "Aguardando assinatura")
    #expect(store.progress(for: request).needsAttention)
    #expect(await transport.postCount() == 1)
    let review = try #require(task.signatureReview)
    await review.load(); await review.sign()
    let progress = store.progress(for: request)
    #expect(progress.title == (confirmSignature ? "Assinatura informada" : "Conferir assinatura"))
    #expect(progress.needsAttention == !confirmSignature)
    if confirmSignature { #expect(progress.detail.contains("recebimento pelo paciente não está confirmado")) }
    else { #expect(!store.canStartAnother(after: request)) }
    // Projecting the same task repeatedly must never sign or request delivery again.
    _ = store.progress(for: request)
    #expect(await transport.postCount() == 2)
    #expect(await transport.remaining() == 0)
}

@Test(arguments: [false, true]) @MainActor
func examProgressDistinguishesQueuedDeliveryFromUncertainDelivery(loseDeliveryResponse: Bool) async throws {
    let signedExam = String(progressExam.dropLast()) + #", "assinatura":"# + progressSignature + "}"
    let transport = ProgressTransport([
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "POST", suffix: "/exames", json: signedExam),
        .init(method: "GET", suffix: "/exam-fiction", json: signedExam),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/exam-fiction", json: signedExam),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "POST", suffix: "/enviar", json: #"{"status":"enfileirado","solicitacaoId":"exam-fiction","canais":["whatsapp"]}"#, lost: loseDeliveryResponse)
    ])
    let api = try await progressAPI(transport), store = LARITaskSessionStore()
    let request = store.request(command: "Solicitar exames de Exame fictício para Paciente Fictício", route: .examRequest, context: UUID())
    let task = LARIExamRequestTask(command: request.command, api: api, context: await api.requestContextID(), user: try progressUser())
    store.examTasks[request.id] = task
    await task.selectPatient(try progressPerson()); task.type = "laboratorial"; task.reviewed = true; await task.create()
    #expect(store.progress(for: request).title == "Revisar envio")
    await task.prepareDelivery(); task.sendByWhatsApp = true; task.deliveryReviewed = true
    #expect(task.canSend)
    await task.send()
    let progress = store.progress(for: request)
    #expect(progress.title == (loseDeliveryResponse ? "Conferir envio" : "Envio solicitado"))
    #expect(progress.needsAttention == loseDeliveryResponse)
    if loseDeliveryResponse { #expect(!store.canStartAnother(after: request)) }
    else { #expect(progress.detail.contains("não comprova recebimento")) }
    await task.send()
    #expect(await transport.postCount() == 2)
    #expect(await transport.remaining() == 0)
}

@Test(arguments: [false, true]) @MainActor
func historyProgressPreservesPartialAndUnavailableSourceWarnings(allUnavailable: Bool) async throws {
    let transport = ProgressTransport([
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/ficha", json: progressTimeline, status: allUnavailable ? 503 : 200),
        .init(method: "GET", suffix: "/antecedentes", json: "{}", status: 503),
        .init(method: "GET", suffix: "/alergias", json: "[]", status: allUnavailable ? 503 : 200)
    ])
    let api = try await progressAPI(transport), store = LARITaskSessionStore()
    let request = store.request(command: "Consultar histórico do paciente Fictício", route: .patientHistory, context: UUID())
    let task = LARIHistoryTask(command: request.command, api: api, context: await api.requestContextID(), user: try progressUser())
    store.historyTasks[request.id] = task
    await task.selectPatient(try progressPerson())
    #expect(task.updatedAt != nil)
    let progress = store.progress(for: request)
    #expect(progress.title == (allUnavailable ? "Fontes indisponíveis" : "Histórico parcial"))
    #expect(progress.needsAttention)
    #expect(await transport.postCount() == 0)
    #expect(await transport.remaining() == 0)
    store.invalidateAll()
    #expect(store.progress(for: request).title == "Sessão encerrada")
}

@Test(arguments: [false, true]) @MainActor
func cancellationInEitherExamSnapshotOverridesPreviouslyQueuedDelivery(cancelTaskSnapshot: Bool) async throws {
    let signed = String(progressExam.dropLast()) + #", "assinatura":"# + progressSignature + "}"
    let cancelled = signed.replacingOccurrences(of: #""status":"solicitado""#, with: #""status":"cancelada""#)
    let transport = ProgressTransport([
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "POST", suffix: "/exames", json: signed),
        .init(method: "GET", suffix: "/exames", json: "[\(signed)]"),
        .init(method: "GET", suffix: "/exam-fiction", json: signed),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/exam-fiction", json: signed),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "POST", suffix: "/enviar", json: #"{"status":"enfileirado","solicitacaoId":"exam-fiction","canais":["whatsapp"]}"#)
    ])
    let api = try await progressAPI(transport), store = LARITaskSessionStore()
    let request = store.request(command: "Solicitar exames de Exame fictício para Paciente Fictício", route: .examRequest, context: UUID())
    let task = LARIExamRequestTask(command: request.command, api: api, context: await api.requestContextID(), user: try progressUser())
    store.examTasks[request.id] = task
    await task.selectPatient(try progressPerson()); task.type = "laboratorial"; task.reviewed = true; await task.create()
    let review = try #require(task.signatureReview)
    await review.load(); await task.prepareDelivery()
    task.sendByWhatsApp = true; task.deliveryReviewed = true; await task.send()
    #expect(task.deliveryOutcome == .succeeded)
    #expect(store.progress(for: request).title == "Envio solicitado")
    if cancelTaskSnapshot {
        await transport.append([
            .init(method: "GET", suffix: "/exam-fiction", json: cancelled),
            .init(method: "GET", suffix: "/patient-fiction", json: progressPatient)
        ])
        await task.prepareDelivery()
        #expect(task.document?.status == "cancelada" && review.document?.status == "solicitado")
    } else {
        await transport.append([.init(method: "GET", suffix: "/exames", json: "[\(cancelled)]")])
        await review.load()
        #expect(task.document?.status == "solicitado" && review.document?.status == "cancelada")
    }
    let progress = store.progress(for: request)
    #expect(progress.title == "Documento cancelado" && progress.needsAttention)
    #expect(progress.detail.contains("nenhum envio anterior é revertido"))
    #expect(!task.canSend)
    #expect(await transport.postCount() == 2)
    #expect(await transport.remaining() == 0)
}

@Test @MainActor func prescriptionCancellationFromReviewOverridesRetainedDraft() async throws {
    let cancelled = progressPrescription.replacingOccurrences(of: #""status":"rascunho""#, with: #""status":"cancelada""#)
    let transport = ProgressTransport([
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/alergias", json: "[]"),
        .init(method: "GET", suffix: "/controle", json: #"{"controlado":false,"lista":null,"modelo":"simples","procedencia":"fora_do_catalogo_344"}"#),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/alergias", json: "[]"),
        .init(method: "POST", suffix: "/receitas", json: progressPrescription),
        .init(method: "GET", suffix: "/receitas", json: "[\(cancelled)]"),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient)
    ])
    let api = try await progressAPI(transport), store = LARITaskSessionStore()
    let request = store.request(command: "Preparar receita", route: .prescription, context: UUID())
    let task = LARIPrescriptionTask(command: request.command, api: api, context: await api.requestContextID(), user: try progressUser())
    store.prescriptionTasks[request.id] = task
    await task.selectPatient(try progressPerson())
    let medicine = try JSONDecoder().decode(MedicineMatch.self, from: Data(#"{"id":"medicine-fiction","nomeProduto":"Medicamento Fictício","principioAtivo":"Princípio fictício","situacao":"ativo"}"#.utf8))
    task.selectMedicine(medicine); await task.checkMedicineControl()
    task.posology = "Posologia revisada"; task.quantity = "Quantidade revisada"; task.prescriptionType = "comum"; task.reviewed = true
    await task.createDraft()
    let review = try #require(task.signatureReview)
    await review.load()
    #expect(task.document?.status == "rascunho" && review.document?.status == "cancelada")
    #expect(store.progress(for: request).title == "Documento cancelado")
    #expect(!review.canSign)
    #expect(await transport.postCount() == 1)
    #expect(await transport.remaining() == 0)
}

@Test @MainActor func reconciledAppointmentCancellationNeverAppearsAsAnActiveBooking() async throws {
    let catalog = ##"{"escopo":"clinica","itens":[{"id":"consulta","rotulo":"Consulta","cor":"#000000","ordem":0,"ativo":true,"sistemico":true,"contaComoRetorno":false}]}"##
    let slots = #"[{"inicio":"2030-01-02T14:00:00-03:00","duracaoMin":30}]"#
    let transport = ProgressTransport([
        .init(method: "GET", suffix: "/usuarios", json: "[\(progressDoctor)]"),
        .init(method: "GET", suffix: "/tipos-atendimento", json: catalog),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/disponibilidade", json: slots),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient),
        .init(method: "GET", suffix: "/disponibilidade", json: slots),
        .init(method: "GET", suffix: "/tipos-atendimento", json: catalog),
        .init(method: "POST", suffix: "/agendamentos", json: "", lost: true)
    ])
    let api = try await progressAPI(transport), store = LARITaskSessionStore()
    let request = store.request(command: "Agendar consulta para Paciente Fictício em 02/01/2030 às 14h", route: .appointment, context: UUID())
    let task = LARIAppointmentTask(command: request.command, api: api, context: await api.requestContextID(), user: try progressUser(), now: { Date(timeIntervalSince1970: 1_893_456_000) })
    store.appointmentTasks[request.id] = task
    await task.loadOptions(); await task.selectPatient(try progressPerson())
    task.professionalID = "doctor-fiction"; task.typeID = "consulta"; task.channel = "presencial"
    await task.loadAvailability(); task.selectSlot(try #require(task.slots.first)); task.reviewed = true
    await task.create()
    #expect(task.outcome == .uncertain)
    let cancelled = "{\"id\":\"\(task.requestID)\",\"inicio\":\"2030-01-02T14:00:00-03:00\",\"duracaoMin\":30,\"pacienteId\":\"patient-fiction\",\"profissionalId\":\"doctor-fiction\",\"tipo\":\"consulta\",\"canal\":\"presencial\",\"status\":\"cancelled\"}"
    await transport.append([
        .init(method: "GET", suffix: "/" + task.requestID, json: cancelled),
        .init(method: "GET", suffix: "/patient-fiction", json: progressPatient)
    ])
    await task.reconcile()
    #expect(task.outcome == .succeeded && task.appointment?.status == "cancelled")
    #expect(store.progress(for: request).title == "Agendamento cancelado")
    #expect(await transport.postCount() == 1)
    #expect(await transport.remaining() == 0)
}
