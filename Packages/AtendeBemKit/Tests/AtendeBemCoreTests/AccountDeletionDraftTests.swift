import Foundation
import Testing
@testable import AtendeBemCore

@Test func accountDeletionDraftUsesOnlyTheCurrentAccountAndFixedPrivacyRecipient() throws {
    let draft = try AccountDeletionDraft(accountID: " synthetic-account ", accountEmail: " profissional+teste@example.invalid ")
    #expect(draft.accountID == "synthetic-account")
    #expect(draft.accountEmail == "profissional+teste@example.invalid")
    let url = try #require(draft.mailtoURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.scheme == "mailto")
    #expect(components.path == "privacidade@atendebem.io")
    #expect(components.host == nil)
    #expect(components.fragment == nil)
    #expect(components.queryItems == [URLQueryItem(name: "subject", value: AccountDeletionDraft.subject), URLQueryItem(name: "body", value: draft.body)])
    #expect(url.absoluteString.contains("%2Bteste"))
    #expect(draft.body.contains("profissional+teste@example.invalid"))
    #expect(draft.body.contains("synthetic-account"))
    #expect(!draft.description.contains("synthetic-account"))
    #expect(!draft.debugDescription.contains("example.invalid"))
}

@Test func accountDeletionDraftEscapesValuesWithoutAddingRecipientsOrMailHeaders() throws {
    let draft = try AccountDeletionDraft(accountID: "synthetic&bcc=other@example.invalid?#", accountEmail: "teste+&=?@example.invalid")
    let url = try #require(draft.mailtoURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.path == AccountDeletionDraft.recipient)
    #expect(components.fragment == nil)
    #expect(components.queryItems?.count == 2)
    #expect(components.queryItems?.first(where: { $0.name == "bcc" || $0.name == "cc" || $0.name == "to" }) == nil)
    #expect(components.queryItems?.first(where: { $0.name == "body" })?.value == draft.body)
}

@Test(arguments: ["", " ", "invalid", "@example.invalid", "teste@", "two@@example.invalid", "name with space@example.invalid", "teste\nBcc:other@example.invalid", "teste\u{00}@example.invalid"])
func accountDeletionDraftRejectsMissingOrUnsafeAccountEmail(email: String) {
    #expect(throws: AccountDeletionDraft.ValidationError.invalidAccount) {
        try AccountDeletionDraft(accountID: "synthetic-account", accountEmail: email)
    }
}

@Test(arguments: ["", " ", "synthetic\nBcc:another", "synthetic\rnew-field", "synthetic\u{00}account", String(repeating: "a", count: 201)])
func accountDeletionDraftRejectsMissingOrUnsafeAccountIdentifier(identifier: String) {
    #expect(throws: AccountDeletionDraft.ValidationError.invalidAccount) {
        try AccountDeletionDraft(accountID: identifier, accountEmail: "teste@example.invalid")
    }
}
