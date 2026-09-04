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
}
