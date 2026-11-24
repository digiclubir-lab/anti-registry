import Foundation
import SwiftUI

/// A language the UI can actually run in — the two this app ships.
enum AppLanguage: String, CaseIterable, Identifiable {
    case persian = "fa"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: self == .persian ? "fa_IR" : "en_US") }
    var layoutDirection: LayoutDirection { self == .persian ? .rightToLeft : .leftToRight }

    /// The calendar dates are rendered in while this language runs: the Persian (Shamsi)
    /// calendar for Persian, Gregorian for English. Day boundaries are the local midnights
    /// in both, so Today/Yesterday pick out the same days — only the numbering differs.
    var calendar: Calendar {
        var calendar = Calendar(identifier: self == .persian ? .persian : .gregorian)
        calendar.locale = locale
        return calendar
    }

    /// The .lproj bundle holding this language's strings (the lookup keys are the English texts).
    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"), let bundle = Bundle(path: path) { return bundle }
        return .main
    }
}

/// What the user picked in the Settings language picker: a fixed language, or Automatic,
/// which follows the iPhone's system language. Persian is the default on first launch.
/// The raw values for the fixed choices match `AppLanguage`'s, so a selection stored by an
/// earlier build (which only knew the two fixed languages) still reads correctly.
enum LanguagePreference: String, CaseIterable, Identifiable {
    case persian = "fa"
    case english = "en"
    case automatic = "auto"

    var id: String { rawValue }

    /// The fixed languages show each language's own name for itself, as in the iOS Settings
    /// language list; Automatic is named in the language the UI currently runs in.
    var displayName: String {
        switch self {
        case .persian: return "فارسی"
        case .english: return "English"
        case .automatic: return L10n.string("Automatic")
        }
    }
}

/// The live language selection: SwiftUI observes it through the root environment, imperative code
/// reads `shared` (through `L10n`). `preference` is what the user picked; `language` is the
/// effective language the UI runs in — the pick itself, or the system language under Automatic.
/// Changing either re-renders the whole UI in the new language and layout direction without
/// an app restart.
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    private static let key = "app.language"
    private static let systemKey = "app.systemLanguage"

    @Published private(set) var preference: LanguagePreference
    @Published private(set) var language: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        preference = raw.flatMap(LanguagePreference.init(rawValue:)) ?? .persian
        language = Self.resolve(preference, system: Self.capturedSystemLanguage())
    }

    func setPreference(_ newValue: LanguagePreference) {
        guard newValue != preference else { return }
        preference = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.key)
        if newValue == .automatic {
            // Drop the process-language override (written for fixed picks): with none in
            // place, Locale.preferredLanguages is the system's own list again, so the next
            // launch captures it exactly. This session resolves from the latest capture.
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        applyEffective(Self.resolve(newValue, system: Self.capturedSystemLanguage()))
    }

    /// Follows an effective-language change: fixed picks also pin the process language (paths
    /// that resolve against it and cannot follow the live SwiftUI environment, e.g. App Intents,
    /// pick it up on the next launch), and notification action titles — registered with the
    /// system — are re-registered in the new language (setUp is idempotent; the permission
    /// request is already answered).
    private func applyEffective(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        language = newValue
        if preference != .automatic {
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
        }
        Notifications.shared.setUp()
    }

    private static func resolve(_ preference: LanguagePreference, system: AppLanguage) -> AppLanguage {
        switch preference {
        case .persian: return .persian
        case .english: return .english
        case .automatic: return system
        }
    }

    /// The system language, reduced to the two supported ones (Persian system → Persian,
    /// anything else → English). The value is captured from Locale.preferredLanguages the
    /// first time it is read — before any override exists — and re-captured at every launch
    /// spent in Automatic, when no override is in the way (see applyAtLaunch). It cannot be
    /// read live on demand: the fixed picks pin AppleLanguages, which is exactly what
    /// preferredLanguages reports.
    private static func capturedSystemLanguage() -> AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: systemKey),
           let language = AppLanguage(rawValue: raw) { return language }
        let language = systemLanguage()
        UserDefaults.standard.set(language.rawValue, forKey: systemKey)
        return language
    }

    private static func systemLanguage() -> AppLanguage {
        (Locale.preferredLanguages.first?.hasPrefix("fa") ?? false) ? .persian : .english
    }

    /// The very first thing at launch: make the process resolve strings in the effective
    /// language (default Persian) before any model or notification code runs. In Automatic
    /// there is no override to write — the process follows the system — so instead the
    /// captured system language is refreshed from the (override-free) preferred list and
    /// the effective language follows it. Skipped under unit tests, which drive the model,
    /// not the screens.
    static func applyAtLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let settings = shared
        if settings.preference == .automatic {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            let system = systemLanguage()
            UserDefaults.standard.set(system.rawValue, forKey: systemKey)
            if system != settings.language { settings.language = system }
        } else {
            UserDefaults.standard.set([settings.language.rawValue], forKey: "AppleLanguages")
        }
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
