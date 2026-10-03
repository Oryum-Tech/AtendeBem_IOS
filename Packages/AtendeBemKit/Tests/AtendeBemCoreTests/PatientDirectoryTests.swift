import Foundation
import Testing
@testable import AtendeBemCore

private func directoryUser(_ roles: [String]) throws -> User {
    let data = try JSONSerialization.data(withJSONObject: ["id": "professional-test", "nome": "Profissional Teste", "email": "example@example.invalid", "papeis": roles])
    return try JSONDecoder().decode(User.self, from: data)
}

@Test func patientAgesAreInclusiveAndNeverSilentlyCoerced() throws {
    #expect(try PatientDirectoryFilters.parseAge("  ") == nil)
    #expect(try PatientDirectoryFilters.parseAge("0") == 0)
    #expect(try PatientDirectoryFilters.parseAge("130") == 130)
    for invalid in ["-1", "131", "18.5", "abc", "+18"] {
        #expect(throws: PatientFilterError.invalidAge) { try PatientDirectoryFilters.parseAge(invalid) }
    }
    var filters = PatientDirectoryFilters()
    filters.minimumAge = 60; filters.maximumAge = 18
    let user = try directoryUser(["medico"])
    #expect(throws: PatientFilterError.reversedAges) { try filters.queryItems(search: "", page: 1, user: user) }
}

@Test func patientClinicalFiltersRequireAnActualClinicalRole() throws {
    for roles in [["recepcao"], ["gestor"], ["admin"]] {
        let user = try directoryUser(roles)
        #expect(!user.canUseClinicalPatientFilters)
        var filters = PatientDirectoryFilters()
        filters.condition = "condição de teste"
        #expect(throws: PatientFilterError.clinicalAccessRequired) { try filters.queryItems(search: "", page: 1, user: user) }
        filters.condition = ""; filters.segment = .pregnant
        #expect(throws: PatientFilterError.clinicalAccessRequired) { try filters.queryItems(search: "", page: 1, user: user) }
        filters.segment = .inactive; filters.minimumAge = 18
        #expect(try filters.queryItems(search: "", page: 1, user: user).contains(.init(name: "idadeDe", value: "18")))
        #expect(filters.includesArchived)
        #expect(filters.summary.contains("Inclui arquivados"))
        #expect(try filters.queryItems(search: "", page: 1, user: user).contains(.init(name: "incluirArquivados", value: "true")))
    }
    for role in User.careRoles { #expect(try directoryUser([role]).canUseClinicalPatientFilters) }
    #expect(try directoryUser(["admin", "medico"]).canUseClinicalPatientFilters)
}

@Test func patientQueryPreservesCombinedFiltersAndExplicitArchiveIntent() throws {
    let user = try directoryUser(["medico"])
    var filters = PatientDirectoryFilters()
    var query = try filters.queryItems(search: "  Ana Teste  ", page: 1, user: user)
    #expect(!query.contains { $0.name == "incluirArquivados" || $0.name == "idadeDe" })
    filters.minimumAge = 0; filters.maximumAge = 130; filters.segment = .chronic
    filters.includeArchived = true; filters.condition = " condição teste "; filters.medication = " item teste "
    query = try filters.queryItems(search: " Ana Teste ", page: 2, user: user)
    let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
    #expect(values == ["busca": "Ana Teste", "page": "2", "perPage": "25", "idadeDe": "0", "idadeAte": "130", "segmento": "cronicos", "incluirArquivados": "true", "condicao": "condição teste", "medicamento": "item teste"])
    #expect(filters.activeCount == 5)
}

@Test func directoryWarningsRemainDistinctFromAnEmptyCompleteResult() throws {
    let partial = try JSONDecoder().decode(PatientPage.self, from: Data(#"{"total":0,"itens":[],"truncado":true,"semNascimento":8}"#.utf8))
    #expect(partial.semNascimento == 8)
    #expect(partial.truncado == true)
    let legacy = try JSONDecoder().decode(PatientPage.self, from: Data(#"{"total":0,"itens":[]}"#.utf8))
    #expect(legacy.semNascimento == nil && legacy.truncado == nil)
}

@Test func directoryDeniedFiltersSendNoRequestAndUnavailableServiceDoesNotBecomeEmptyPatients() async throws {
    let tokens = try JSONDecoder().decode(TokenPair.self, from: Data(#"{"accessToken":"test-access","refreshToken":"test-refresh","expiraEm":900}"#.utf8))
    let transport = StubTransport { _ in ("{}", 503) }
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession()
    let service = PatientDirectoryService(api: api)
    var filters = PatientDirectoryFilters(); filters.medication = "item de teste"
    let admin = try directoryUser(["admin"]), professional = try directoryUser(["medico"])
    await #expect(throws: PatientFilterError.clinicalAccessRequired) { try await service.patients(search: "", page: 1, filters: filters, user: admin) }
    #expect(await transport.count("/v1/pacientes") == 0)
    await #expect(throws: APIError.http(503)) { try await service.patients(search: "", page: 1, filters: filters, user: professional) }
    #expect(await transport.count("/v1/pacientes") == 1)
}
