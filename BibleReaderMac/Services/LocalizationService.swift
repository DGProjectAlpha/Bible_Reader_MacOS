import Foundation
import Observation

// MARK: - Localization Service

/// Observable singleton that drives in-app language switching.
/// Views that call L() automatically re-render when `language` changes
/// because @Observable tracks the `language` property access.
@Observable final class LocalizationService {

    static let shared = LocalizationService()

    /// Current language code — "en" or "ru".
    var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "appLanguage")
        }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    /// Look up a localized string by key, falling back to English then the key itself.
    func string(_ key: String) -> String {
        Strings.table[key]?[language] ?? Strings.table[key]?["en"] ?? key
    }
}

// MARK: - Convenience global

/// Short-form localization lookup. Call L("key") anywhere in the UI.
func L(_ key: String) -> String {
    LocalizationService.shared.string(key)
}
