import Foundation
import Testing
@testable import AtendeBemCore

final class MockTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { try handler(request) }
}

struct MockStorage: SessionStorage {
    var memory: StoredSession?
    func load() throws -> StoredSession? { memory }
    func save(_ session: StoredSession) throws { }
    func clear() throws { }
}

@Suite("APIClient and ClinicalService")
struct APIClientTests {
    @Test("makeRequest rejects invalid scheme")
    func invalidScheme() async throws {
        #expect(throws: APIError.invalidConfiguration) {
            _ = try APIClient.makeRequest(baseURL: URL(string: "http://example.com")!, path: ["a"], method: "GET")
        }
    }

    @Test("login returns authenticated and installs tokens")
    func loginAuthenticated() async throws {
        let pair = TokenPair(accessToken: "a.b.c", refreshToken: "r", expiraEm: 3600)
        let transport = MockTransport { req in
            let url = try #require(req.url)
            #expect(url.path.contains("/auth/login"))
            let data = try JSONEncoder().encode(pair)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
        let api = APIClient(baseURL: URL(string: "https://example.com/v1")!,
                            storage: MockStorage(), transport: transport)
        let result = try await api.login(email: "a@b.com", password: "123")
        switch result { case .authenticated: break; default: Issue.record("Expected authenticated") }
        #expect(await api.hasSession())
    }

    @Test("ClinicalService agenda returns sorted appointments and names")
    func agendaSnapshot() async throws {
        let day = "2024-01-02"
        let appts = AppointmentPage(itens: [
            Appointment(id: "2", inicio: "2024-01-02T13:00:00Z", duracaoMin: 30, pacienteId: "p2", profissionalId: "m1", tipo: "consulta", canal: "presencial", status: "scheduled", chegadaEm: nil, motivo: nil),
            Appointment(id: "1", inicio: "2024-01-02T08:00:00Z", duracaoMin: 30, pacienteId: "p1", profissionalId: "m1", tipo: "consulta", canal: "presencial", status: "scheduled", chegadaEm: nil, motivo: "Retorno")
        ])
        let patients = PatientPage(total: 2, itens: [
            Patient(id: "p1", nome: "Ana", cpfMascarado: nil, nascimento: nil, telefone: nil, email: nil, status: nil, rascunho: nil, alergias: nil, condicoes: nil),
            Patient(id: "p2", nome: "Bruno", cpfMascarado: nil, nascimento: nil, telefone: nil, email: nil, status: nil, rascunho: nil, alergias: nil, condicoes: nil)
        ], truncado: nil)
        let transport = MockTransport { req in
            let url = try #require(req.url)
            let path = url.path
            if path.contains("/agendamentos") {
                // Ensure day is passed
                #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "dia" && $0.value == day }) == true)
                let data = try JSONEncoder().encode(appts)
                return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            } else if path.contains("/pacientes") {
                let data = try JSONEncoder().encode(patients)
                return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        let api = APIClient(baseURL: URL(string: "https://example.com/v1")!, storage: MockStorage(), transport: transport)
        let service = ClinicalService(api: api)
        let snapshot = try await service.agenda(day: day)
        #expect(snapshot.appointments.first?.id == "1")
        #expect(snapshot.patientNames["p1"] == "Ana")
        #expect(snapshot.patientNames["p2"] == "Bruno")
        #expect(snapshot.namesUnavailable == false)
    }
}

