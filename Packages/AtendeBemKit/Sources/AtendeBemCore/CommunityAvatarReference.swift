import Foundation

/// Community avatars are authenticated media identifiers, never arbitrary download URLs.
public enum CommunityAvatarReference {
    public static func mediaID(_ value: String?, anonymous: Bool = false) -> String? {
        guard !anonymous, let value, !value.isEmpty, value.utf8.count <= 200,
              value.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (97...122).contains($0.value) ||
                  (48...57).contains($0.value) || $0 == "_" || $0 == "-"
              }) else { return nil }
        return value
    }
}
