import Foundation
import Testing
@testable import Anvil

struct FeatureFlagTests {
    @Test
    func diagnosticWholeFileRewriteFeatureFlagDefaultsOff() throws {
        let userDefaults = try Self.makeIsolatedUserDefaults()

        #expect(!AnvilFeatureFlags.isDiagnosticWholeFileRewriteEnabled(
            userDefaults: userDefaults
        ))
    }

    @Test
    func diagnosticWholeFileRewriteFeatureFlagReadsAndWritesPreferenceKey() throws {
        let userDefaults = try Self.makeIsolatedUserDefaults()

        AnvilFeatureFlags.setDiagnosticWholeFileRewriteEnabled(
            true,
            userDefaults: userDefaults
        )
        #expect(AnvilFeatureFlags.isDiagnosticWholeFileRewriteEnabled(
            userDefaults: userDefaults
        ))
        #expect(userDefaults.bool(
            forKey: AnvilPreferenceKeys.featureDiagnosticWholeFileRewriteEnabled
        ))

        AnvilFeatureFlags.setDiagnosticWholeFileRewriteEnabled(
            false,
            userDefaults: userDefaults
        )
        #expect(!AnvilFeatureFlags.isDiagnosticWholeFileRewriteEnabled(
            userDefaults: userDefaults
        ))
    }

    private static func makeIsolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "AnvilTests.FeatureFlags.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
