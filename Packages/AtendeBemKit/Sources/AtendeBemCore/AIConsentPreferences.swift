import Foundation
import Observation

/// This local preference authorizes general text only. It contains no messages,
/// patient references, audio permissions or authorization to perform clinical acts.
@MainActor @Observable public final class AIConsentPreferences {
    /// Change whenever providers, transmitted data or the disclosed purpose change.
    public static let currentPolicyVersion = "general-text-anthropic-google-2026-10-03-v1"
    public let policyVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    private var grants: [String: String]
    private static let storageKey = "atendebem.ai-consent.general-text.scopes.v1"
    private static let activeStores = NSHashTable<AIConsentPreferences>.weakObjects()

    public init(defaults: UserDefaults = .standard, policyVersion: String = currentPolicyVersion) {
        self.defaults = defaults
        self.policyVersion = policyVersion
        grants = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        Self.activeStores.add(self)
    }

    public func hasGeneralTextConsent(userID: String?, clinicID: String?) -> Bool {
        guard !policyVersion.isEmpty, let key = scopeKey(userID: userID, clinicID: clinicID) else { return false }
        // Track in-process updates, but authorize against the latest persisted
        // value so another scene cannot continue with a revoked snapshot.
        _ = grants
        let current = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        return current[key] == policyVersion
    }

    /// Called only after an explicit toggle or revocation, never to synchronize
    /// a view's initial false state. Observation updates every open view using this store.
    public func setGeneralTextConsent(_ granted: Bool, userID: String?, clinicID: String?) {
        guard !policyVersion.isEmpty, let key = scopeKey(userID: userID, clinicID: clinicID) else { return }
        // Merge the stored map so another account's grant is never overwritten by
        // an older instance of this preference object.
        var updated = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        if granted { updated[key] = policyVersion }
        else { updated.removeValue(forKey: key) }
        if updated.isEmpty { defaults.removeObject(forKey: Self.storageKey) }
        else { defaults.set(updated, forKey: Self.storageKey) }
        grants = updated
        for store in Self.activeStores.allObjects { store.reload() }
    }

    /// Refresh local preferences when returning from another scene on this device.
    public func reload() {
        grants = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    private func scopeKey(userID: String?, clinicID: String?) -> String? {
        guard let userID, let clinicID,
              !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !clinicID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Base64 segments cannot contain '.', so opaque identifiers cannot collide
        // through separators ("a.b"/"c" versus "a"/"b.c", for example).
        return Data(userID.utf8).base64EncodedString() + "." + Data(clinicID.utf8).base64EncodedString()
    }
}
