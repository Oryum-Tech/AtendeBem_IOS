import Foundation
import Testing
@testable import AtendeBemCore

@MainActor
private final class MedicineReferenceTestContext {
    var isCurrent = true
}

private func referenceUser(_ roles: [String] = ["medico"]) throws -> User {
    try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: ["id": "reference-fixture", "nome": "Profissional fictício", "email": "fixture@example.invalid", "papeis": roles]))
}
private func referenceAPI(_ transport: any HTTPTransport) async throws -> APIClient {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"reference-fixture","refreshToken":"refresh-fixture","expiraEm":900}"#.utf8))
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession(); return api
}
private func referenceJSON(id: String = "med_fixture01", registration: String? = "1.0000.0001", url: String? = nil, date: String = "2026-01-10T12:00:00Z") throws -> String {
    var object: [String: Any] = ["id": id, "nomeProduto": "Produto de teste", "principioAtivo": "Princípio fictício", "situacao": "Ativo", "atualizadoEm": date, "numeroProcesso": "Processo de teste", "empresa": "Fabricante fictício"]
    if let registration { object["numeroRegistro"] = registration }
    if let url { object["bulaUrl"] = url }
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}
private func referencePageJSON(page: Int = 1, perPage: Int = 1, total: Int = 1, ids: [String] = ["med_fixture01"]) throws -> String {
    let items = try ids.map { try JSONSerialization.jsonObject(with: Data(referenceJSON(id: $0).utf8)) }
    return String(decoding: try JSONSerialization.data(withJSONObject: ["page": page, "perPage": perPage, "total": total, "itens": items]), as: UTF8.self)
}

@Test func medicineReferenceSearchUsesExactPublicQueryAndPagination() async throws {
    let response = try referencePageJSON(page: 2, perPage: 1, total: 3, ids: ["med_fixture02"])
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/medicamentos")
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(values == ["busca": "Princípio fictício", "campo": "principio", "page": "2", "perPage": "1", "incluirInativos": "true"])
        #expect(request.httpBody == nil)
        return (response, 200)
    }
    let api = try await referenceAPI(transport)
    let query = try MedicineReferenceQuery(term: " Princípio fictício ", field: .ingredient, page: 2, perPage: 1, includeInactive: true)
    let page = try await MedicineReferenceService(api: api).search(query, user: referenceUser(), context: await api.requestContextID())
    #expect(page.hasPrevious && page.hasNext)
    #expect(page.firstItemNumber == 2 && page.lastItemNumber == 2)
    let next = try query.moving(to: 3)
    #expect(next.term == query.term && next.field == .ingredient && next.includeInactive && next.page == 3)
    let defaults = try MedicineReferenceQuery(term: "fictício")
    #expect(defaults.field == .all && !defaults.includeInactive && defaults.perPage == 25)
}

@Test func medicineReferenceRejectsInvalidSearchAndInconsistentEnvelopes() throws {
    #expect(throws: MedicineReferenceError.invalidQuery) { try MedicineReferenceQuery(term: "a") }
    #expect(throws: MedicineReferenceError.invalidQuery) { try MedicineReferenceQuery(term: "ab", perPage: 101) }
    #expect(throws: MedicineReferenceError.invalidQuery) { try MedicineReferenceQuery(term: "ab", page: 0) }
    let query = try MedicineReferenceQuery(term: "teste", perPage: 2)
    let invalid = [
        try referencePageJSON(page: 2, perPage: 2, total: 2),
        try referencePageJSON(perPage: 1, total: 1),
        try referencePageJSON(perPage: 2, total: 2, ids: ["same", "same"]),
        try referencePageJSON(perPage: 2, total: 3, ids: ["only-one"]),
        try referencePageJSON(perPage: 2, total: -1, ids: [])
    ]
    for json in invalid {
        let page = try JSONDecoder().decode(MedicineReferencePage.self, from: Data(json.utf8))
        #expect(throws: MedicineReferenceError.invalidResponse) { try page.validate(for: query) }
    }
    let empty = try JSONDecoder().decode(MedicineReferencePage.self, from: Data(referencePageJSON(perPage: 2, total: 0, ids: []).utf8))
    try empty.validate(for: query)
    #expect(!empty.hasNext && !empty.hasPrevious && empty.firstItemNumber == 0)
}

@Test func medicineReferenceDetailPreservesOpaqueIdentityAndRejectsDifferentProduct() async throws {
    let json = try referenceJSON(id: "med_hash_123")
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/medicamentos/med_hash_123")
        return (json, 200)
    }
    let api = try await referenceAPI(transport)
    let item = try await MedicineReferenceService(api: api).detail(id: "med_hash_123", user: referenceUser(), context: await api.requestContextID())
    #expect(item.id == "med_hash_123" && item.numeroProcesso == "Processo de teste")
    let mismatchAPI = try await referenceAPI(StubTransport { _ in (json, 200) })
    await #expect(throws: MedicineReferenceError.identityMismatch) {
        try await MedicineReferenceService(api: mismatchAPI).detail(id: "other-record", user: referenceUser(), context: await mismatchAPI.requestContextID())
    }
    let unused = StubTransport { _ in Issue.record("Path delimiter must never reach API"); return (json, 200) }
    let protectedAPI = try await referenceAPI(unused)
    for id in ["", "../other", "med?foo=bar", "med%2Fother"] {
        await #expect(throws: MedicineReferenceError.invalidQuery) {
            try await MedicineReferenceService(api: protectedAPI).detail(id: id, user: referenceUser(), context: await protectedAPI.requestContextID())
        }
    }
    #expect(await unused.all().isEmpty)
}

@Test func medicineReferenceOfficialLinkNeverTrustsReturnedURLOrUsesProcessAsRegister() throws {
    for unsafe in ["javascript:alert(1)", "https://evil.example/bula", "https://consultas.anvisa.gov.br.evil.example/", "https://user:secret@consultas.anvisa.gov.br/", "https://consultas.anvisa.gov.br/#/bulario/q/?numeroRegistro=999"] {
        let item = try JSONDecoder().decode(MedicineReference.self, from: Data(referenceJSON(url: unsafe).utf8))
        let url = try #require(item.officialLeafletSearchURL)
        #expect(url.scheme == "https" && url.host == "consultas.anvisa.gov.br")
        #expect(url.user == nil && url.password == nil && url.query == nil)
        #expect(url.fragment == "/bulario/q/?numeroRegistro=100000001")
    }
    let missing = try JSONDecoder().decode(MedicineReference.self, from: Data(referenceJSON(id: "123456789", registration: nil, url: "https://consultas.anvisa.gov.br/").utf8))
    #expect(missing.officialLeafletSearchURL == nil)
    for value in ["", "...", "1", "12345678", "1234567890", "123&token=secret", "https://123", "１２３", "123\n456", "123?other=1"] {
        #expect(MedicineReference.officialLeafletSearchURL(registration: value) == nil)
    }
    #expect(MedicineReference.officialLeafletSearchURL(registration: " 1.0000.0001 ")?.fragment == "/bulario/q/?numeroRegistro=100000001")
}

@Test func medicineReferenceDateIsIngestionAndMissingDateDoesNotBecomeToday() throws {
    let record = try JSONDecoder().decode(MedicineReference.self, from: Data(referenceJSON().utf8))
    try record.validate()
    #expect(record.ingestionDate == ClinicClock.parseInstant("2026-01-10T12:00:00Z"))
    #expect(MedicineReference.leafletLimitation.contains("ainda não leu"))
    #expect(MedicineReference.coverageDescription.contains("parcial"))
    let invalid = try JSONDecoder().decode(MedicineReference.self, from: Data(referenceJSON(date: "").utf8))
    #expect(invalid.ingestionDate == nil)
    #expect(throws: MedicineReferenceError.invalidResponse) { try invalid.validate() }
}

@Test func medicineReferenceClinicalAccessAndOldContextBlockRequests() async throws {
    let transport = StubTransport { _ in Issue.record("Forbidden read must not reach API"); return ("{}", 500) }
    let api = try await referenceAPI(transport)
    let service = MedicineReferenceService(api: api)
    for role in ["admin", "gestor", "recepcao", "contabilista", "Medico", "unknown"] {
        let user = try referenceUser([role])
        await #expect(throws: MedicineReferenceError.permissionDenied) {
            try await service.search(MedicineReferenceQuery(term: "fictício"), user: user, context: await api.requestContextID())
        }
        await #expect(throws: MedicineReferenceError.permissionDenied) {
            try await service.detail(id: "med_fixture01", user: user, context: await api.requestContextID())
        }
    }
    let old = await api.requestContextID()
    try await api.logout()
    await #expect(throws: APIError.contextChanged) {
        try await service.search(MedicineReferenceQuery(term: "fictício"), user: referenceUser(), context: old)
    }
    #expect(await transport.all().isEmpty)
}

@Test @MainActor func medicineReferenceBrowserDiscardsLateSearchAfterContextChange() async throws {
    let gate = ResponseGate()
    let json = try referencePageJSON()
    let api = try await referenceAPI(StubTransport { _ in await gate.suspend(); return (json, 200) })
    let contextState = MedicineReferenceTestContext()
    let browser = MedicineReferenceBrowser(api: api, context: await api.requestContextID(), isContextCurrent: { contextState.isCurrent })
    let query = try MedicineReferenceQuery(term: "fictício", perPage: 1)
    let user = try referenceUser()
    let read = Task { await browser.search(query, user: user) }
    try await gate.waitForRequest()
    contextState.isCurrent = false
    await gate.resume(); await read.value
    #expect(browser.expired && browser.page == nil && browser.query == nil && !browser.isSearching)
}

@Test @MainActor func medicineReferenceNewSearchCannotBeOverwrittenByOlderResponse() async throws {
    let gate = ResponseGate()
    let oldPage = try referencePageJSON(ids: ["old"])
    let newPage = try referencePageJSON(ids: ["new"])
    let api = try await referenceAPI(StubTransport { request in
        if request.url?.query?.contains("antigo") == true { await gate.suspend(); return (oldPage, 200) }
        return (newPage, 200)
    })
    let browser = MedicineReferenceBrowser(api: api, context: await api.requestContextID())
    let user = try referenceUser()
    let firstQuery = try MedicineReferenceQuery(term: "antigo", perPage: 1)
    let first = Task { await browser.search(firstQuery, user: user) }
    try await gate.waitForRequest()
    await browser.search(try MedicineReferenceQuery(term: "novo", perPage: 1), user: user)
    await gate.resume(); await first.value
    #expect(browser.page?.itens.first?.id == "new" && browser.query?.term == "novo" && !browser.isSearching)
    browser.clearSearch()
    #expect(browser.page == nil && browser.query == nil && browser.detail == nil && !browser.expired)
}

@Test @MainActor func medicineReferenceForbiddenDetailClearsPreviouslyLoadedSearch() async throws {
    let json = try referencePageJSON()
    let api = try await referenceAPI(StubTransport { request in request.url?.path == "/v1/medicamentos" ? (json, 200) : ("{}", 403) })
    let browser = MedicineReferenceBrowser(api: api, context: await api.requestContextID())
    let user = try referenceUser()
    await browser.search(try MedicineReferenceQuery(term: "fictício", perPage: 1), user: user)
    #expect(browser.page != nil)
    await browser.open(id: "med_fixture01", user: user)
    #expect(browser.expired && browser.page == nil && browser.query == nil && browser.detail == nil)
    #expect(browser.detailFailure as? APIError == .http(403))
}

@Test @MainActor func medicineReferenceDetailChangedOrDismissedWhileReadingCannotReappear() async throws {
    let gate = ResponseGate()
    let json = try referenceJSON()
    let api = try await referenceAPI(StubTransport { _ in await gate.suspend(); return (json, 200) })
    let browser = MedicineReferenceBrowser(api: api, context: await api.requestContextID())
    let user = try referenceUser()
    let read = Task { await browser.open(id: "med_fixture01", user: user) }
    try await gate.waitForRequest(); browser.clearDetail(); await gate.resume(); await read.value
    #expect(browser.detail == nil && !browser.isLoadingDetail && !browser.expired)
}
