import Foundation
import Testing
@testable import AtendeBemCore

private func advancedUser(_ roles: [String]) throws -> User {
    try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id": "advanced-fixture", "nome": "Profissional fictício", "email": "fixture@example.invalid", "papeis": roles]))
}
private func advancedAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"advanced-fixture","refreshToken":"refresh-fixture","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession(); return api
}
private let transcriptJSON = #"{"linhas":[{"quem":"med","texto":"Texto fictício."},{"quem":null,"texto":"Outra fala."}],"texto":"Texto fictício.\nOutra fala.","disclaimer":"Rascunho para revisão profissional."}"#

@Test func audioRequestEnforcesConsentMimeAndBinarySizeBeforeEncoding() throws {
    let data = Data(repeating: 1, count: 48)
    #expect(throws: LARIAdvancedError.consent) { try ConsultationAudioRequest(data: data, mimeType: "audio/mp4", consent: false) }
    #expect(throws: LARIAdvancedError.invalidAudio) { try ConsultationAudioRequest(data: Data(), mimeType: "audio/mp4", consent: true) }
    #expect(throws: LARIAdvancedError.invalidAudio) { try ConsultationAudioRequest(data: data, mimeType: "video/mp4", consent: true) }
    let request = try ConsultationAudioRequest(data: data, mimeType: "audio/mp4", consent: true)
    #expect(request.audioB64.count == 64)
    #expect(ConsultationAudioRequest.maximumBytes / 3 * 4 == ConsultationAudioRequest.maximumBase64Characters)
    #expect(throws: LARIAdvancedError.invalidAudio) {
        try ConsultationAudioRequest(data: Data(repeating: 0, count: ConsultationAudioRequest.maximumBytes + 1), mimeType: "audio/mp4", consent: true)
    }
}

@Test func audioUsesDedicatedTimeoutAndExactRouteWithoutPatientOrClinicalWrite() async throws {
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/sugestoes/transcrever")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 120)
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        #expect(Set(body.keys) == Set(["audioB64", "mimeType"]))
        return (transcriptJSON, 200)
    }
    let api = try await advancedAPI(transport)
    let response = try await api.transcribeAudio(ConsultationAudioRequest(data: Data(repeating: 1, count: 48), mimeType: "audio/mp4", consent: true), expectedContext: await api.requestContextID())
    #expect(response.linhas[1].quem == nil)
    #expect(response.texto == "Texto fictício.\nOutra fala.")
    #expect(await transport.all().count == 1)
}

@Test func audioDoesNotReplayPostAfterUnauthorizedOrFabricateOnUnavailable() async throws {
    for status in [401, 503] {
        let transport = StubTransport { _ in ("{}", status) }
        let api = try await advancedAPI(transport)
        await #expect(throws: APIError.http(status)) {
            try await api.transcribeAudio(ConsultationAudioRequest(data: Data(repeating: 1, count: 48), mimeType: "audio/mp4", consent: true), expectedContext: await api.requestContextID())
        }
        #expect(await transport.all().count == 1)
    }
}

@Test func audioRejectsChangedSessionBeforeSending() async throws {
    let transport = StubTransport { _ in Issue.record("stale audio must not be sent"); return (transcriptJSON, 200) }
    let api = try await advancedAPI(transport)
    let context = await api.requestContextID()
    try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        try await api.transcribeAudio(ConsultationAudioRequest(data: Data(repeating: 1, count: 48), mimeType: "audio/mp4", consent: true), expectedContext: context)
    }
    #expect(await transport.all().isEmpty)
}

@Test func transcriptRejectsInventedSpeakerOrInconsistentCombinedText() throws {
    for value in [transcriptJSON.replacingOccurrences(of: "\"med\"", with: "\"verified-doctor\""), transcriptJSON.replacingOccurrences(of: "Texto fictício.\\nOutra fala.", with: "Conteúdo diferente")] {
        let response = try JSONDecoder().decode(ConsultationTranscription.self, from: Data(value.utf8))
        #expect(throws: LARIAdvancedError.invalidTranscript) { try response.validate() }
    }
}

@Test func transcriptAppendPreservesOriginalContentAndDoesNotAssignDiagnosis() throws {
    let baseline = ConsultationContent(notes: ["s": "Nota original."], complaint: "Queixa fictícia", codes: ["Z00"])
    let result = try ConsultationTranscriptMerge.append("Texto revisado.", sectionID: "s", baseline: baseline, current: baseline)
    #expect(result.notes["s"] == "Nota original.\n\nTexto revisado.")
    #expect(result.codes == baseline.codes)
    #expect(result.complaint == baseline.complaint)
    #expect(throws: LARIAdvancedError.staleConsultation) {
        try ConsultationTranscriptMerge.append("Texto", sectionID: "s", baseline: baseline, current: result)
    }
    #expect(throws: LARIAdvancedError.invalidTranscript) {
        try ConsultationTranscriptMerge.append("Texto", sectionID: "unknown", baseline: baseline, current: baseline)
    }
}

@Test func interactionInputsRequireReviewedDistinctPrinciplesRatherThanGuessingBrands() throws {
    #expect(try CuratedInteractionService.principles(from: "Princípio alfa\nPrincípio beta") == ["Princípio alfa", "Princípio beta"])
    for value in ["", "único", "alfa\nALFA", "ácido\nacido", Array(repeating: "princípio", count: 51).joined(separator: "\n")] {
        #expect(throws: LARIAdvancedError.invalidPrinciples) { try CuratedInteractionService.principles(from: value) }
    }
}

@Test func interactionsUseCuratedServiceAndKeepProvenance() async throws {
    let transport = StubTransport { request in
        #expect(request.url?.path == "/v1/medicamentos/interacoes")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval != 120)
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: [String]])
        #expect(body == ["principios": ["Alfa", "Beta"]])
        return (#"[{"a":"Alfa","b":"Beta","gravidade":"grave","descricao":"Alerta sintético de teste.","fonte":"Referência sintética para teste","revisadoEm":"2026-01-10"}]"#, 201)
    }
    let api = try await advancedAPI(transport)
    let report = try await CuratedInteractionService(api: api).check(text: "Alfa\nBeta", user: advancedUser(["medico"]), context: await api.requestContextID())
    #expect(report.alerts.count == 1)
    #expect(report.text().contains("2026-01-10"))
    #expect(report.text().contains("não confirma segurança"))
}

@Test func interactionsEmptyResultIsNotASafetyClearance() async throws {
    let api = try await advancedAPI(StubTransport { _ in ("[]", 200) })
    let report = try await CuratedInteractionService(api: api).check(text: "Alfa\nBeta", user: advancedUser(["dentista"]), context: await api.requestContextID())
    #expect(report.text().contains("Nenhum alerta encontrado na base consultada"))
    #expect(report.text().contains("não confirma segurança"))
}

@Test func interactionsRejectMissingProvenanceAndUnrequestedPrinciple() async throws {
    for json in [#"[{"a":"Alfa","b":"Beta","gravidade":"grave","descricao":"Alerta fictício.","fonte":"","revisadoEm":"2026-01-10"}]"#, #"[{"a":"Alfa","b":"Outro","gravidade":"grave","descricao":"Alerta fictício.","fonte":"Referência sintética para teste","revisadoEm":"2026-01-10"}]"#] {
        let api = try await advancedAPI(StubTransport { _ in (json, 200) })
        await #expect(throws: LARIAdvancedError.invalidReport) {
            try await CuratedInteractionService(api: api).check(text: "Alfa\nBeta", user: advancedUser(["medico"]), context: await api.requestContextID())
        }
    }
}

private func seasonalityJSON() throws -> String {
    let weekly: [[String: Any]] = (0...6).map { ["diaSemana": $0, "nome": "Dia \($0)", "totalConsultas": $0 == 0 ? 1 : 0, "mediaConsultasDia": $0 == 0 ? 1.0 : 0] }
    let monthly: [[String: Any]] = (1...12).map { ["mes": $0, "nome": "Mês \($0)", "totalConsultas": $0 == 1 ? 1 : 0, "mediaConsultasDia": $0 == 1 ? 1.0 : 0] }
    return String(decoding: try JSONSerialization.data(withJSONObject: ["disclaimerCfm": "Somente análise operacional", "escopo": "clinica", "periodo": ["de": "2026-01-04", "ate": "2026-01-04", "dias": 1, "fuso": "America/Sao_Paulo"], "totalConsultas": 1, "perfilSemanal": weekly, "perfilMensal": monthly, "avisos": ["Fonte de clima indisponível"]]), as: UTF8.self)
}

@Test func analyticsUsesBackendPeriodAndPreservesSourceWarnings() async throws {
    let json = try seasonalityJSON()
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/analytics/demanda/sazonalidade")
        #expect(request.url?.query == nil)
        return (json, 200)
    }
    let api = try await advancedAPI(transport)
    let report = try await LARIAnalyticsService(api: api).seasonality(user: advancedUser(["medico"]), context: await api.requestContextID())
    #expect(report.text(clinic: "Clínica fictícia").contains("2026-01-04"))
    #expect(report.text(clinic: "Clínica fictícia").contains("Fonte de clima indisponível"))
    #expect(report.text(clinic: "Clínica fictícia").contains("não faz previsão"))
}

@Test func analyticsDeniesUnmappedRolesBeforeNetwork() async throws {
    let transport = StubTransport { _ in Issue.record("forbidden analytics"); return ("{}", 200) }
    let api = try await advancedAPI(transport)
    for role in ["admin", "contabilista", "enfermeiro", "recepcao", "Gestor"] {
        await #expect(throws: LARIAdvancedError.permission) {
            try await LARIAnalyticsService(api: api).geography(user: advancedUser([role]), context: await api.requestContextID())
        }
    }
    #expect(await transport.all().isEmpty)
}

@Test func geographyRejectsMismatchedCountsAndShowsMissingCensusHonestly() async throws {
    let valid = #"{"municipios":[{"cidade":"Cidade fictícia","uf":"XX","total":2,"pct":1,"ibge":null,"penetracao":null}],"totalPacientes":3,"comCidade":2,"semCidade":1,"avisos":["IBGE indisponível"],"fontes":[],"atualizadoEm":"2026-01-10T12:00:00Z"}"#
    let api = try await advancedAPI(StubTransport { request in
        #expect(request.url?.path == "/v1/analytics/geo/mapa"); return (valid, 200)
    })
    let report = try await LARIAnalyticsService(api: api).geography(user: advancedUser(["gestor"]), context: await api.requestContextID())
    #expect(report.text(clinic: "Fictícia").contains("População municipal indisponível"))
    let invalid = try JSONDecoder().decode(LARIGeography.self, from: Data(valid.replacingOccurrences(of: "\"comCidade\":2", with: "\"comCidade\":0").utf8))
    #expect(throws: LARIAdvancedError.invalidReport) { try invalid.validate() }
}
