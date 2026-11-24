import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatusPayload
    let language: String
}

struct StatusProvider: TimelineProvider {
    private func entry() -> StatusEntry {
        StatusEntry(date: Date(), status: WidgetStatusReader.load(), language: WidgetStatusReader.languageCode())
    }

    func placeholder(in context: Context) -> StatusEntry { entry() }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        // No schedule of its own: the app calls WidgetCenter.reloadAllTimelines() whenever
        // the published status changes, and the entry is re-read from the App Group then.
        completion(Timeline(entries: [entry()], policy: .never))
    }
}

private extension StatusEntry {
    func tr(_ key: String) -> String { WidgetL10n.string(key, language: language) }

    var stateText: String { tr(status.connected ? "Connected" : "Not connected") }

    /// SIM labels with the default SIM first, e.g. "Irancell · Personal · MCI".
    var simLine: String {
        status.sims
            .sorted { ($0.isDefault ? 0 : 1) < ($1.isDefault ? 0 : 1) }
            .map(\.label)
            .joined(separator: " · ")
    }

    /// The first SIM's initial (the default SIM's, when there are two), for the circular face.
    var simInitial: String? {
        status.sims
            .sorted { ($0.isDefault ? 0 : 1) < ($1.isDefault ? 0 : 1) }
            .first?.label.first.map(String.init)
    }

    /// Honest by design: the snapshot's age is part of the display, never implied live.
    var syncedText: String {
        guard let last = status.lastSync else { return tr("Not synced yet") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language == "fa" ? "fa_IR" : "en_US")
        formatter.unitsStyle = .short
        return tr("Last synced") + " " + formatter.localizedString(for: last, relativeTo: Date())
    }
}

/// Lock Screen faces are rendered in the system's tint, so connection state reads from
/// shape, not colour: a filled disc when connected, a hollow ring when not.
private struct StatusDot: View {
    let connected: Bool

    var body: some View {
        Group {
            if connected {
                Circle()
            } else {
                Circle().strokeBorder(lineWidth: 2)
            }
        }
        .frame(width: 11, height: 11)
    }
}

private struct RectangularView: View {
    let entry: StatusEntry

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(connected: entry.status.connected)
            VStack(alignment: .leading, spacing: 1) {
                Text("Anti Registry · \(entry.stateText)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !entry.simLine.isEmpty {
                    Text(entry.simLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.syncedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CircularView: View {
    let entry: StatusEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                // Filled handset when connected, outline handset when not — shape carries
                // the state in the monochrome Lock Screen treatment.
                Image(systemName: entry.status.connected ? "phone.fill" : "phone")
                    .font(.system(size: 15, weight: .semibold))
                if let initial = entry.simInitial {
                    Text(initial)
                        .font(.system(size: 9, weight: .semibold))
                }
            }
        }
    }
}

private struct InlineView: View {
    let entry: StatusEntry

    var body: some View {
        Text("Anti Registry · \(entry.stateText)")
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineView(entry: entry)
        case .accessoryCircular:
            CircularView(entry: entry)
        default:
            RectangularView(entry: entry)
        }
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AntiRegistryStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Anti Registry")
        .description(WidgetL10n.string("Link status and SIMs from the app's last sync.", language: WidgetStatusReader.languageCode()))
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
