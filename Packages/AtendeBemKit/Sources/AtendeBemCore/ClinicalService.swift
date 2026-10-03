import Foundation

public struct WaitingQueue: Decodable, Sendable {
    public let dia: String
    public let geradoEm: String
    public let totalAguardando: Int
    public let emAtendimento: [WaitingItem]
    public let itens: [WaitingItem]
}

public struct WaitingItem: Decodable, Sendable, Identifiable {
    public let agendamentoId: String
    public let pacienteId: String
    public let profissionalId: String
    public let posicao: Int?
    public let inicio: String
    public let esperaMin: Int
    public let chegadaEm: String?
    public let atrasoMin: Int?
    public let tipo: String?
    public let canal: String?
    public let autoCheckin: Bool?
    public let liberacaoExcepcional: Bool?
    public let liberacaoMotivo: String?
    public var id: String { agendamentoId }
}

public struct VisitSummary: Decodable, Sendable {
    public let totalRealizadas: Int
    public let ultima: LastVisit?
    public struct LastVisit: Decodable, Sendable {
        public let agendamentoId: String
        public let inicio: String
        public let diasAtras: Int
    }
}

public struct AgendaSnapshot: Sendable {
    public let appointments: [Appointment]
    public let patientNames: [String: String]
    public let namesUnavailable: Bool
}

public struct ClinicalService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func agenda(day: String) async throws -> AgendaSnapshot {
        let page: AppointmentPage = try await api.get(["agendamentos"], query: [.init(name: "dia", value: day)])
        let ids = Array(Set(page.itens.map(\.pacienteId))).sorted()
        var names: [String: String] = [:]
        var namesUnavailable = false
        // Bounded batches avoid one query per patient and do not truncate large clinic days.
        for offset in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[offset..<min(offset + 100, ids.count)])
            do {
                let patients: PatientPage = try await api.get(["pacientes"], query: [
                    .init(name: "ids", value: batch.joined(separator: ",")),
                    .init(name: "perPage", value: "100"), .init(name: "page", value: "1")
                ])
                for patient in patients.itens { names[patient.id] = patient.nome }
                if patients.itens.count < patients.total { namesUnavailable = true }
            } catch let error as APIError where error == .sessionExpired || error == .contextChanged {
                throw error
            } catch is CancellationError { throw CancellationError() }
            catch { namesUnavailable = true }
        }
        try Task.checkCancellation()
        return AgendaSnapshot(appointments: page.itens.sorted {
            ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
        },
                              patientNames: names, namesUnavailable: namesUnavailable)
    }

    public func patients(search: String, page: Int) async throws -> PatientPage {
        try await api.get(["pacientes"], query: [
            .init(name: "busca", value: search), .init(name: "page", value: String(page)),
            .init(name: "perPage", value: "25")
        ])
    }
}
