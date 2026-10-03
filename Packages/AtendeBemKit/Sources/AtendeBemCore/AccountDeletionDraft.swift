import Foundation

/// A user-reviewed message, not a server request or evidence of account deletion.
public struct AccountDeletionDraft: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let recipient = "privacidade@atendebem.io"
    public static let subject = "Solicitação de exclusão da conta AtendeBem"

    public let accountID: String
    public let accountEmail: String

    public enum ValidationError: Error, Equatable { case invalidAccount }

    public init(accountID: String, accountEmail: String) throws {
        let identifier = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        guard !identifier.isEmpty, identifier.utf8.count <= 200,
              !identifier.unicodeScalars.contains(where: forbidden.contains),
              !email.isEmpty, email.utf8.count <= 254,
              !email.unicodeScalars.contains(where: { forbidden.contains($0) || CharacterSet.whitespaces.contains($0) }),
              email.split(separator: "@", omittingEmptySubsequences: false).count == 2,
              email.first != "@", email.last != "@" else { throw ValidationError.invalidAccount }
        self.accountID = identifier
        self.accountEmail = email
    }

    public var body: String {
        """
        Olá, equipe de privacidade do AtendeBem.

        Solicito a exclusão integral da minha conta AtendeBem e dos meus dados pessoais que não precisem ser mantidos por obrigação legal. O pedido se refere à minha conta como um todo, e não apenas ao acesso à clínica atualmente selecionada.

        E-mail da conta: \(accountEmail)
        Identificador da conta: \(accountID)

        Peço a confirmação de recebimento, as orientações para verificar minha identidade e a informação do prazo de processamento. Caso algum dado precise ser conservado, peço a informação das categorias, do motivo e do período de retenção aplicável. Por favor, informem quando o pedido for concluído.

        Este pedido não solicita a eliminação automática de prontuários ou de registros clínicos sob responsabilidade das clínicas.
        """
    }

    /// The fixed recipient cannot be replaced by values from the account profile.
    public var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.recipient
        components.queryItems = [URLQueryItem(name: "subject", value: Self.subject), URLQueryItem(name: "body", value: body)]
        // Some mail clients interpret an unescaped plus as a space in query values.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    public var description: String { "AccountDeletionDraft(redacted)" }
    public var debugDescription: String { description }
}
