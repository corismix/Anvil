import Foundation

struct AppleFoundationModelPreferenceStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: AnvilPreferenceKeys.appleFoundationModelEnabled)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: AnvilPreferenceKeys.appleFoundationModelEnabled)
        }
    }
}
