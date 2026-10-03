import Foundation
import Observation

public enum MedicineReferenceError: Error, LocalizedError, Equatable, Sendable {
    case permissionDenied, invalidQuery, invalidResponse, identityMismatch
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Seu perfil nesta clínica não permite consultar referências clínicas."
        case .invalidQuery: "Informe entre 2 e 200 caracteres para buscar e confira os filtros da consulta."
        case .invalidResponse: "O catálogo retornou uma referência incompleta ou inconsistente. Tente consultar novamente; nenhum dado será completado por suposição."
        case .identityMismatch: "A ficha recebida não corresponde ao medicamento escolhido. Volte à busca e selecione novamente."
        }
    }
}

public struct MedicineReferenceQuery: Equatable, Sendable {
    public enum Field: String, CaseIterable, Identifiable, Sendable {
        case all = "todos", name = "nome", ingredient = "principio"
        public var id: String { rawValue }
        public var title: String {
            switch self { case .all: "Todos os campos"; case .name: "Nome comercial"; case .ingredient: "Princípio ativo" }
        }
    }
    public let term: String
    public let field: Field
    public let page: Int
    public let perPage: Int
    public let includeInactive: Bool
    public init(term: String, field: Field = .all, page: Int = 1, perPage: Int = 25, includeInactive: Bool = false) throws {
        let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...200).contains(cleaned.utf16.count), (1...1_000_000).contains(page), (1...100).contains(perPage) else {
            throw MedicineReferenceError.invalidQuery
        }
        self.term = cleaned; self.field = field; self.page = page; self.perPage = perPage; self.includeInactive = includeInactive
    }
    public var queryItems: [URLQueryItem] {
        [.init(name: "busca", value: term), .init(name: "campo", value: field.rawValue),
         .init(name: "page", value: String(page)), .init(name: "perPage", value: String(perPage)),
         .init(name: "incluirInativos", value: includeInactive ? "true" : "false")]
    }
    public func moving(to page: Int) throws -> Self {
        try .init(term: term, field: field, page: page, perPage: perPage, includeInactive: includeInactive)
    }
}

/// A catalog record, not a retrieved leaflet. Presentation fields are derived by the service from the product name.
public struct MedicineReference: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let nomeProduto: String
    public let principioAtivo: String?
    public let classeTerapeutica: String?
    public let categoriaRegulatoria: String?
    public let numeroRegistro: String?
    public let numeroProcesso: String?
    public let empresa: String?
    public let empresaCnpj: String?
    public let situacao: String
    public let vencimentoRegistro: String?
    public let bulaUrl: String?
    public let concentracao: String?
    public let formaFarmaceutica: String?
    public let atualizadoEm: String

    public static let sourceDescription = "Catálogo de medicamentos do AtendeBem, com referência declarada aos dados de registro da ANVISA."
    public static let coverageDescription = "A base disponível no aplicativo pode ser parcial ou estar defasada. O total da busca corresponde aos filtros deste catálogo e não comprova cobertura de todos os medicamentos ou bulas da ANVISA."
    public static let leafletLimitation = "A LARI ainda não leu o texto da bula deste medicamento. Esta ficha não informa indicações, contraindicações ou todas as interações. A classe terapêutica não equivale a uma indicação de uso. Consulte a bula oficial e revise a informação profissionalmente."

    /// Never forwards the service's arbitrary URL. The only external destination is an exact-register search on the official host.
    public var officialLeafletSearchURL: URL? { Self.officialLeafletSearchURL(registration: numeroRegistro) }
    public static func officialLeafletSearchURL(registration: String?) -> URL? {
        guard let registration else { return nil }
        let cleaned = registration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 60,
              cleaned.unicodeScalars.allSatisfy({ "0123456789./- ".unicodeScalars.contains($0) }) else { return nil }
        let digits = cleaned.filter { $0 >= "0" && $0 <= "9" }
        // Only the supported nine-digit product registration format is used for the official search.
        // Other source values remain visible in the record and are never replaced with a process or ID.
        guard digits.count == 9 else { return nil }
        var components = URLComponents()
        components.scheme = "https"; components.host = "consultas.anvisa.gov.br"; components.path = "/"
        components.fragment = "/bulario/q/?numeroRegistro=" + digits
        return components.url
    }
    public var ingestionDate: Date? { ClinicClock.parseInstant(atualizadoEm) }
    public func validate() throws {
        guard Self.validID(id), !nomeProduto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              nomeProduto.utf16.count <= 2_000, !situacao.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ingestionDate != nil else { throw MedicineReferenceError.invalidResponse }
    }
    public static func validID(_ value: String) -> Bool {
        // Opaque registry/process/hash identifiers are not UUIDs. Reject path delimiters rather than reinterpreting them.
        (1...200).contains(value.utf16.count) && value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}

public struct MedicineReferencePage: Decodable, Sendable {
    public let total: Int
    public let page: Int
    public let perPage: Int
    public let itens: [MedicineReference]
    public var hasPrevious: Bool { page > 1 }
    public var hasNext: Bool { page <= 1_000_000 && perPage <= 100 && page * perPage < total }
    public var firstItemNumber: Int { itens.isEmpty ? 0 : (page - 1) * perPage + 1 }
    public var lastItemNumber: Int { itens.isEmpty ? 0 : (page - 1) * perPage + itens.count }
    public func validate(for query: MedicineReferenceQuery) throws {
        guard page == query.page, perPage == query.perPage, (0...1_000_000_000).contains(total),
              itens.count <= perPage, Set(itens.map(\.id)).count == itens.count else { throw MedicineReferenceError.invalidResponse }
        let offset = (query.page - 1) * query.perPage
        guard itens.count == min(query.perPage, max(0, total - offset)) else { throw MedicineReferenceError.invalidResponse }
        try itens.forEach { try $0.validate() }
    }
}

public struct MedicineReferenceService: Sendable {
    public let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func search(_ query: MedicineReferenceQuery, user: User, context: UUID) async throws -> MedicineReferencePage {
        guard user.canReadClinicalData else { throw MedicineReferenceError.permissionDenied }
        try await requireContext(context)
        let response: MedicineReferencePage = try await api.get(["medicamentos"], query: query.queryItems)
        try await requireContext(context)
        try response.validate(for: query)
        return response
    }
    public func detail(id: String, user: User, context: UUID) async throws -> MedicineReference {
        guard user.canReadClinicalData else { throw MedicineReferenceError.permissionDenied }
        guard MedicineReference.validID(id) else { throw MedicineReferenceError.invalidQuery }
        try await requireContext(context)
        let response: MedicineReference = try await api.get(["medicamentos", id])
        try await requireContext(context)
        guard response.id == id else { throw MedicineReferenceError.identityMismatch }
        try response.validate()
        return response
    }
    private func requireContext(_ context: UUID) async throws {
        guard await api.requestContextID() == context else { throw APIError.contextChanged }
        try Task.checkCancellation()
    }
}

/// Coordinates read-only browsing. Results from another query, record, clinic or permission context are never installed.
@MainActor @Observable
public final class MedicineReferenceBrowser {
    public private(set) var query: MedicineReferenceQuery?
    public private(set) var page: MedicineReferencePage?
    public private(set) var detail: MedicineReference?
    public private(set) var failure: (any Error)?
    public private(set) var detailFailure: (any Error)?
    public private(set) var isSearching = false
    public private(set) var isLoadingDetail = false
    public private(set) var expired = false
    private let service: MedicineReferenceService
    private let context: UUID
    private let current: @MainActor () -> Bool
    private var searchID = UUID()
    private var detailID = UUID()
    public init(api: APIClient, context: UUID, isContextCurrent: @escaping @MainActor () -> Bool = { true }) {
        self.service = .init(api: api); self.context = context; self.current = isContextCurrent
    }
    public func search(_ query: MedicineReferenceQuery, user: User) async {
        guard !expired, current(), user.canReadClinicalData else { invalidate(); failure = MedicineReferenceError.permissionDenied; return }
        let operation = UUID(); searchID = operation
        self.query = query; page = nil; failure = nil; isSearching = true
        clearDetail()
        do {
            let result = try await service.search(query, user: user, context: context)
            guard operation == searchID, !expired else { return }
            guard current() else { invalidate(); return }
            page = result
        } catch {
            guard operation == searchID, !expired else { return }
            if !current() || Self.denied(error) { invalidate(); failure = error; return }
            if !(error is CancellationError) && !Task.isCancelled { failure = error }
        }
        if operation == searchID { isSearching = false }
    }
    public func open(id: String, user: User) async {
        guard !expired, current(), user.canReadClinicalData else { invalidate(); detailFailure = MedicineReferenceError.permissionDenied; return }
        let operation = UUID(); detailID = operation
        detail = nil; detailFailure = nil; isLoadingDetail = true
        do {
            let result = try await service.detail(id: id, user: user, context: context)
            guard operation == detailID, !expired else { return }
            guard current() else { invalidate(); return }
            detail = result
        } catch {
            guard operation == detailID, !expired else { return }
            if !current() || Self.denied(error) { invalidate(); detailFailure = error; return }
            if !(error is CancellationError) && !Task.isCancelled { detailFailure = error }
        }
        if operation == detailID { isLoadingDetail = false }
    }
    public func clearDetail() { detailID = UUID(); detail = nil; detailFailure = nil; isLoadingDetail = false }
    public func clearSearch() {
        searchID = UUID(); query = nil; page = nil; failure = nil; isSearching = false; clearDetail()
    }
    public func invalidate() {
        searchID = UUID(); detailID = UUID(); query = nil; page = nil; detail = nil; failure = nil; detailFailure = nil
        isSearching = false; isLoadingDetail = false; expired = true
    }
    private static func denied(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return error as? MedicineReferenceError == .permissionDenied }
        return [.http(401), .http(403), .sessionExpired, .contextChanged].contains(api)
    }
}
