import Foundation

public enum PatientSegment: String, CaseIterable, Sendable, Identifiable {
    case all = "todos", inactive = "inativos-90d", chronic = "cronicos", pregnant = "gestantes"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "Todos"; case .inactive: "Sem consulta há 90 dias"
        case .chronic: "Condições crônicas"; case .pregnant: "Gestantes"
        }
    }
    public var requiresClinicalAccess: Bool { self == .chronic || self == .pregnant }
}

public extension User {
    // The directory service deliberately does not treat admin as a clinical wildcard.
    var canUseClinicalPatientFilters: Bool { !Set(papeis).isDisjoint(with: Self.careRoles) }
}

public enum PatientFilterError: Error, LocalizedError, Equatable {
    case invalidAge, reversedAges, clinicalAccessRequired
    public var errorDescription: String? {
        switch self {
        case .invalidAge: "Informe idades inteiras de 0 a 130 anos, ou deixe o campo vazio."
        case .reversedAges: "A idade mínima deve ser menor ou igual à máxima."
        case .clinicalAccessRequired: "Seu perfil não permite filtrar pacientes por informações clínicas."
        }
    }
}

public struct PatientDirectoryFilters: Equatable, Sendable {
    public var segment: PatientSegment = .all
    public var includeArchived = false
    public var minimumAge: Int?
    public var maximumAge: Int?
    public var condition = ""
    public var medication = ""
    public init() {}
    // The service includes archived records for this follow-up segment regardless of the flag.
    public var includesArchived: Bool { includeArchived || segment == .inactive }

    public var usesClinicalData: Bool {
        segment.requiresClinicalAccess || !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !medication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var activeCount: Int {
        (segment == .all ? 0 : 1) + (includeArchived ? 1 : 0) + (minimumAge == nil && maximumAge == nil ? 0 : 1)
        + (condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
        + (medication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }
    public var summary: [String] {
        var labels: [String] = []
        if segment != .all { labels.append(segment.title) }
        if let minimumAge, let maximumAge { labels.append("De \(minimumAge) a \(maximumAge) anos") }
        else if let minimumAge { labels.append("A partir de \(minimumAge) anos") }
        else if let maximumAge { labels.append("Até \(maximumAge) anos") }
        if !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { labels.append("Condição: \(condition)") }
        if !medication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { labels.append("Medicamento: \(medication)") }
        if includesArchived { labels.append("Inclui arquivados") }
        return labels
    }

    public static func parseAge(_ text: String) throws -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.allSatisfy({ $0 >= "0" && $0 <= "9" }), let age = Int(value), (0...130).contains(age) else { throw PatientFilterError.invalidAge }
        return age
    }

    public func queryItems(search: String, page: Int, user: User) throws -> [URLQueryItem] {
        guard user.canReadPatients else { throw APIError.http(403) }
        for age in [minimumAge, maximumAge].compactMap({ $0 }) where !(0...130).contains(age) { throw PatientFilterError.invalidAge }
        if let minimumAge, let maximumAge, minimumAge > maximumAge { throw PatientFilterError.reversedAges }
        if usesClinicalData && !user.canUseClinicalPatientFilters { throw PatientFilterError.clinicalAccessRequired }
        var items: [URLQueryItem] = [
            .init(name: "busca", value: search.trimmingCharacters(in: .whitespacesAndNewlines)),
            .init(name: "page", value: String(max(1, page))), .init(name: "perPage", value: "25")
        ]
        if segment != .all { items.append(.init(name: "segmento", value: segment.rawValue)) }
        if includesArchived { items.append(.init(name: "incluirArquivados", value: "true")) }
        if let minimumAge { items.append(.init(name: "idadeDe", value: String(minimumAge))) }
        if let maximumAge { items.append(.init(name: "idadeAte", value: String(maximumAge))) }
        for (key, value) in [("condicao", condition), ("medicamento", medication)] {
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty { items.append(.init(name: key, value: term)) }
        }
        return items
    }
}

public struct PatientDirectoryService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func patients(search: String, page: Int, filters: PatientDirectoryFilters, user: User) async throws -> PatientPage {
        let query = try filters.queryItems(search: search, page: page, user: user)
        return try await api.get(["pacientes"], query: query)
    }
}
