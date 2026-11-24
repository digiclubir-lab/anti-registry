import Perception
import SwiftUI
import TetherCore

struct RecentsView: View {
    @Environment(\.appModel) private var model
    @State private var missedOnly = false
    @State private var search = ""
    @State private var blocking: String?
    @State private var clearing = false

    private func message(_ num: String) {
        Router.shared.tab = .messages
        if let t = model.thread(for: num) { Router.shared.openThread = t } else { Router.shared.compose(to: num) }
    }

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            List(entries) { e in
                HStack(spacing: 12) {
                    Avatar(name: e.name ?? model.displayName(e.num), photo: model.photo(for: e.num), size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.name ?? model.displayName(e.num))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(e.type == 3 || e.type == 5 ? .red : .primary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Image(systemName: arrow(e.type)).font(.system(size: 11, weight: .semibold))
                            Text(secondaryLine(e)).lineLimit(1)
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(shortTime(e.date)).font(.subheadline).foregroundStyle(.secondary)
                    Button { model.dial(e.num, sub: e.sub) } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.blue)
                            .frame(width: 38, height: 38)
                            .background(Color(.secondarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.dial(e.num, sub: e.sub) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Like Phone: a swipe deletes the entry at once (from the Android phone and every device).
                    Button(role: .destructive) { model.deleteRecents([e.id]) } label: { Label("Delete", systemImage: "trash") }
                    Button { message(e.num) } label: { Label("Message", systemImage: "message") }
                }
                .contextMenu {
                    Button { model.dial(e.num, sub: e.sub) } label: { Label("Call", systemImage: "phone") }
                    Button { message(e.num) } label: { Label("Message", systemImage: "message") }
                    Button { UIPasteboard.general.string = e.num } label: { Label("Copy", systemImage: "doc.on.doc") }
                    if model.isBlocked(e.num) {
                        Button { model.setBlocked(e.num, false) } label: { Label("Unblock this Caller", systemImage: "hand.raised.slash") }
                    } else {
                        Button(role: .destructive) { blocking = e.num } label: { Label("Block this Caller", systemImage: "hand.raised") }
                    }
                    Button(role: .destructive) { model.deleteRecents([e.id]) } label: { Label("Delete from Recents", systemImage: "trash") }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { model.requestSync() }
            .onAppear { model.markRecentsSeen() }
            // Seen only while the user can see it: a call missed in the background keeps its badge.
            .onChangeCompat(of: model.data.recents.first?.id) { _ in if Router.shared.tab == .recents && model.appActive { model.markRecentsSeen() } }
            .onChangeCompat(of: model.appActive) { on in if on && Router.shared.tab == .recents { model.markRecentsSeen() } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search name or number"))
            .overlay {
                if !search.isEmpty && entries.isEmpty { EmptyStateView(searchText: search) }
            }
            .overlay {
                if model.data.recents.isEmpty { EmptyStateView("No recent calls", systemImage: "clock") }
            }
            .navigationTitle("Recents")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(blocking.map { model.displayName($0) } ?? "",
                                isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
                if let n = blocking { Button("Block Contact", role: .destructive) { model.setBlocked(n, true) } }
            } message: {
                Text("You will not receive phone calls or messages from people on the block list.")
            }
            .confirmationDialog("Clear All Recents", isPresented: $clearing, titleVisibility: .hidden) {
                Button("Clear All Recents", role: .destructive) { model.clearRecents() }
            } message: {
                Text("The call history will be deleted from your Android phone and all your devices.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { clearing = true }
                        .disabled(model.data.recents.isEmpty || !model.linkState.isConnected)
                }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $missedOnly) {
                        Text("All").tag(false)
                        Text("Missed").tag(true)
                    }.pickerStyle(.segmented).frame(width: 180)
                }
            }
        }
    }

    private var entries: [CallEntry] {
        var list = model.data.recents
        if missedOnly { list = list.filter { $0.type == 3 || $0.type == 5 } }
        if !search.isEmpty {
            list = list.filter { e in SearchText.matches(search, names: [e.name ?? "", model.name(for: e.num) ?? ""], numbers: [e.num]) }
        }
        return Array(list.prefix(500))
    }

    /// The small direction arrow in the row's second line, as in Phone: down-left for incoming
    /// (missed and rejected included), up-right for outgoing.
    private func arrow(_ type: Int) -> String {
        switch type {
        case 2: "arrow.up.right"
        case 6: "nosign"
        default: "arrow.down.left"
        }
    }

    /// Second line of a Recents row: the number (formatted for a known contact, raw otherwise,
    /// LTR-isolated so it reads correctly in the RTL layout), plus the duration when there was one.
    private func secondaryLine(_ e: CallEntry) -> String {
        let number = e.name != nil || model.name(for: e.num) != nil ? model.formatted(e.num) : e.num
        var parts = ["\u{2066}\(number)\u{2069}"]
        if e.dur > 0 { parts.append(Duration.seconds(e.dur).formatted(.time(pattern: .minuteSecond))) }
        return parts.joined(separator: " · ")
    }
}

/// An Apple-style dial key: a soft system-filled circle that brightens while pressed.
/// The fills are system background colours, so the keypad reads correctly in both colour schemes.
private struct DialKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 80, height: 80)
            .background(configuration.isPressed ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground), in: Circle())
            .contentShape(Circle())
    }
}

struct KeypadView: View {
    @Environment(\.appModel) private var model
    @Environment(\.router) private var router
    @State private var number = ""
    @State private var longPressedZero = false

    private let keys: [[(String, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", ""), ("0", "+"), ("#", "")],
    ]

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(number.isEmpty ? " " : model.formatted(number))
                .font(.system(size: 40, weight: .light))
                .lineLimit(1).minimumScaleFactor(0.5)
                .environment(\.layoutDirection, .leftToRight)
                .contextMenu {
                    Button { if let s = UIPasteboard.general.string { number = PhoneNumber.digits(s) } } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                }
            if let name = model.name(for: number), !number.isEmpty {
                Text(name).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button { if let s = UIPasteboard.general.string { number = PhoneNumber.digits(s) } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard").font(.caption)
                }
            }
            VStack(spacing: 16) {
                ForEach(keys.indices, id: \.self) { r in
                    HStack(spacing: 26) {
                        ForEach(keys[r], id: \.0) { k in
                            Button { if k.0 == "0" && longPressedZero { longPressedZero = false } else { longPressedZero = false; number.append(k.0) } } label: {
                                VStack(spacing: 1) {
                                    Text(k.0).font(.system(size: 34, weight: .light))
                                    if !k.1.isEmpty {
                                        Text(k.1).font(.system(size: 10, weight: .semibold))
                                            .tracking(k.1.count > 1 ? 2 : 0)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(DialKeyStyle())
                            // Hold 0 for "+" (the tap that ends the hold must not add a 0 as well).
                            .simultaneousGesture(LongPressGesture().onEnded { _ in if k.0 == "0" { number.append("+"); longPressedZero = true } })
                        }
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 26) {
                Color.clear.frame(width: 80, height: 80)
                Button { model.dial(number, sub: nil) } label: {
                    Image(systemName: "phone.fill").font(.system(size: 30)).foregroundStyle(.white).accessibilityLabel(Text("Call"))
                        .frame(width: 80, height: 80).background(.green, in: Circle())
                }
                .disabled(number.isEmpty || !model.linkState.isConnected)
                Button { if !number.isEmpty { number.removeLast() } } label: {
                    Image(systemName: "delete.left").font(.system(size: 26)).foregroundStyle(.primary).frame(width: 80, height: 80).accessibilityLabel(Text("Delete"))
                }
                .opacity(number.isEmpty ? 0 : 1)
            }
            .environment(\.layoutDirection, .leftToRight)
            Spacer()
        }
        .onAppear {
            #if DEBUG
            // -TetherDemoKeypad <digits>: a typed number, to check the as-you-type grouping.
            let args = ProcessInfo.processInfo.arguments
            if number.isEmpty, let i = args.firstIndex(of: "-TetherDemoKeypad"), i + 1 < args.count { number = args[i + 1] }
            #endif
            takeRouted()
        }
        .onChangeCompat(of: router.keypadNumber) { _ in takeRouted() }
    }

    /// A number from a link the owner did not call yet (cancelled, or the Android phone was not connected).
    private func takeRouted() {
        guard let n = router.keypadNumber else { return }
        number = n
        router.keypadNumber = nil
    }
}
