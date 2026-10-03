import Foundation
import Testing
@testable import AtendeBemCore

private func user(_ roles: [String]) throws -> User {
    let data = try JSONSerialization.data(withJSONObject: ["id": "professional-test", "nome": "Teste", "email": "test@example.invalid", "papeis": roles])
    return try JSONDecoder().decode(User.self, from: data)
}
private func authenticated(_ transport: StubTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"test-only","refreshToken":"test-only","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession()
    return api
}
private func appointmentJSON(_ status: String) -> String {
    """
    {"id":"appointment-test","inicio":"2026-09-30T09:00:00-03:00","duracaoMin":30,"pacienteId":"patient-test","profissionalId":"professional-test","tipo":"consulta","canal":"presencial","status":"\(status)"}
    """
}

@Test func savedFiveTabLayoutMigratesToFourPrimaryTabs() throws {
    let professional = try user(["medico"])
    #expect(WorkspacePolicy.tabs(["today", "agenda", "patients", "lari", "finance", "more", "today"], user: professional) == ["today", "agenda", "patients", "more"])
    #expect(WorkspacePolicy.tabs(["finance", "lari"], user: professional) == ["today", "more"])
}

@Test func receptionCanReachPatientsButCannotPrescribeOrStartConsultation() throws {
    let reception = try user(["recepcao"])
    let appointment = try JSONDecoder().decode(Appointment.self, from: Data(appointmentJSON("confirmed").utf8))
    #expect(WorkspacePolicy.tabs(["patients", "agenda"], user: reception) == ["patients", "agenda", "more"])
    #expect(AppointmentAction.checkIn.allowed(for: appointment, user: reception))
    #expect(!AppointmentAction.start.allowed(for: appointment, user: reception))
    #expect(!reception.canPrescribe)
    #expect(!reception.canIssueDocument)
}

@Test func nursingRegistrationTermAndPrescriptionPermissionsAreDistinct() throws {
    let nurse = try user(["enfermeiro"])
    #expect(nurse.canCreatePatient && nurse.needsNursingRegistrationTerm)
    #expect(!nurse.canEditPatient && !nurse.canPrescribe)
    #expect(try !user(["enfermeiro", "gestor"]).needsNursingRegistrationTerm)
    #expect(try user(["dentista"]).canPrescribe)
}

@Test func ambiguousWriteMustBeReconciledInsteadOfRepeated() {
    #expect(WriteOutcome.afterFailure(URLError(.timedOut)) == .uncertain)
    #expect(WriteOutcome.afterFailure(APIError.http(503)) == .uncertain)
    #expect(WriteOutcome.afterFailure(APIError.invalidResponse) == .uncertain)
    #expect(WriteOutcome.afterFailure(APIError.problem(422, "Campo inválido")) == .ready)
    #expect(!WriteOutcome.succeeded.canSubmit)
}

@Test func arrivalUsesDedicatedCheckInRouteAfterFreshRead() async throws {
    let transport = StubTransport { request in
        if request.httpMethod == "GET" { return (appointmentJSON("confirmed"), 200) }
        #expect(request.url?.path == "/v1/agendamentos/appointment-test/checkin")
        #expect(request.httpMethod == "POST")
        return (appointmentJSON("waiting"), 200)
    }
    let api = try await authenticated(transport)
    let updated = try await AppointmentService(api: api).perform(.checkIn, id: "appointment-test", user: user(["recepcao"]))
    #expect(updated.status == "waiting")
    #expect(await transport.all().count == 2)
}

@Test func staleCompletedAppointmentCannotBeReconfirmed() async throws {
    let transport = StubTransport { _ in (appointmentJSON("completed"), 200) }
    let api = try await authenticated(transport)
    await #expect(throws: APIError.http(409)) {
        try await AppointmentService(api: api).perform(.confirm, id: "appointment-test", user: user(["medico"]))
    }
    #expect(await transport.all().count == 1)
}

@Test func rescheduleRefusesStaleDataAndUnavailableRoleBeforeWriting() async throws {
    let original = try JSONDecoder().decode(Appointment.self, from: Data(appointmentJSON("confirmed").utf8))
    let transport = StubTransport { _ in (appointmentJSON("completed"), 200) }
    let api = try await authenticated(transport)
    await #expect(throws: APIError.http(403)) {
        try await AppointmentService(api: api).reschedule(original, date: .now, duration: 45, user: user(["paciente"]))
    }
    #expect(await transport.all().isEmpty)
    await #expect(throws: APIError.http(409)) {
        try await AppointmentService(api: api).reschedule(original, date: .now, duration: 45, user: user(["recepcao"]))
    }
    #expect(await transport.all().count == 1)
    #expect(await transport.all().allSatisfy { $0.httpMethod == "GET" })
}

@Test func rescheduleSendsNumericDurationWithoutReplacingOtherFields() async throws {
    let transport = StubTransport { request in
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(body.keys) == ["inicio", "duracaoMin"])
        #expect(body["duracaoMin"] as? Int == 45)
        #expect(request.httpMethod == "PATCH")
        return (appointmentJSON("confirmed"), 200)
    }
    let api = try await authenticated(transport)
    let _: Appointment = try await api.patch(["agendamentos", "appointment-test"], body: RescheduleInput(date: .now, duration: 45))
}

@Test func emptySuccessfulResponseIsOnlyAcceptedForEmptyContract() async throws {
    let api = try await authenticated(StubTransport { _ in ("", 204) })
    let _: EmptyResponse = try await api.post(["test-empty"])
    await #expect(throws: APIError.invalidResponse) { let _: Patient = try await api.get(["pacientes", "test"]) }
}

@Test func clinicalSOAPPreservesWebCustomSectionsAndVersionWithoutForce() throws {
    let soap = try JSONDecoder().decode(SOAPNote.self, from: Data(#"{"s":"Relato","exame_especialidade":"Texto adicional"}"#.utf8))
    let input = DraftInput(soap: soap, sections: nil, complaint: nil, codes: [], version: 7)
    let encoded = try JSONEncoder().encode(input)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect((json["soap"] as? [String: String])?["exame_especialidade"] == "Texto adicional")
    #expect(json["versaoBase"] as? Int == 7)
    #expect(json["sobrescreverServidor"] == nil)
}

@Test func unsignedDocumentIsNeverInferredSignedFromEmittedStatus() throws {
    let json = #"{"id":"rx-test","pacienteId":"patient-test","profissionalId":"professional-test","tipo":"comum","itens":[],"status":"emitida","assinada":false,"procedencia":"historico_importado"}"#
    let document = try JSONDecoder().decode(Prescription.self, from: Data(json.utf8))
    #expect(document.assinada == false)
    #expect(document.assinatura == nil)
    #expect(document.procedencia == "historico_importado")
}

@Test func pdfRejectsJSONInsteadOfRenderingInvalidDocument() async throws {
    let api = try await authenticated(StubTransport { _ in ("{}", 200) })
    await #expect(throws: APIError.invalidResponse) { try await api.pdf(["receitas", "test", "pdf"]) }
}

@Test func signedDocumentPDFUsesAuthenticatedRead() async throws {
    let transport = StubTransport { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        #expect(request.httpMethod == "GET")
        return ("%PDF-1.7\nfixture", 200)
    }
    let api = try await authenticated(transport)
    let bytes = try await api.pdf(["receitas", "test", "pdf"])
    #expect(bytes.starts(with: Data("%PDF-".utf8)))
}
