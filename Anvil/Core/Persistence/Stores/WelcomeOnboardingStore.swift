import Foundation

struct WelcomeOnboardingStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompleted: Bool {
        userDefaults.bool(forKey: AnvilPreferenceKeys.hasCompletedWelcomeOnboarding)
    }

    func complete() {
        userDefaults.set(true, forKey: AnvilPreferenceKeys.hasCompletedWelcomeOnboarding)
    }
}
