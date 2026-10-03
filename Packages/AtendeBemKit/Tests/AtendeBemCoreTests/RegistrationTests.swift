import Foundation
import Testing
@testable import AtendeBemCore

private func registrationRequest(profession: RegistrationProfession = .medico, planID: String? = "plan-test") throws -> RegistrationRequest {
    try RegistrationRequest(clinicName: " Clínica fictícia ", responsibleName: " Pessoa fictícia ",
        email: " TEST@example.invalid ", password: "Synthetic 123 ", profession: profession,
        professionalRegistration: " Registro fictício ", specialty: " Especialidade de teste ", planID: planID)
}

private func registrationResponse(userID: String = "user-test", clinicID: String = "clinic-test",
                                 tokenUser: String = "user-test", tokenClinic: String = "clinic-test",
                                 planID: String = "plan-test") throws -> String {
    let claims = try JSONEncoder().encode(["sub": tokenUser, "clinicaId": tokenClinic])
        .base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    let value: [String: Any] = ["usuarioId": userID, "clinicaId": clinicID,
        "assinaturaId": "subscription-test", "planoId": planID,
        "accessToken": "synthetic.\(claims).signature", "refreshToken": "synthetic-refresh", "expiraEm": 900]
    return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
}

@Test func publicRegistrationUsesExactPayloadWithoutAuthenticationOrCredentialChanges() async throws {
    let response = try registrationResponse()
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/onboarding")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let bytes = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(body.keys) == ["clinica", "responsavel", "planoId", "origem"])
        #expect(body["origem"] as? String == "ios")
        #expect(body["planoId"] as? String == "plan-test")
        let clinic = try #require(body["clinica"] as? [String: String])
        #expect(clinic == ["nome": "Clínica fictícia"])
        let person = try #require(body["responsavel"] as? [String: String])
        #expect(person == ["nome": "Pessoa fictícia", "email": "test@example.invalid", "senha": "Synthetic 123 ",
            "profissao": "medico", "crm": "Registro fictício", "especialidade": "Especialidade de teste"])
        return (response, 201)
    }
    let client = RegistrationClient(transport: transport)
    let receipt = try await client.register(registrationRequest())
    #expect(receipt.clinicID == "clinic-test")
    #expect(receipt.userID == "user-test")
    #expect(receipt.subscriptionID == "subscription-test")
    #expect(receipt.planID == "plan-test")
    #expect(await client.state == .completed)
    #expect(await transport.count("/v1/auth/refresh") == 0)
    await #expect(throws: RegistrationError.alreadyCompleted) { try await client.register(registrationRequest()) }
    #expect(await transport.count("/v1/onboarding") == 1)
}

@Test(arguments: RegistrationProfession.allCases)
func registrationMapsOnlyTheSelectedProfessionalCouncil(profession: RegistrationProfession) throws {
    let value = try registrationRequest(profession: profession)
    let body = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    let person = try #require(body["responsavel"] as? [String: String])
    let councils: [RegistrationProfession: String] = [.medico: "crm", .fisioterapeuta: "crefito", .dentista: "cro",
        .psicologo: "crp", .fonoaudiologo: "crfa", .nutricionista: "crn"]
    #expect(person["profissao"] == profession.rawValue)
    #expect(Set(person.keys).intersection(["crm", "crefito", "cro", "crp", "crfa", "crn"]) == Set(councils[profession].map { [$0] } ?? []))
    #expect(value.description == "RegistrationRequest(redacted)")
    #expect(!value.debugDescription.contains("Synthetic"))
}

@Test func registrationValidatesUserInputBeforeTransportAndPreservesOptionalFields() throws {
    #expect(throws: RegistrationError.invalidField(.clinicName)) {
        try RegistrationRequest(clinicName: " ", responsibleName: "Pessoa", email: "test@example.invalid", password: "Password123", profession: .medico)
    }
    #expect(throws: RegistrationError.invalidField(.responsibleName)) {
        try RegistrationRequest(clinicName: "Clínica", responsibleName: String(repeating: "x", count: 121), email: "test@example.invalid", password: "Password123", profession: .medico)
    }
    #expect(throws: RegistrationError.invalidField(.email)) {
        try RegistrationRequest(clinicName: "Clínica", responsibleName: "Pessoa", email: "test..name@example.invalid", password: "Password123", profession: .medico)
    }
    #expect(throws: RegistrationError.invalidField(.password)) {
        try RegistrationRequest(clinicName: "Clínica", responsibleName: "Pessoa", email: "test@example.invalid", password: "no-numbers", profession: .medico)
    }
    let request = try RegistrationRequest(clinicName: "Clínica", responsibleName: "Pessoa", email: "test@example.invalid", password: "Password123", profession: .nutricionista)
    let body = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    let person = try #require(body["responsavel"] as? [String: String])
    #expect(body["planoId"] == nil)
    #expect(person["crn"] == nil)
    #expect(person["especialidade"] == nil)
}

@Test(arguments: [400, 401, 403, 422, 429])
func registrationRejectionsDoNotRefreshOrReplay(status: Int) async throws {
    let transport = StubTransport { _ in (#"{"detail":"This response text must not be echoed."}"#, status) }
    let client = RegistrationClient(transport: transport)
    await #expect(throws: RegistrationError.rejected(status)) { try await client.register(registrationRequest()) }
    #expect(await client.state == .ready)
    #expect(await transport.all().count == 1)
}

@Test(arguments: [200, 409, 500, 503])
func registrationAmbiguousServerOutcomesBlockAnotherPost(status: Int) async throws {
    let transport = StubTransport { _ in ("{}", status) }
    let client = RegistrationClient(transport: transport)
    await #expect(throws: RegistrationError.outcomeUnknown) { try await client.register(registrationRequest()) }
    await #expect(throws: RegistrationError.outcomeUnknown) { try await client.register(registrationRequest()) }
    #expect(await client.state == .outcomeUnknown)
    #expect(await transport.all().count == 1)
}

@Test func registrationLostResponseCannotCreateADuplicateClinic() async throws {
    let transport = StubTransport { _ in throw URLError(.timedOut) }
    let client = RegistrationClient(transport: transport)
    await #expect(throws: RegistrationError.outcomeUnknown) { try await client.register(registrationRequest()) }
    await #expect(throws: RegistrationError.outcomeUnknown) { try await client.register(registrationRequest()) }
    #expect(await transport.count("/v1/onboarding") == 1)
}

@Test func registrationConcurrentSubmissionsAreNotRepeated() async throws {
    let gate = ResponseGate()
    let response = try registrationResponse()
    let transport = StubTransport { _ in
        await gate.suspend()
        return (response, 201)
    }
    let client = RegistrationClient(transport: transport)
    let first = Task { try await client.register(registrationRequest()) }
    try await gate.waitForRequest()
    await #expect(throws: RegistrationError.alreadySubmitting) { try await client.register(registrationRequest()) }
    await gate.resume()
    _ = try await first.value
    #expect(await transport.count("/v1/onboarding") == 1)
}

@Test(arguments: ["user", "clinic", "plan", "missing"])
func registrationDoesNotTrustMismatchedOrMalformedSuccess(kind: String) async throws {
    let response: String
    switch kind {
    case "user": response = try registrationResponse(tokenUser: "another-user")
    case "clinic": response = try registrationResponse(tokenClinic: "another-clinic")
    case "plan": response = try registrationResponse(planID: "another-plan")
    default: response = #"{"clinicaId":"clinic-test","usuarioId":"user-test"}"#
    }
    let transport = StubTransport { _ in (response, 201) }
    let client = RegistrationClient(transport: transport)
    await #expect(throws: RegistrationError.outcomeUnknown) { try await client.register(registrationRequest()) }
    #expect(await client.state == .outcomeUnknown)
}

@Test func registrationTrialCopyComesFromThePublicCatalog() async throws {
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/planos")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        return (#"[{"id":"trial14","nome":"Plano de teste","trialDias":14,"semCartao":true,"recursos":[]},{"id":"trial7","nome":"Outro plano","trialDias":7,"semCartao":false,"recursos":["nutricao"]}]"#, 200)
    }
    let client = RegistrationClient(transport: transport)
    let plans = try await client.plans()
    #expect(plans[0].trialDescription == "14 dias para experimentar, sem cartão.")
    #expect(plans[1].trialDescription == "7 dias para experimentar.")
    #expect(await client.state == .ready)
}

@Test(arguments: [#"[{"id":"p","nome":"P","trialDias":-1,"semCartao":true,"recursos":[]}]"#,
    #"[{"id":"p","nome":"P","trialDias":14,"semCartao":true,"recursos":[]},{"id":"p","nome":"P","trialDias":14,"semCartao":true,"recursos":[]}]"#,
    #"[{"id":"p","nome":"P","semCartao":true,"recursos":[]}]"#])
func registrationRejectsAnInvalidTrialCatalog(body: String) async throws {
    let client = RegistrationClient(transport: StubTransport { _ in (body, 200) })
    await #expect(throws: APIError.invalidResponse) { try await client.plans() }
}
