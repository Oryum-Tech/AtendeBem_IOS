import Foundation
import Observation
import Testing
@testable import AtendeBemCore

@Test @MainActor func revocationInAnotherSceneInvalidatesGeneralConsentImmediately() async throws {
    try await confirmation("Open scene observes revocation", expectedCount: 1) { changed in
        try withConsentDefaults { defaults in
            let first = AIConsentPreferences(defaults: defaults)
            let second = AIConsentPreferences(defaults: defaults)
            first.setGeneralTextConsent(true, userID: "doctor", clinicID: "clinic")
            withObservationTracking {
                _ = first.hasGeneralTextConsent(userID: "doctor", clinicID: "clinic")
            } onChange: { changed() }
            second.setGeneralTextConsent(false, userID: "doctor", clinicID: "clinic")
            #expect(!first.hasGeneralTextConsent(userID: "doctor", clinicID: "clinic"))
        }
    }
}

@MainActor private func withConsentDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "AtendeBemConsentTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

@Test @MainActor func generalAIConsentPersistsOnlyAfterExplicitGrant() throws {
    try withConsentDefaults { defaults in
        let first = AIConsentPreferences(defaults: defaults)
        #expect(!first.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("atendebem.ai-consent") }.isEmpty)
        first.setGeneralTextConsent(true, userID: "doctor-a", clinicID: "clinic-a")
        let relaunched = AIConsentPreferences(defaults: defaults)
        #expect(relaunched.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
    }
}

@Test @MainActor func generalAIConsentDoesNotCrossAccountsClinicsOrOpaqueIDBoundaries() throws {
    try withConsentDefaults { defaults in
        let store = AIConsentPreferences(defaults: defaults)
        store.setGeneralTextConsent(true, userID: "a.b", clinicID: "c")
        #expect(store.hasGeneralTextConsent(userID: "a.b", clinicID: "c"))
        #expect(!store.hasGeneralTextConsent(userID: "a", clinicID: "b.c"))
        #expect(!store.hasGeneralTextConsent(userID: "another-user", clinicID: "c"))
        #expect(!store.hasGeneralTextConsent(userID: "a.b", clinicID: "another-clinic"))
        store.setGeneralTextConsent(true, userID: nil, clinicID: "c")
        store.setGeneralTextConsent(true, userID: "a.b", clinicID: "  ")
        #expect(!store.hasGeneralTextConsent(userID: nil, clinicID: "c"))
        #expect(!store.hasGeneralTextConsent(userID: "a.b", clinicID: "  "))
    }
}

@Test @MainActor func generalAIConsentRevocationPersistsAndPreservesOtherScopes() throws {
    try withConsentDefaults { defaults in
        let store = AIConsentPreferences(defaults: defaults)
        store.setGeneralTextConsent(true, userID: "doctor-a", clinicID: "clinic-a")
        store.setGeneralTextConsent(true, userID: "doctor-a", clinicID: "clinic-b")
        store.setGeneralTextConsent(false, userID: "doctor-a", clinicID: "clinic-a")
        #expect(!store.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
        let relaunched = AIConsentPreferences(defaults: defaults)
        #expect(!relaunched.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
        #expect(relaunched.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-b"))
    }
}

@Test @MainActor func changedAIProcessingPolicyRequiresAnotherExplicitGrant() throws {
    try withConsentDefaults { defaults in
        let old = AIConsentPreferences(defaults: defaults, policyVersion: "old-providers-and-purpose")
        old.setGeneralTextConsent(true, userID: "doctor-a", clinicID: "clinic-a")
        let revised = AIConsentPreferences(defaults: defaults, policyVersion: "new-providers-and-purpose")
        #expect(!revised.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
        revised.setGeneralTextConsent(true, userID: "doctor-a", clinicID: "clinic-a")
        #expect(AIConsentPreferences(defaults: defaults, policyVersion: "new-providers-and-purpose")
            .hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
        #expect(!AIConsentPreferences(defaults: defaults, policyVersion: "old-providers-and-purpose")
            .hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
    }
}

@Test @MainActor func independentConsentStoresMergeWithoutRemovingOtherAccounts() throws {
    try withConsentDefaults { defaults in
        let first = AIConsentPreferences(defaults: defaults)
        let second = AIConsentPreferences(defaults: defaults)
        first.setGeneralTextConsent(true, userID: "doctor-a", clinicID: "clinic-a")
        second.setGeneralTextConsent(true, userID: "doctor-b", clinicID: "clinic-b")
        first.reload()
        #expect(first.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
        #expect(first.hasGeneralTextConsent(userID: "doctor-b", clinicID: "clinic-b"))
        second.setGeneralTextConsent(false, userID: "doctor-a", clinicID: "clinic-a")
        first.reload()
        #expect(!first.hasGeneralTextConsent(userID: "doctor-a", clinicID: "clinic-a"))
    }
}
