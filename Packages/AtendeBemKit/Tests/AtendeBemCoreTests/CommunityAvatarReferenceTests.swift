import Foundation
import Testing
@testable import AtendeBemCore

@Test func communityAvatarNeverUsesAnonymousIdentityOrExternalAddress() {
    #expect(CommunityAvatarReference.mediaID("mid_avatar-123") == "mid_avatar-123")
    #expect(CommunityAvatarReference.mediaID("mid_avatar-123", anonymous: true) == nil)
    for value in ["", "../secret", "https://example.invalid/avatar", "file:///photo", "//example.invalid", "image?token=value", "image#fragment", "image%2Fsecret", "image\\secret", " image", "image\n", String(repeating: "a", count: 201)] {
        #expect(CommunityAvatarReference.mediaID(value) == nil)
    }
    #expect(CommunityAvatarReference.mediaID(nil) == nil)
}

@Test func communityProfileImagesDecodeWithoutRequiringThemForOlderResponses() throws {
    let base = #"{"id":"post-fiction","autorNome":"Profissional Fictício","conteudo":"Publicação fictícia","tipo":"post","anonimo":false,"curtidas":0,"compartilhamentos":0,"curtiu":false,"salvou":false,"criadoEm":"2030-01-01T00:00:00Z"}"#
    let decoder = JSONDecoder()
    let original = try decoder.decode(CommunityPost.self, from: Data(base.utf8))
    #expect(original.autorAvatarMidiaId == nil)
    let withAvatar = String(base.dropLast()) + #", "autorAvatarMidiaId":"mid_fixture"}"#
    #expect(try decoder.decode(CommunityPost.self, from: Data(withAvatar.utf8)).autorAvatarMidiaId == "mid_fixture")
    let suggestion = #"{"usuarioId":"member-fiction","nome":"Profissional Fictício","seguidores":0,"avatarMidiaId":"mid_fixture"}"#
    #expect(try decoder.decode(CommunitySuggestion.self, from: Data(suggestion.utf8)).avatarMidiaId == "mid_fixture")
    let member = #"{"usuarioId":"member-fiction","nome":"Profissional Fictício","avatarMidiaId":"mid_fixture"}"#
    #expect(try decoder.decode(CommunityConversation.Member.self, from: Data(member.utf8)).avatarMidiaId == "mid_fixture")
}

@Test func communityAvatarDownloadsUseOnlyTheAuthenticatedMediaRoute() async throws {
    let tokens = TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiraEm: 900)
    let transport = StubTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.scheme == "https" && request.url?.host == "api.atendebem.io")
        #expect(request.url?.path == "/v1/comunidade/midias/mid_fixture")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
        #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
        return ("fixture-image-bytes", 200)
    }
    let api = APIClient(storage: MemoryStorage(StoredSession(tokens: tokens)), transport: transport)
    _ = try await api.restoreSession()
    _ = try await api.communityImage(id: try #require(CommunityAvatarReference.mediaID("mid_fixture")))
    #expect(await transport.count("/v1/comunidade/midias/mid_fixture") == 1)
}
