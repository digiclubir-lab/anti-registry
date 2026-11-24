import Foundation
import WidgetKit

/// The App Group the app and the Lock Screen widget extension share. The app is the only
/// writer; the widget only reads. The id derives from the app's bundle id.
enum AppGroup {
    static let id = "group.com.amirmohammadyavari.antiregistry"
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// One SIM as the widget shows it: a display label ("Irancell · Personal") and whether it is
/// the Android phone's default SIM. The widget target declares its own copy of this shape —
/// the two targets share the JSON in the group defaults, not code.
struct WidgetSim: Codable, Equatable {
    var label: String
    var isDefault: Bool
}

/// The tiny status payload behind the Lock Screen widget: link state, SIMs and the moment
/// the last sync completed. It is a snapshot of the app's last known state, never live —
/// the widget labels it with the sync time.
struct WidgetStatusPayload: Codable, Equatable {
    var connected: Bool
    var sims: [WidgetSim]
    var lastSync: Date?
}

enum WidgetStatusStore {
    private static let key = "widget.status"

    /// Writes the payload to the group defaults and asks WidgetKit for fresh timelines.
    /// An unchanged payload is skipped, so frequent status messages from the phone do not
    /// burn the widget's reload budget.
    static func publish(_ payload: WidgetStatusPayload) {
        guard let defaults = AppGroup.defaults,
              let data = try? JSONEncoder().encode(payload) else { return }
        guard defaults.data(forKey: key) != data else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
