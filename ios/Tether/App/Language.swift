import Foundation
import SwiftUI

/// The app's own language, chosen inside the app (Settings tab) — independent of the iOS system language.
/// Persian is the default on first launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case persian = "fa"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: self == .persian ? "fa_IR" : "en_US") }
    var layoutDirection: LayoutDirection { self == .persian ? .rightToLeft : .leftToRight }

    /// Each language's own name for itself, as in the iOS Settings language list.
    var displayName: String { self == .persian ? "فارسی" : "English" }

    /// The .lproj bundle holding this language's strings (the lookup keys are the English texts).
    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"), let bundle = Bundle(path: path) { return bundle }
        return .main
    }
}

/// The live language selection: SwiftUI observes it through the root environment, imperative code
/// reads `shared` (through `L10n`). Changing it re-renders the whole UI in the new language and
/// layout direction without an app restart.
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    private static let key = "app.language"

    @Published private(set) var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .persian
    }

    func setLanguage(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        language = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.key)
        // Paths that resolve against the process language and cannot follow the live SwiftUI
        // environment (e.g. App Intents) pick the choice up on the next launch.
        UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
        // Notification action titles are registered with the system: re-register them in the
        // new language (setUp is idempotent; the permission request is already answered).
        Notifications.shared.setUp()
    }

    /// The very first thing at launch: make the process resolve strings in the chosen language
    /// (default Persian) before any model or notification code runs. Skipped under unit tests,
    /// which drive the model, not the screens.
    static func applyAtLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        UserDefaults.standard.set([shared.language.rawValue], forKey: "AppleLanguages")
    }
}

/// Imperative localized strings that follow the in-app choice *live*. Plain `String(localized:)`
/// resolves against the process language fixed at launch; this helper looks the key up in the
/// chosen language's own .lproj bundle instead, so it is correct the moment the picker changes.
/// A key missing from the chosen bundle falls back to the key itself (the English source text).
enum L10n {
    static func string(_ value: String.LocalizationValue) -> String {
        let language = LanguageSettings.shared.language
        return String(localized: value, bundle: language.bundle, locale: language.locale)
    }
}

extension View {
    /// Locale + layout direction of the in-app language, for content shown in sheets and covers,
    /// which does not reliably inherit the root environment.
    func appLanguageEnvironment() -> some View {
        let language = LanguageSettings.shared.language
        return environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
    }
}
