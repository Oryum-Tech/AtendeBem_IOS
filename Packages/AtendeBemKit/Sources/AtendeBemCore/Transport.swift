import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// No response cache, cookies, credential persistence, or cross-origin redirects.
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum APIError: Error, LocalizedError, Equatable, Sendable {
    case http(Int)
    case problem(Int, String)
    case invalidResponse
    case invalidConfiguration
    case sessionExpired
    case contextChanged
    case secureStorage

    public var errorDescription: String? {
        switch self {
        case .problem(_, let detail): detail
        case .http(402): "Este recurso ou certificado não está disponível para sua conta. Confira com a administração da clínica."
        case .http(401), .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .http(403): "Sua conta não tem acesso a esta informação nesta clínica."
        case .http(404): "Não foi possível encontrar este registro."
        case .http(409), .http(412): "O registro mudou. Atualize os dados antes de tentar novamente."
        case .http(422): "Confira os campos e tente novamente."
        case .http(429): "Há muitas solicitações. Aguarde um momento e tente novamente."
        case .http: "O serviço está indisponível no momento. Tente novamente."
        case .invalidResponse: "O servidor retornou uma resposta inesperada. Tente atualizar."
        case .invalidConfiguration: "A conexão com o AtendeBem não está configurada corretamente."
        case .contextChanged: "A clínica ou a sessão mudou. Atualize esta tela."
        case .secureStorage: "Não foi possível acessar a sessão protegida deste dispositivo."
        }
    }

    public var statusCode: Int? {
        switch self {
        case .http(let code), .problem(let code, _): code
        default: nil
        }
    }
}
