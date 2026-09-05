import Foundation

enum AnvilFeatureFlags {
    nonisolated static func isDiagnosticWholeFileRewriteEnabled(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.bool(
            forKey: AnvilPreferenceKeys.featureDiagnosticWholeFileRewriteEnabled
        )
    }

    nonisolated static func setDiagnosticWholeFileRewriteEnabled(
        _ isEnabled: Bool,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(
            isEnabled,
            forKey: AnvilPreferenceKeys.featureDiagnosticWholeFileRewriteEnabled
        )
    }

    nonisolated static func isCoverageCheckEnabled(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard let value = userDefaults.object(
            forKey: AnvilPreferenceKeys.featureCoverageCheckEnabled
        ) as? Bool else {
            return true
        }
        return value
    }

    nonisolated static func setCoverageCheckEnabled(
        _ isEnabled: Bool,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(
            isEnabled,
            forKey: AnvilPreferenceKeys.featureCoverageCheckEnabled
        )
    }
}
