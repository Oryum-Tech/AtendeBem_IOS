import Foundation
import Testing
@testable import AtendeBemCore

private let summaryRoute = "/v1/pacientes/patient-fiction/resumo-prontuario"
private let summaryFixture = #"{"pacienteId":"patient-fiction","geradoEm":"2026-10-02T12:00:00-03:00","atividade":{"totalEvolucoes":24,"naoAssinadas":1,"primeiraEm":"2020-01-02T12:00:00-03:00","ultimaEm":"2026-10-01T12:00:00-03:00"},"fatos":[{"ref":"f1","categoria":"medicacao","rotulo":"Medicação fictícia","detalhe":"50 mg — dado sintético","data":"2026-10-01","fonte":{"servico":"prontuario","tabela":"medicacoes_uso","id":"med-fiction"}}],"trechos":[{"ref":"t1","secaoId":"s","secaoTitulo":"Relato","texto":"Texto sintético original.\n  Preservar espaços e pontuação!","data":"2026-10-01T12:00:00-03:00","profissionalId":"author-fiction","assinado":false,"tipo":"consulta","fonte":{"servico":"prontuario","tabela":"evolucoes","id":"evo-fiction"}}],"narrativa":{"frases":[{"texto":"Medicação fictícia 50 mg.","refs":["f1"],"fontes":[{"servico":"prontuario","tabela":"medicacoes_uso","id":"med-fiction"}]}]},"narrativaIndisponivel":null,"disclaimer":"Conteúdo sintético. Exige revisão profissional.","geradoPorIa":true,"registroClinico":false}"#

private func summaryBody(_ mutate: (inout [String: Any]) -> Void) throws -> String {
    var object = try #require(JSONSerialization.jsonObject(with: Data(summaryFixture.utf8)) as? [String: Any])
    mutate(&object)
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}
private func summaryDecoded(_ value: String = summaryFixture) throws -> LariSummaryResponse {
    try JSONDecoder().decode(LariSummaryResponse.self, from: Data(value.utf8))
}
private func summaryUser(_ roles: [String] = ["medico"], id: String = "author-fiction") throws -> User {
    try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id": id, "nome": "Pessoa fictícia", "email": "fixture@example.invalid", "papeis": roles]))
}
private func summaryAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession()
    return api
}
@MainActor private func summarySession(_ api: APIClient) async -> LariSummarySession {
    LariSummarySession(api: api, context: await api.requestContextID(), patientID: "patient-fiction", userID: "author-fiction")
}

@Test func lariSummaryRetainsOriginalFactsExcerptsAnchorsAndPartialCounts() throws {
    let value = try summaryDecoded()
    try value.validate(patientID: "patient-fiction")
    #expect(value.hasMatchedNarrative)
    let sentence = try #require(value.narrativa?.frases.first)
    #expect(value.facts(for: sentence)?.first == value.fatos.first)
    #expect(value.trechos[0].texto == "Texto sintético original.\n  Preservar espaços e pontuação!")
    #expect(!value.trechos[0].assinado)
    #expect(value.fatos[0].data == "2026-10-01")
    #expect(value.atividade.totalEvolucoes == 24 && value.returnedEvolutionCount == 1)
    #expect(value.narrativeNotice == nil)
}

@Test func lariSummaryRejectsWrongPatientMissingProvenanceFlagsAndDuplicateRefs() throws {
    for body in [try summaryBody { $0["pacienteId"] = "different-fiction" },
                 try summaryBody { $0["geradoPorIa"] = false },
                 try summaryBody { $0["registroClinico"] = true },
                 try summaryBody { $0["geradoEm"] = "invalid" },
                 try summaryBody { $0["disclaimer"] = " " },
                 try summaryBody { $0["fatos"] = [] },
                 try summaryBody { object in var facts = object["fatos"] as! [[String: Any]]; facts.append(facts[0]); object["fatos"] = facts }] {
        let value = try summaryDecoded(body)
        if value.fatos.isEmpty {
            try value.validate(patientID: "patient-fiction")
            #expect(!value.hasMatchedNarrative)
        } else {
            #expect(throws: LariSummaryFailure.invalidResponse) { try value.validate(patientID: "patient-fiction") }
        }
    }
}

@Test func lariSummaryRejectsInvalidSourceButRetainsUnknownTableAsLiteralMetadata() throws {
    let unknown = try summaryDecoded(summaryFixture.replacingOccurrences(of: "medicacoes_uso", with: "nova_tabela"))
    try unknown.validate(patientID: "patient-fiction")
    #expect(unknown.hasMatchedNarrative)
    #expect(unknown.fatos[0].fonte.title == "Origem: nova_tabela")
    for body in [summaryFixture.replacingOccurrences(of: #""servico":"prontuario""#, with: #""servico":"outra-fonte""#),
                 summaryFixture.replacingOccurrences(of: #""id":"med-fiction""#, with: #""id":" ""#)] {
        let value = try summaryDecoded(body)
        #expect(throws: LariSummaryFailure.invalidResponse) { try value.validate(patientID: "patient-fiction") }
    }
}

@Test func lariSummaryUnmatchedNarrativeIsHiddenWithoutLosingSources() throws {
    let variants: [(inout [String: Any]) -> Void] = [
        { $0["refs"] = ["absent"] }, { $0["refs"] = [] }, { $0["refs"] = ["f1", "f1"] },
        { $0["fontes"] = [] }, { $0["texto"] = " " },
        { $0["fontes"] = [["servico": "prontuario", "tabela": "medicacoes_uso", "id": "wrong-id"]] }
    ]
    for variant in variants {
        let body = try summaryBody { object in
            var narrative = object["narrativa"] as! [String: Any]
            var sentences = narrative["frases"] as! [[String: Any]]
            variant(&sentences[0]); narrative["frases"] = sentences; object["narrativa"] = narrative
        }
        let value = try summaryDecoded(body)
        try value.validate(patientID: "patient-fiction")
        #expect(!value.hasMatchedNarrative)
        #expect(value.narrativeNotice?.contains("ocultada") == true)
        #expect(value.fatos.count == 1 && value.trechos.count == 1)
    }
}

@Test func lariSummaryUnavailableReasonsRemainDistinctWithFactsIntact() throws {
    var notices = Set<String>()
    for reason in ["sem-fatos", "modelo-indisponivel", "nao-verificada", "future-reason"] {
        let value = try summaryDecoded(summaryBody { $0["narrativa"] = NSNull(); $0["narrativaIndisponivel"] = ["motivo": reason] })
        try value.validate(patientID: "patient-fiction")
        #expect(!value.hasMatchedNarrative)
        #expect(value.fatos.count == 1 && value.trechos.count == 1)
        notices.insert(try #require(value.narrativeNotice))
    }
    #expect(notices.count == 4)
}

@Test func lariSummaryClinicalRolesDoNotTreatAdminReceptionOrWildcardAsCare() throws {
    for role in User.careRoles { #expect(LariSummaryPolicy.canGenerate(try summaryUser([role]))) }
    for roles in [["recepcao"], ["admin"], ["gestor"], ["*"], []] {
        #expect(!LariSummaryPolicy.canGenerate(try summaryUser(roles)))
    }
    #expect(LariSummaryPolicy.canGenerate(try summaryUser(["admin", "medico"])))
}

@Test @MainActor func lariSummaryOpeningAndMissingConsentDoNotGenerateOrFetchAnything() async throws {
    let transport = StubTransport { _ in (summaryFixture, 200) }
    let session = await summarySession(try await summaryAPI(transport))
    #expect(session.phase == .ready && session.summary == nil && !session.hasRequested)
    await session.generate(patientID: "patient-fiction", user: try summaryUser())
    #expect(session.failure as? LariSummaryFailure == .consentRequired)
    #expect(await transport.all().isEmpty)
}

@Test @MainActor func lariSummaryInvalidPatientOrRoleCannotReachTransport() async throws {
    for (patient, user) in [("wrong", try summaryUser()), ("patient-fiction", try summaryUser(["recepcao"])),
                            ("patient-fiction", try summaryUser(id: "other-user"))] {
        let transport = StubTransport { _ in (summaryFixture, 200) }
        let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
        await session.generate(patientID: patient, user: user)
        #expect(session.phase == .expired && session.summary == nil)
        #expect(await transport.all().isEmpty)
    }
}

@Test @MainActor func lariSummaryExplicitActionMakesSingleGETWithoutBodyAndNoClinicalWrites() async throws {
    let transport = StubTransport { _ in (summaryFixture, 200) }
    let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
    await session.generate(patientID: "patient-fiction", user: try summaryUser())
    #expect(session.phase == .reviewing && session.summary?.hasMatchedNarrative == true)
    let requests = await transport.all(); #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.url?.path == summaryRoute && request.httpMethod == "GET" && request.httpBody == nil)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access")
    session.invalidate()
    let reopened = await summarySession(try await summaryAPI(transport))
    #expect(reopened.summary == nil && !reopened.agreedToProcessing && !reopened.hasRequested)
    #expect(await transport.all().count == 1)
}

@Test @MainActor func lariSummary503CannotBecomeAnEmptyMedicalHistoryOrReplay() async throws {
    let transport = StubTransport { _ in ("{}", 503) }
    let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
    await session.generate(patientID: "patient-fiction", user: try summaryUser())
    #expect(session.failure as? LariSummaryFailure == .sourceUnavailable)
    #expect(session.summary == nil && session.phase == .ready && !session.agreedToProcessing)
    #expect(await transport.all().count == 1)
}

@Test @MainActor func lariSummaryTimeoutDoesNotReplayAndNeedsConsentForAnotherAction() async throws {
    let transport = StubTransport { _ in throw URLError(.timedOut) }
    let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
    await session.generate(patientID: "patient-fiction", user: try summaryUser())
    #expect(session.failure != nil && session.summary == nil && !session.agreedToProcessing)
    await session.generate(patientID: "patient-fiction", user: try summaryUser())
    #expect(await transport.all().count == 1)
}

@Test @MainActor func lariSummary401WaitsForSeparateSessionCheckWithoutReplayingGeneration() async throws {
    let transport = StubTransport { request in
        switch request.url?.path {
        case summaryRoute: return ("{}", 401)
        case "/v1/me":
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access" { return ("{}", 401) }
            return (#"{"id":"author-fiction","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["medico"]}"#, 200)
        case "/v1/auth/refresh": return (#"{"accessToken":"synthetic-renewed","refreshToken":"synthetic-renewed-refresh","expiraEm":900}"#, 200)
        default: Issue.record("Unexpected route"); return ("{}", 500)
        }
    }
    let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
    await session.generate(patientID: "patient-fiction", user: try summaryUser())
    #expect(session.phase == .sessionRejected)
    #expect(await transport.all().count == 1)
    await session.checkSession()
    #expect(session.phase == .ready && session.failure as? LariSummaryFailure == .sessionChecked)
    #expect(!session.agreedToProcessing && session.summary == nil)
    #expect(await transport.count(summaryRoute) == 1)
    #expect(await transport.count("/v1/auth/refresh") == 1)
}

@Test @MainActor func lariSummarySessionRecoveryRejectsChangedUserOrClinicalPermission() async throws {
    for body in [#"{"id":"other-user","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["medico"]}"#,
                 #"{"id":"author-fiction","nome":"Pessoa fictícia","email":"fixture@example.invalid","papeis":["admin"]}"#] {
        let transport = StubTransport { request in request.url?.path == summaryRoute ? ("{}", 401) : (body, 200) }
        let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
        await session.generate(patientID: "patient-fiction", user: try summaryUser()); await session.checkSession()
        #expect(session.phase == .expired && session.summary == nil)
        #expect(session.failure as? LariSummaryFailure == .permissionDenied)
        #expect(await transport.count(summaryRoute) == 1)
    }
}

@Test @MainActor func lariSummaryLocalContextInvalidationRejectsLateResponseWithoutAPIEpochChange() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { _ in await gate.suspend(); return (summaryFixture, 200) }
    let api = try await summaryAPI(transport), context = await api.requestContextID()
    let session = await summarySession(api); session.agreedToProcessing = true
    let pending = Task { await session.generate(patientID: "patient-fiction", user: try summaryUser()) }
    try await gate.waitForRequest(); session.invalidate()
    await gate.resume(); try await pending.value
    #expect(await api.requestContextID() == context)
    #expect(session.phase == .expired && session.summary == nil && !session.agreedToProcessing)
}

@Test @MainActor func lariSummaryLogoutAndConsentRevocationDiscardLateResponse() async throws {
    for logout in [true, false] {
        let gate = ResponseGate()
        let transport = StubTransport { _ in await gate.suspend(); return (summaryFixture, 200) }
        let api = try await summaryAPI(transport), session = await summarySession(api)
        session.agreedToProcessing = true
        let pending = Task { await session.generate(patientID: "patient-fiction", user: try summaryUser()) }
        try await gate.waitForRequest()
        if logout { try await api.logout() } else { session.agreedToProcessing = false }
        await gate.resume(); try await pending.value
        #expect(session.summary == nil && !session.agreedToProcessing)
        #expect(session.phase == (logout ? .expired : .ready))
        #expect(await transport.all().count == 1)
    }
}

@Test @MainActor func lariSummaryStopWaitingDoesNotCancelRemoteOrAcceptLateContent() async throws {
    let gate = ResponseGate()
    let transport = StubTransport { _ in await gate.suspend(); return (summaryFixture, 200) }
    let session = await summarySession(try await summaryAPI(transport)); session.agreedToProcessing = true
    let pending = Task { await session.generate(patientID: "patient-fiction", user: try summaryUser()) }
    try await gate.waitForRequest(); session.stopWaiting()
    await gate.resume(); try await pending.value
    #expect(session.summary == nil && session.phase == .ready)
    #expect(session.failure as? LariSummaryFailure == .interrupted)
    #expect(await transport.all().count == 1)
}

@Test @MainActor func lariSummaryOldContextNeverReachesGeneratingRoute() async throws {
    let transport = StubTransport { _ in (summaryFixture, 200) }
    let api = try await summaryAPI(transport), context = await api.requestContextID()
    try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        _ = try await api.lariPatientSummary(patientID: "patient-fiction", expectedContext: context)
    }
    #expect(await transport.all().isEmpty)
}
