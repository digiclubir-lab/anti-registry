import Foundation

/// The status payload the app publishes into the shared App Group. This target declares its
/// own copy of the shape (see Tether/App/WidgetStatus.swift in the app target) — the two
/// targets share the JSON in the group defaults, not code. The widget only reads.
struct WidgetSim: Codable, Equatable {
    var label: String
    var isDefault: Bool
}

struct WidgetStatusPayload: Codable, Equatable {
    var connected: Bool
    var sims: [WidgetSim]
    var lastSync: Date?

    static let empty = WidgetStatusPayload(connected: false, sims: [], lastSync: nil)
}

enum WidgetStatusReader {
    private static let groupID = "group.com.amirmohammadyavari.antiregistry"
    private static let statusKey = "widget.status"
    private static let languageKey = "app.language"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func load() -> WidgetStatusPayload {
        guard let data = defaults?.data(forKey: statusKey),
              let payload = try? JSONDecoder().decode(WidgetStatusPayload.self, from: data)
        else { return .empty }
        return payload
    }

    /// The language the widget renders in: the app's own choice, mirrored into the group
    /// defaults ("fa" / "en"). "auto" — or nothing written yet — follows the system, with a
    /// Persian system meaning Persian, exactly as the app resolves it.
    static func languageCode() -> String {
        switch defaults?.string(forKey: languageKey) {
        case "fa": return "fa"
        case "en": return "en"
        default: return (Locale.preferredLanguages.first?.hasPrefix("fa") ?? false) ? "fa" : "en"
        }
    }
}

/// Strings from this extension's own .lproj bundles for the app's chosen language. The
/// process language follows the system, which is not always the language the app runs in,
/// so lookups go through the chosen language's bundle directly (as the app's L10n does).
enum WidgetL10n {
    static func string(_ key: String, language: String) -> String {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: bundle, value: key, comment: "")
        }
        return NSLocalizedString(key, value: key, comment: "")
    }
}
