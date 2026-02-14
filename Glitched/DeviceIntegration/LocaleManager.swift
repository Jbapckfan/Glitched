import UIKit
import Combine

/// Monitors device language/locale changes for locale-based puzzles
final class LocaleManager: DeviceManager {
    static let shared = LocaleManager()

    let supportedMechanics: Set<MechanicType> = [.locale]

    private var isActive = false
    private var lastLanguage: String = ""

    private init() {}

    func activate() {
        guard !isActive else { return }
        isActive = true

        lastLanguage = currentLanguageCode

        // Monitor for locale changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localeDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )

        // Post initial
        DispatchQueue.main.async {
            InputEventBus.shared.post(.localeChanged(language: self.currentLanguageCode))
        }

        print("LocaleManager: Activated - Language: \(currentLanguageCode)")
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        NotificationCenter.default.removeObserver(self)
        print("LocaleManager: Deactivated")
    }

    @objc private func localeDidChange() {
        let newLanguage = currentLanguageCode
        if newLanguage != lastLanguage {
            lastLanguage = newLanguage
            DispatchQueue.main.async {
                InputEventBus.shared.post(.localeChanged(language: newLanguage))
            }
        }
    }

    var currentLanguageCode: String {
        if #available(iOS 16, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }

    var currentLanguageName: String {
        Locale.current.localizedString(forLanguageCode: currentLanguageCode) ?? "English"
    }

    /// Whether the current language differs from English
    var isNonEnglish: Bool {
        currentLanguageCode != "en"
    }
}
