import Foundation
import Testing
@testable import AtendeBemCore

private let expansionPatientJSON = #"{"id":"patient-fiction","nome":"Paciente Fictício","nascimento":"1980-01-01","telefone":"11999990000","email":"patient@example.invalid"}"#
private let expansionUserJSON = #"{"id":"doctor-fiction","nome":"Profissional Fictício","email":"doctor@example.invalid","papeis":["medico"]}"#
private let expansionCatalogJSON = ##"{"escopo":"clinica","itens":[{"id":"consulta","rotulo":"Consulta","cor":"#000000","ordem":0,"ativo":true,"sistemico":true,"contaComoRetorno":false}]}"##
private let expansionSlotJSON = #"[{"inicio":"2030-01-02T14:00:00-03:00","duracaoMin":30}]"#
private let expansionAppointmentJSON = #"{"id":"$ID","inicio":"2030-01-02T14:00:00-03:00","duracaoMin":30,"pacienteId":"patient-fiction","profissionalId":"doctor-fiction","tipo":"consulta","canal":"presencial","status":"scheduled"}"#
private let expansionExamJSON = #"{"id":"exam-fiction","pacienteId":"patient-fiction","pacienteNome":"Paciente Fictício","medicoId":"doctor-fiction","tipo":"laboratorial","itens":[{"descricao":"Exame fictício"}],"status":"solicitado","criadoEm":"2030-01-01T00:00:00Z","origem":"solicitada"}"#
private let expansionTimelineJSON = #"{"pacienteId":"patient-fiction","eventos":[],"paginacao":{"page":1,"perPage":25,"total":0,"totalPaginas":0},"avisos":[]}"#

private actor ExpansionTransport: HTTPTransport {
    struct Step: Sendable { let method: String; let suffix: String; let json: String; var status = 200; var lost = false }
    var steps: [Step]
    var requests: [URLRequest] = []
    var observer: (@Sendable (URLRequest) async -> Void)?
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        await observer?(request)
        guard !steps.isEmpty else { Issue.record("Unexpected LARI task request: \(request.url!.path)"); throw APIError.invalidResponse }
        let step = steps.removeFirst()
        #expect(request.httpMethod == step.method); #expect(request.url!.path.hasSuffix(step.suffix))
        if step.lost { throw URLError(.networkConnectionLost) }
        var json = step.json
        if let body = request.httpBody, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let id = object["id"] as? String {
            json = json.replacingOccurrences(of: "$ID", with: id)
        }
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil, headerFields: nil)!)
    }
    func all() -> [URLRequest] { requests }
    func append(_ steps: [Step]) { self.steps.append(contentsOf: steps) }
    func observe(_ action: @escaping @Sendable (URLRequest) async -> Void) { observer = action }
}
private func expansionUser(_ role: String = "medico") throws -> User {
    try JSONDecoder().decode(User.self, from: Data(expansionUserJSON.replacingOccurrences(of: "medico", with: role).utf8))
}
private func expansionPatient() throws -> Patient { try JSONDecoder().decode(Patient.self, from: Data(expansionPatientJSON.utf8)) }
private func expansionAPI(_ transport: ExpansionTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic","refreshToken":"synthetic","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession(); return api
}
private let expansionNow = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01T00:00:00Z
@MainActor private func appointmentModel(_ transport: ExpansionTransport, role: String = "medico") async throws -> LARIAppointmentTask {
    let api = try await expansionAPI(transport)
    return LARIAppointmentTask(command: "Agendar consulta para Paciente Fictício em 02/01/2030 às 14h", api: api, context: await api.requestContextID(), user: try expansionUser(role), now: { expansionNow })
}
private let appointmentPreparation: [ExpansionTransport.Step] = [
    .init(method:"GET", suffix:"/usuarios", json:"[" + expansionUserJSON + "]"),
    .init(method:"GET", suffix:"/tipos-atendimento", json:expansionCatalogJSON),
    .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
    .init(method:"GET", suffix:"/disponibilidade", json:expansionSlotJSON)
]
@MainActor private func prepareAppointment(_ task: LARIAppointmentTask) async throws {
    await task.loadOptions(); await task.selectPatient(try expansionPatient())
    task.professionalID = "doctor-fiction"; task.typeID = "consulta"; task.channel = "presencial"
    task.day = try #require(ClinicClock.parseInstant("2030-01-02T14:00:00-03:00"))
    await task.loadAvailability(); task.selectSlot(try #require(task.slots.first)); task.reviewed = true
}
private let appointmentPreflight: [ExpansionTransport.Step] = [
    .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
    .init(method:"GET", suffix:"/disponibilidade", json:expansionSlotJSON),
    .init(method:"GET", suffix:"/tipos-atendimento", json:expansionCatalogJSON)
]

@Test func appointmentCommandRequiresExplicitDateAndTimeAndNeverResolvesPatientIdentity() {
    let parsed = LARIAppointmentCommand(text:"Agendar consulta para Paciente Fictício em 02/01/2030 às 14h por 30 minutos", now:expansionNow)
    #expect(parsed.patientQuery == "Paciente Fictício")
    #expect(parsed.requestedStart == ClinicClock.parseInstant("2030-01-02T14:00:00-03:00"))
    #expect(parsed.requestedDuration == 30)
    #expect(LARIAppointmentCommand(text:"Agendar para Paciente Fictício às 14h", now:expansionNow).requestedStart == nil)
    #expect(LARIAppointmentCommand(text:"Agendar em 31/02/2030 às 14h", now:expansionNow).requestedStart == nil)
    #expect(LARIAppointmentCommand(text:"Agendar amanhã às 25h", now:expansionNow).requestedStart == nil)
}

@Test(arguments: [
    ("Paciente Fictício", "Paciente Fictício"),
    ("o Paciente Fictício", "Paciente Fictício"),
    ("a Paciente Fictícia", "Paciente Fictícia"),
    ("PACIENTE FICTÍCIO", "PACIENTE FICTÍCIO"),
    ("João Gonçalves de Sá", "João Gonçalves de Sá"),
    ("a Érica D’Ávila", "Érica D’Ávila")
])
func appointmentAndExamPatientSearchPreservesNamesAndAccents(input: String, expected: String) {
    let appointment = LARIAppointmentCommand(text: "Agendar consulta para \(input) amanhã às 14h", now: expansionNow)
    let exam = LARIExamCommand(text: "Solicitar exames de Exame fictício para \(input)")
    #expect(appointment.patientQuery == expected)
    #expect(exam.patientQuery == expected)
}

@Test @MainActor func appointmentRequiresSelectionAndReviewAndPerformsNoWriteDuringPreparation() async throws {
    let transport = ExpansionTransport(appointmentPreparation), task = try await appointmentModel(transport)
    #expect(await transport.all().isEmpty); #expect(!task.canCreate)
    try await prepareAppointment(task)
    #expect(task.canCreate); #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
    task.channel = "teleconsulta"; #expect(!task.reviewed && !task.canCreate)
}

@Test @MainActor func appointmentUnavailableSlotNeverReachesCreate() async throws {
    let transport = ExpansionTransport(appointmentPreparation + [
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/disponibilidade", json:"[]")])
    let task = try await appointmentModel(transport); try await prepareAppointment(task); await task.create()
    #expect(!task.canCreate); #expect(task.appointment == nil)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test @MainActor func appointmentCreationUsesRetainedIDAndValidatesReturnedIdentity() async throws {
    let transport = ExpansionTransport(appointmentPreparation + appointmentPreflight + [.init(method:"POST", suffix:"/agendamentos", json:expansionAppointmentJSON)])
    let task = try await appointmentModel(transport); try await prepareAppointment(task); await task.create()
    #expect(task.outcome == .succeeded); #expect(task.appointment?.id == task.requestID)
    let writes = await transport.all().filter { $0.httpMethod == "POST" }
    #expect(writes.count == 1)
    let body = try #require(writes.first?.httpBody)
    let value = try #require(JSONSerialization.jsonObject(with:body) as? [String:Any])
    #expect(value["id"] as? String == task.requestID); #expect(value["duracaoMin"] as? Int == 30)
}

@Test @MainActor func lostAppointmentResponseReconcilesOnlyItsOriginalIDWithoutRetryingWrite() async throws {
    let transport = ExpansionTransport(appointmentPreparation + appointmentPreflight + [.init(method:"POST", suffix:"/agendamentos", json:"", lost:true)])
    let task = try await appointmentModel(transport); try await prepareAppointment(task); await task.create(); await task.create()
    #expect(task.outcome == .uncertain)
    await transport.append([.init(method:"GET", suffix:"/" + task.requestID, json:expansionAppointmentJSON.replacingOccurrences(of:"$ID", with:task.requestID)), .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON)])
    await task.reconcile()
    #expect(task.outcome == .succeeded)
    #expect(await transport.all().filter { $0.httpMethod == "POST" }.count == 1)
}

@Test @MainActor func appointmentUnknownReconciliationStaysBlocked() async throws {
    let transport = ExpansionTransport(appointmentPreparation + appointmentPreflight + [.init(method:"POST", suffix:"/agendamentos", json:"", lost:true)])
    let task = try await appointmentModel(transport); try await prepareAppointment(task); await task.create()
    await transport.append([.init(method:"GET", suffix:"/" + task.requestID, json:"{}", status:404)])
    await task.reconcile(); #expect(task.outcome == .uncertain); #expect(!task.canCreate)
}

@Test @MainActor func appointmentInvalidatedTaskCannotCreate() async throws {
    let transport = ExpansionTransport(appointmentPreparation), task = try await appointmentModel(transport)
    try await prepareAppointment(task); task.invalidate(); await task.create()
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" }); #expect(task.lookup.patient == nil)
}

@Test @MainActor func managerAloneCannotScheduleThroughLARI() async throws {
    let transport = ExpansionTransport([]), task = try await appointmentModel(transport, role:"gestor")
    await task.loadOptions(); await task.create(); #expect(await transport.all().isEmpty)
}

@MainActor private func examModel(_ transport: ExpansionTransport, role: String = "medico") async throws -> LARIExamRequestTask {
    let api = try await expansionAPI(transport)
    return LARIExamRequestTask(command:"Solicitar exames de Exame fictício para Paciente Fictício", api:api, context:await api.requestContextID(), user:try expansionUser(role))
}
@MainActor private func prepareExam(_ task: LARIExamRequestTask) async throws {
    await task.selectPatient(try expansionPatient()); task.type = "laboratorial"; task.reviewed = true
}

@Test func examCommandCopiesOnlyExplicitItemsWithoutInventingCodesOrIndication() {
    let parsed = LARIExamCommand(text:"Solicite exames de Exame fictício A, Exame fictício B para Paciente Fictício")
    #expect(parsed.patientQuery == "Paciente Fictício")
    #expect(parsed.proposedItems == ["Exame fictício A", "Exame fictício B"])
    #expect(LARIExamCommand(text:"Solicite os exames necessários para Paciente Fictício").proposedItems.isEmpty)
}

@Test @MainActor func examNoCreationWithoutFinalReviewAndCreationDoesNotRequestDelivery() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON), .init(method:"POST", suffix:"/exames", json:expansionExamJSON)])
    let task = try await examModel(transport); await task.create(); #expect(await transport.all().isEmpty)
    try await prepareExam(task); #expect(task.canCreate); await task.create()
    #expect(task.document?.id == "exam-fiction"); #expect(task.outcome == .succeeded)
    #expect(await transport.all().filter { $0.httpMethod == "POST" }.count == 1)
    #expect(await transport.all().allSatisfy { !$0.url!.path.hasSuffix("/enviar") && !$0.url!.path.hasSuffix("/assinar") })
}

@Test @MainActor func examLostCreateResponseNeverRetriesAndSimilarRecordIsNotTreatedAsProof() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON), .init(method:"POST", suffix:"/exames", json:"", lost:true),
        .init(method:"GET", suffix:"/exames", json:"[" + expansionExamJSON + "]")])
    let task = try await examModel(transport); try await prepareExam(task); await task.create(); await task.create(); await task.consultExistingRequests()
    #expect(task.outcome == .uncertain); #expect(task.document == nil); #expect(task.existingRequests.count == 1)
    #expect(await transport.all().filter { $0.httpMethod == "POST" }.count == 1)
}

@Test @MainActor func examChangedPatientStopsBeforeCreationAndRequiresAnotherReview() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON.replacingOccurrences(of:"11999990000", with:"11888880000"))])
    let task = try await examModel(transport); try await prepareExam(task); await task.create()
    #expect(!task.reviewed); #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test @MainActor func examReceptionCannotCreateOrSend() async throws {
    let transport = ExpansionTransport([]), task = try await examModel(transport, role:"recepcao")
    try await prepareExam(task); await task.create(); await task.send()
    #expect(!task.canCreate && !task.canSend); #expect(await transport.all().isEmpty)
}

@Test @MainActor func examResultForDifferentPatientRemainsUncertainAndHidden() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON), .init(method:"POST", suffix:"/exames", json:expansionExamJSON.replacingOccurrences(of:"patient-fiction", with:"wrong-patient"))])
    let task = try await examModel(transport); try await prepareExam(task); await task.create()
    #expect(task.outcome == .uncertain); #expect(task.document == nil); #expect(task.lookup.patient == nil)
}

@Test @MainActor func historySelectionReadsSourcesWithoutGeneratingAIOrWriting() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/ficha", json:expansionTimelineJSON), .init(method:"GET", suffix:"/antecedentes", json:"{}"), .init(method:"GET", suffix:"/alergias", json:"[]")])
    let api = try await expansionAPI(transport)
    let task = LARIHistoryTask(command:"Consultar histórico do paciente Paciente Fictício", api:api, context:await api.requestContextID(), user:try expansionUser())
    #expect(await transport.all().isEmpty); await task.selectPatient(try expansionPatient())
    #expect(task.timeline != nil && task.allergies?.isEmpty == true && task.antecedents != nil)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" && !$0.url!.path.hasSuffix("resumo-prontuario") })
}

@Test @MainActor func historyUnavailableSourceIsNotRepresentedAsEmptyData() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/ficha", json:expansionTimelineJSON), .init(method:"GET", suffix:"/antecedentes", json:"{}", status:503), .init(method:"GET", suffix:"/alergias", json:"[]")])
    let api = try await expansionAPI(transport)
    let task = LARIHistoryTask(command:"Histórico do paciente Fictício", api:api, context:await api.requestContextID(), user:try expansionUser())
    await task.selectPatient(try expansionPatient())
    #expect(task.antecedents == nil); #expect(task.sourceWarnings.count == 1); #expect(task.timeline != nil)
}

@Test @MainActor func historyDeniedSourceClearsEarlierClinicalData() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/ficha", json:expansionTimelineJSON), .init(method:"GET", suffix:"/antecedentes", json:"{}", status:403)])
    let api = try await expansionAPI(transport)
    let task = LARIHistoryTask(command:"Histórico do paciente Fictício", api:api, context:await api.requestContextID(), user:try expansionUser())
    await task.selectPatient(try expansionPatient())
    #expect(task.lookup.patient == nil && task.timeline == nil && task.allergies == nil); #expect(task.error != nil)
}

private let expansionSignedExamJSON = String(expansionExamJSON.dropLast()) + #", "assinatura":{"padrao":"ICP-Brasil","certificado":"certificate-fiction","carimboTempo":"2030-01-01T00:00:00Z","validador":"https://example.invalid/verify","codigoVerificacao":"CFM0000000"}}"#
private let examSignedPreparation: [ExpansionTransport.Step] = [
    .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
    .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
    .init(method:"POST", suffix:"/exames", json:expansionSignedExamJSON),
    .init(method:"GET", suffix:"/exam-fiction", json:expansionSignedExamJSON),
    .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON)
]
private let examSendPreflight: [ExpansionTransport.Step] = [
    .init(method:"GET", suffix:"/exam-fiction", json:expansionSignedExamJSON),
    .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON)
]

@Test(arguments: ["cancelado", "cancelada"]) @MainActor
func cancelledExamNeverOffersOrRequestsDelivery(status: String) async throws {
    let cancelled = expansionSignedExamJSON.replacingOccurrences(of: #""status":"solicitado""#, with: "\"status\":\"\(status)\"")
    let transport = ExpansionTransport([
        .init(method: "GET", suffix: "/patient-fiction", json: expansionPatientJSON),
        .init(method: "GET", suffix: "/patient-fiction", json: expansionPatientJSON),
        .init(method: "POST", suffix: "/exames", json: cancelled),
        .init(method: "GET", suffix: "/exam-fiction", json: cancelled),
        .init(method: "GET", suffix: "/patient-fiction", json: expansionPatientJSON)
    ])
    let task = try await examModel(transport)
    try await prepareExam(task); await task.create(); await task.prepareDelivery()
    task.sendByWhatsApp = true; task.deliveryReviewed = true
    #expect(task.document?.status == status && !task.canSend)
    await task.send()
    #expect(await transport.all().allSatisfy { !$0.url!.path.hasSuffix("/enviar") })
}

@Test @MainActor func examCancellationAfterReviewStopsBeforeDeliveryPOST() async throws {
    let cancelled = expansionSignedExamJSON.replacingOccurrences(of: #""status":"solicitado""#, with: #""status":"cancelado""#)
    let transport = ExpansionTransport(examSignedPreparation + [
        .init(method: "GET", suffix: "/exam-fiction", json: cancelled)
    ])
    let task = try await examModel(transport)
    try await prepareExamDelivery(task)
    await task.send()
    #expect(task.document?.status == "cancelado")
    #expect(!task.deliveryReviewed && !task.canSend)
    #expect(task.deliveryError?.contains("cancelamento") == true)
    #expect(task.deliveryOutcome == .ready)
    #expect(await transport.all().allSatisfy { !$0.url!.path.hasSuffix("/enviar") })
}

@Test @MainActor func examCancellationInSignatureReviewBlocksAnOlderActiveDeliverySnapshot() async throws {
    let cancelled = expansionSignedExamJSON.replacingOccurrences(of: #""status":"solicitado""#, with: #""status":"cancelada""#)
    let transport = ExpansionTransport(examSignedPreparation + [
        .init(method: "GET", suffix: "/exames", json: "[\(cancelled)]")
    ])
    let task = try await examModel(transport)
    try await prepareExamDelivery(task)
    let review = try #require(task.signatureReview)
    await review.load()
    #expect(task.document?.status == "solicitado" && review.document?.status == "cancelada")
    #expect(task.deliveryOutcome == .ready && !task.canSend)
    await task.send()
    #expect(await transport.all().allSatisfy { !$0.url!.path.hasSuffix("/enviar") })
}

@MainActor private func prepareExamDelivery(_ task: LARIExamRequestTask) async throws {
    try await prepareExam(task); await task.create(); await task.prepareDelivery()
    task.sendByWhatsApp = true; task.deliveryReviewed = true
    #expect(task.canSend)
}

@Test @MainActor func examDeliveryUsesSeparateExplicitGestureAndDoesNotRepeatAfterQueueConfirmation() async throws {
    let transport = ExpansionTransport(examSignedPreparation + examSendPreflight + [
        .init(method:"POST", suffix:"/enviar", json:#"{"status":"enfileirado","solicitacaoId":"exam-fiction","canais":["whatsapp"]}"#, status:202)])
    let task = try await examModel(transport); try await prepareExamDelivery(task)
    #expect(await transport.all().filter { $0.url!.path.hasSuffix("/enviar") }.isEmpty)
    await task.send(); await task.send()
    #expect(task.deliveryOutcome == .succeeded)
    let sends = await transport.all().filter { $0.url!.path.hasSuffix("/enviar") }
    #expect(sends.count == 1)
    let body = try #require(sends.first?.httpBody)
    let value = try #require(JSONSerialization.jsonObject(with: body) as? [String:Any])
    #expect(value["canais"] as? [String] == ["whatsapp"])
}

@Test @MainActor func examLostDeliveryRemainsUncertainAndCannotBeResentByReopeningReview() async throws {
    let transport = ExpansionTransport(examSignedPreparation + examSendPreflight + [.init(method:"POST", suffix:"/enviar", json:"", lost:true)])
    let task = try await examModel(transport); try await prepareExamDelivery(task); await task.send()
    #expect(task.deliveryOutcome == .uncertain)
    await transport.append([.init(method:"GET", suffix:"/exam-fiction", json:expansionSignedExamJSON), .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON)])
    await task.prepareDelivery(); task.deliveryReviewed = true; await task.send()
    #expect(task.deliveryOutcome == .uncertain && !task.canSend)
    #expect(await transport.all().filter { $0.url!.path.hasSuffix("/enviar") }.count == 1)
}

@Test @MainActor func examChangedDeliveryContactStopsBeforeSendAndShowsFreshContactForReview() async throws {
    let transport = ExpansionTransport(examSignedPreparation + [.init(method:"GET", suffix:"/exam-fiction", json:expansionSignedExamJSON),
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON.replacingOccurrences(of:"11999990000", with:"11888880000"))])
    let task = try await examModel(transport); try await prepareExamDelivery(task); await task.send()
    #expect(task.deliveryOutcome == .ready && !task.deliveryReviewed && !task.canSend)
    #expect(task.delivery?.phone == "11888880000")
    #expect(await transport.all().filter { $0.url!.path.hasSuffix("/enviar") }.isEmpty)
}

@Test @MainActor func examWithoutConfirmedSignatureCannotRequestDelivery() async throws {
    let steps = examSignedPreparation.map { ExpansionTransport.Step(method:$0.method, suffix:$0.suffix, json:$0.json.replacingOccurrences(of:expansionSignedExamJSON, with:expansionExamJSON)) }
    let transport = ExpansionTransport(steps), task = try await examModel(transport)
    try await prepareExam(task); await task.create(); await task.prepareDelivery()
    task.sendByWhatsApp = true; task.deliveryReviewed = true; await task.send()
    #expect(!task.canSend)
    #expect(await transport.all().filter { $0.url!.path.hasSuffix("/enviar") }.isEmpty)
}

@Test @MainActor func examCommandNeverDropsItemsOverServiceLimits() async throws {
    let descriptions = (1...51).map { "Exame fictício \($0)" }
    let command = "Solicitar exames de " + descriptions.joined(separator:", ") + " para Paciente Fictício"
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON)])
    let api = try await expansionAPI(transport)
    let task = LARIExamRequestTask(command:command, api:api, context:await api.requestContextID(), user:try expansionUser())
    try await prepareExam(task)
    #expect(task.items.map(\.descricao) == descriptions)
    #expect(task.itemValidationMessage != nil && !task.canCreate)
    await task.create(); #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
    task.removeItem(at:50); task.reviewed = true
    #expect(task.canCreate)
    let longDescription = String(repeating:"A", count:501)
    #expect(LARIExamCommand(text:"Solicitar exame de \(longDescription)").proposedItems == [longDescription])
    task.updateItemDescription(at:0, text:longDescription); task.reviewed = true
    #expect(task.items[0].descricao == longDescription && !task.canCreate)
    task.updateItemDescription(at:0, text:"Exame revisado"); task.reviewed = true
    #expect(task.canCreate)
}

@Test @MainActor func examContextChangedDuringPreflightCannotCreateOrKeepPatientData() async throws {
    let transport = ExpansionTransport([.init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON),
        .init(method:"GET", suffix:"/patient-fiction", json:expansionPatientJSON)])
    let api = try await expansionAPI(transport)
    let task = LARIExamRequestTask(command:"Solicitar exames de Exame fictício para Paciente Fictício", api:api, context:await api.requestContextID(), user:try expansionUser())
    try await prepareExam(task)
    await transport.observe { _ in try? await api.logout() }
    await task.create()
    #expect(task.outcome == .ready && task.lookup.patient == nil)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}
