import Perception
import SwiftUI
import TetherCore

struct RootView: View {
    @Environment(\.appModel) private var model
    @Environment(\.router) private var router

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        @Perception.Bindable var router = router
        @Perception.Bindable var model = model
        VStack(spacing: 0) {
            ReturnToCallBanner()
            RemoteCallBanner()
            TabView(selection: $router.tab) {
                RecentsView()
                    .tabItem { Label("Recents", systemImage: "clock") }
                    .badge(model.missedCount)
                    .tag(Router.Tab.recents)
                ContactsView()
                    .tabItem { Label("Contacts", systemImage: "person.crop.circle") }
                    .tag(Router.Tab.contacts)
                KeypadView()
                    .tabItem { Label("Keypad", systemImage: "circle.grid.3x3.fill") }
                    .tag(Router.Tab.keypad)
                MessagesView()
                    .tabItem { Label("Messages", systemImage: "message") }
                    .badge(model.unreadTotal)
                    .tag(Router.Tab.messages)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Router.Tab.settings)
            }
        }
        .overlay(alignment: .bottom) {
            if let err = model.lastError {
                Text(err)
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 64)
                    .onTapGesture { model.lastError = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let n = model.notice {
                Label(n, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert(item: $router.dialRequest) { req in
            let linked = model.linkState.isConnected
            let who = model.name(for: req.number)
            return Alert(
                title: Text("Call \(who ?? model.formatted(req.number))?"),
                message: Text(linked
                    ? (who == nil ? "The call goes through your Android phone." : "\(model.formatted(req.number)) · through your Android phone.")
                    : "The Android phone is not connected. Keep it nearby and open the Settings tab, then call from the Keypad."),
                primaryButton: .default(Text(linked ? "Call" : "Show in Keypad")) {
                    if linked { model.dial(req.number, sub: nil) } else { router.keypadNumber = req.number }
                },
                secondaryButton: .cancel { router.keypadNumber = req.number })
        }
        .animation(.default, value: model.lastError)
        .animation(.default, value: model.notice)
        .fullScreenCover(isPresented: Binding(get: { model.showCallScreen && model.callScreen != nil },
                                              set: { model.showCallScreen = $0 })) {
            // Presented content does not always inherit environment objects: pass them explicitly.
            InCallView().environment(\.appModel, AppModel.shared).environment(\.router, Router.shared).appLanguageEnvironment()
        }
        .preferredColorScheme(.dark)
        .tint(Color("AccentColor"))
        .task {
            if !model.isPaired { router.tab = .settings }
        }
    }
}

/// A call whose audio is on the other device (answered or dialed there): one tap moves it here.
struct RemoteCallBanner: View {
    @Environment(\.appModel) private var model

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        ForEach(model.remoteCalls, id: \.cid) { c in
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName(c.num)).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text("On \(c.at ?? L10n.string("another device"))").font(.caption2).opacity(0.85)
                }
                Spacer()
                Button {
                    model.calls.take(c.cid)
                } label: {
                    Text("Move here").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.indigo)
        }
    }
}

/// One SIM of the Android phone: bars, network type (5G / LTE+ / H+ …), roaming, or "No service".
struct SimStatus: View {
    let sim: SimInfo
    var showName = true

    var body: some View {
        HStack(spacing: 3) {
            if showName { Text(sim.name).font(.caption2).lineLimit(1) }
            if sim.hasService {
                SignalBars(level: sim.signal)
                if let n = sim.net { Text(n).font(.caption2.weight(.semibold)) }
                if sim.roaming == true { Text("R").font(.caption2.weight(.bold)).foregroundStyle(.orange) }
            } else {
                Text(sim.service == "emergency" ? "SOS" : L10n.string("No service")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SignalBars: View {
    let level: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
        .accessibilityLabel(Text("Signal \(level) of 4"))
    }
}

struct Avatar: View {
    let name: String
    var photo: String? = nil
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let photo, let data = Data(base64Encoded: photo), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.65, green: 0.67, blue: 0.72), Color(red: 0.52, green: 0.54, blue: 0.58)],
                                   startPoint: .top, endPoint: .bottom)
                    if let text = AvatarImage.initials(name) {
                        Text(text).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: size * 0.5)).foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// SIM choice for a call or a conversation.
struct SimPicker: View {
    @Environment(\.appModel) private var model
    @Binding var sub: Int?

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        if model.sims.count > 1 {
            Menu {
                ForEach(model.sims) { sim in
                    Button {
                        sub = sim.sub
                    } label: {
                        Label("\(sim.name) · \(sim.carrier)", systemImage: sub == sim.sub ? "checkmark" : "simcard")
                    }
                }
                .onAppear { hideKeyboard() }   // the menu must not open under / over the keyboard
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "simcard")
                    Text(label).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }

    private var label: String {
        guard let sim = model.sims.first(where: { $0.sub == sub }) else { return L10n.string("SIM") }
        return sim.name.isEmpty ? "SIM \(sim.slot + 1)" : sim.name
    }
}

extension Date {
    init(millis: Int64) { self.init(timeIntervalSince1970: Double(millis) / 1000) }
}

func shortTime(_ ms: Int64) -> String {
    let d = Date(millis: ms)
    if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
    if Calendar.current.isDateInYesterday(d) { return L10n.string("Yesterday") }
    return d.formatted(.dateTime.day().month(.abbreviated))
}


/// Puts the keyboard away (before a menu, sheet or dialog opens over a text field).
@MainActor func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// A "Done" button above number / phone pads, which have no return key to close them.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }.fontWeight(.semibold)
            }
        }
    }
}
