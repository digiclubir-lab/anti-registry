import Perception
import SwiftUI
import TetherCore

struct ContactsView: View {
    @Environment(\.appModel) private var model
    @State private var search = ""
    @State private var adding = false

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            List {
                // Favourites first, as in the Phone app (the Android phone's starred contacts).
                if search.isEmpty && !model.favourites.isEmpty {
                    Section("Favourites") {
                        ForEach(model.favourites) { c in FavouriteRow(contact: c) }
                    }
                }
                // Letter sections, as in Contacts; while searching, one flat list.
                if search.isEmpty {
                    ForEach(grouped, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.items) { c in contactRow(c) }
                        }
                    }
                } else {
                    Section {
                        ForEach(filtered) { c in contactRow(c) }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.data.contacts.isEmpty { EmptyStateView("No contacts", systemImage: "person.crop.circle") }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search contacts"))
            .scrollDismissesKeyboard(.immediately)
            .refreshable { model.requestSync() }
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { hideKeyboard(); adding = true } label: { Image(systemName: "plus") }.disabled(!model.linkState.isConnected)
                }
            }
            .sheet(isPresented: $adding) { AddContactView().environment(\.appModel, AppModel.shared).environment(\.router, Router.shared).appLanguageEnvironment() }
        }
    }

    private var filtered: [Contact] {
        guard !search.isEmpty else { return model.data.contacts }
        return model.data.contacts.filter { c in
            SearchText.matches(search, names: [c.name] + c.emails, numbers: c.phones.map(\.n))
        }
    }

    /// One list row: photo (or initials) first, then the name, as in Contacts.
    private func contactRow(_ c: Contact) -> some View {
        NavigationLink {
            ContactDetailView(contact: c)
        } label: {
            HStack(spacing: 12) {
                Avatar(name: c.name, photo: c.photo, size: 48)
                Text(c.name).fontWeight(.semibold).lineLimit(1)
                if c.starred { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            }
            .padding(.vertical, 2)
        }
    }

    private struct ContactGroup: Identifiable {
        let key: String
        let items: [Contact]
        var id: String { key }
    }

    /// Contacts grouped by their first letter ("#" for names not starting with a letter),
    /// in alphabetical order with "#" last. Persian names group under their own letter.
    private var grouped: [ContactGroup] {
        var byKey: [String: [Contact]] = [:]
        for c in filtered { byKey[Self.sectionKey(c.name), default: []].append(c) }
        return byKey
            .sorted { a, b in
                if a.key == "#" { return false }
                if b.key == "#" { return true }
                return a.key < b.key
            }
            .map { ContactGroup(key: $0.key, items: $0.value) }
    }

    private static func sectionKey(_ name: String) -> String {
        guard let ch = name.trimmingCharacters(in: .whitespaces).first, ch.isLetter else { return "#" }
        return String(ch).uppercased()
    }
}

/// A favourite: tap to call (its first number, on the SIM last used with it), ⓘ for the contact.
struct FavouriteRow: View {
    @Environment(\.appModel) private var model
    let contact: Contact

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        HStack(spacing: 12) {
            Avatar(name: contact.name, photo: contact.photo, size: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name).fontWeight(.semibold)
                if let p = contact.phones.first {
                    Text(LocalizedStringKey(p.type.capitalized)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            NavigationLink { ContactDetailView(contact: contact) } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let p = contact.phones.first { model.dial(p.n, sub: model.preferredSim(for: p.n)) }
        }
        .swipeActions {
            Button { model.setStarred(contact.id, false) } label: { Label("Remove", systemImage: "star.slash") }.tint(.orange)
        }
    }
}

struct ContactDetailView: View {
    @Environment(\.appModel) private var model
    @Environment(\.openURL) private var openURL
    /// The contact as it was when the row was tapped; the live copy follows edits and re-syncs.
    let original: Contact
    @State private var editing = false
    @State private var confirmBlock = false

    init(contact: Contact) { original = contact }
    private var contact: Contact { model.data.contacts.first { $0.id == original.id } ?? original }

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                posterHeader
                if !contact.phones.isEmpty || !contact.emails.isEmpty {
                    actionRow
                }
                VStack(spacing: 12) {
                    ForEach(contact.phones, id: \.self) { p in phoneCard(p) }
                    ForEach(contact.emails, id: \.self) { e in emailCard(e) }
                    if !history.isEmpty { historyCard }
                    if !contact.phones.isEmpty { blockCard }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 28)
        }
        .confirmationDialog(contact.name, isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block Contact", role: .destructive) { for p in contact.phones { model.setBlocked(p.n, true) } }
        } message: {
            Text("You will not receive phone calls or messages from people on the block list.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { model.setStarred(contact.id, !contact.starred) } label: {
                    Image(systemName: contact.starred ? "star.fill" : "star").foregroundStyle(contact.starred ? .yellow : .accentColor)
                }
                .accessibilityLabel(Text(contact.starred ? "Remove from Favourites" : "Add to Favourites"))
                .disabled(!model.linkState.isConnected)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { editing = true }.disabled(!model.linkState.isConnected)
            }
        }
        .sheet(isPresented: $editing) {
            EditContactView(contact: contact).environment(\.appModel, AppModel.shared).environment(\.router, Router.shared).appLanguageEnvironment()
        }
    }

    /// Poster header, as in Contacts: the photo large over a backdrop blurred from the photo
    /// itself; without a photo, the grey monogram gradient with big initials (the same
    /// gradient the list avatars use).
    private var posterHeader: some View {
        VStack(spacing: 14) {
            Avatar(name: contact.name, photo: contact.photo, size: 176)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            Text(contact.name)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .background { backdrop }
        .clipped()
    }

    @ViewBuilder private var backdrop: some View {
        if let photo = contact.photo, let data = Data(base64Encoded: photo), let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .blur(radius: 48, opaque: true)
                .overlay(Color.black.opacity(0.22))
        } else {
            LinearGradient(colors: [Color(red: 0.65, green: 0.67, blue: 0.72),
                                    Color(red: 0.52, green: 0.54, blue: 0.58)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// The round action buttons under the name, as on a contact poster: message and call on
    /// the first number, mail when the contact has an e-mail address.
    private var actionRow: some View {
        HStack(spacing: 20) {
            if let p = contact.phones.first {
                actionButton("message.fill", label: Text("Message")) { openThread(p.n) }
                actionButton("phone.fill", label: Text("Call")) { model.dial(p.n, sub: model.preferredSim(for: p.n)) }
            }
            if let e = contact.emails.first {
                actionButton("envelope.fill", label: Text("Email")) {
                    if let url = URL(string: "mailto:\(e)") { openURL(url) }
                }
            }
        }
    }

    private func actionButton(_ icon: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21))
                .foregroundStyle(Color.accentColor)
                .frame(width: 58, height: 58)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// One phone number as a card: label and number with message and call buttons; tapping
    /// the number itself calls, as in Contacts.
    private func phoneCard(_ p: Phone) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let label = p.label, !label.trimmingCharacters(in: .whitespaces).isEmpty { Text(verbatim: label) }
                    else { Text(LocalizedStringKey(p.type.capitalized)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(model.formatted(p.n)).environment(\.layoutDirection, .leftToRight)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.dial(p.n, sub: model.preferredSim(for: p.n)) }
            Spacer()
            cardButton("message.fill", label: Text("Message")) { openThread(p.n) }
            cardButton("phone.fill", label: Text("Call")) { model.dial(p.n, sub: model.preferredSim(for: p.n)) }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cardButton(_ icon: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// One e-mail address as a card; tapping it opens Mail, as in Contacts.
    private func emailCard(_ e: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Email").font(.caption).foregroundStyle(.secondary)
                Text(e).lineLimit(1)
            }
            Spacer()
            Image(systemName: "envelope.fill").font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if let url = URL(string: "mailto:\(e)") { openURL(url) } }
    }

    /// This contact's calls, newest first, from the same synced log Recents shows (matched
    /// by the same number key the name/photo indexes use).
    private var history: [CallEntry] {
        let keys = Set(contact.phones.map { PhoneNumber.matchKey($0.n) })
        guard !keys.isEmpty else { return [] }
        return Array(model.data.recents.filter { keys.contains(PhoneNumber.matchKey($0.num)) }.prefix(8))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Call History").font(.headline)
            ForEach(history) { e in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(historyLabel(e))
                            .foregroundStyle(e.type == 3 || e.type == 5 ? Color.red : Color.primary)
                        Text(Date(millis: e.date).formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if e.dur > 0 {
                        Text(Duration.seconds(e.dur).formatted(.time(pattern: .minuteSecond)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if e.id != history.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func historyLabel(_ e: CallEntry) -> LocalizedStringKey {
        switch e.type {
        case 2: return "Outgoing Call"
        case 3, 5: return "Missed Call"
        default: return "Incoming Call"
        }
    }

    /// Block / unblock for the whole contact (all of its numbers), as a card, as in Contacts.
    private var blockCard: some View {
        let blocked = contact.phones.contains { model.isBlocked($0.n) }
        return Button {
            if blocked { for p in contact.phones where model.isBlocked(p.n) { model.setBlocked(p.n, false) } }
            else { confirmBlock = true }
        } label: {
            Text(blocked ? "Unblock this Caller" : "Block this Caller")
                .foregroundStyle(blocked ? Color.accentColor : .red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.linkState.isConnected)
    }

    private func openThread(_ number: String) {
        if let t = model.thread(for: number) {
            Router.shared.open(thread: t)
        } else {
            Router.shared.compose(to: number)   // no conversation yet: a new message to this number
        }
    }
}

struct AddContactView: View {
    @Environment(\.appModel) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var type = "mobile"
    @State private var email = ""

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name) }
                Section {
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    Picker("Type", selection: $type) {
                        Text("Mobile").tag("mobile"); Text("Home").tag("home"); Text("Work").tag("work"); Text("Other").tag("other")
                    }
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                }
                Section { Text("The contact is saved on your Android phone.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addContact(name: name, phones: phone.isEmpty ? [] : [Phone(n: phone, type: type)],
                                         emails: email.isEmpty ? [] : [email])
                        dismiss()
                    }
                    .disabled(name.isEmpty || (phone.isEmpty && email.isEmpty))
                }
            }
        }
    }
}

/// Edit an existing contact, laid out like the iOS Contacts editor: name, then phone and e-mail rows that
/// can be added, retyped and removed. Saving rewrites the contact on the Android phone.
struct EditContactView: View {
    @Environment(\.appModel) private var model
    @Environment(\.dismiss) private var dismiss
    let contact: Contact

    /// `label`: the number's custom kind from the Android phone ("Satellite"); kept unless another kind is picked.
    struct PhoneRow: Identifiable { let id = UUID(); var number: String; var type: String; var label: String? = nil }
    private struct EmailRow: Identifiable { let id = UUID(); var address: String }
    @State private var name = ""
    @State private var phones: [PhoneRow] = []
    @State private var emails: [EmailRow] = []
    private let types = ["mobile", "home", "work", "main", "other"]

    /// Picker tag for "keep the custom kind" (never sent: it goes out as type "other" with the label).
    static let custom = "custom"

    /// What the Android phone stores: a kept custom kind is sent with its label; picking a standard kind for a
    /// custom one sends an empty label (clears it); otherwise no label (protocol §5 contact.update).
    static func phone(from row: PhoneRow) -> Phone {
        let n = row.number.trimmingCharacters(in: .whitespaces)
        if row.type == custom, let label = row.label { return Phone(n: n, type: "other", label: label) }
        return Phone(n: n, type: row.type, label: row.label != nil ? "" : nil)
    }

    var body: some View { WithPerceptionTracking { bodyContent } }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); Avatar(name: name.isEmpty ? contact.name : name, photo: contact.photo, size: 80); Spacer() }
                        .listRowBackground(Color.clear)
                    TextField("Name", text: $name)
                }
                Section {
                    ForEach($phones) { $p in
                        HStack {
                            Picker("", selection: $p.type) {
                                if let label = p.label { Text(verbatim: label).tag(Self.custom) }
                                ForEach(types, id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                            TextField("Phone", text: $p.number).keyboardType(.phonePad)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    .onDelete { phones.remove(atOffsets: $0) }
                    Button { phones.append(PhoneRow(number: "", type: "mobile")) } label: {
                        Label("Add phone", systemImage: "plus.circle.fill")
                    }
                }
                Section {
                    ForEach($emails) { $e in
                        TextField("Email", text: $e.address).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    }
                    .onDelete { emails.remove(atOffsets: $0) }
                    Button { emails.append(EmailRow(address: "")) } label: {
                        Label("Add email", systemImage: "plus.circle.fill")
                    }
                }
                Section { Text("Changes are saved on your Android phone.").font(.footnote).foregroundStyle(.secondary) }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let ps = phones.map { Self.phone(from: $0) }.filter { !$0.n.isEmpty }
                        let es = emails.map { $0.address.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        model.updateContact(id: contact.id, name: name.trimmingCharacters(in: .whitespaces), phones: ps, emails: es)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !model.linkState.isConnected)
                }
            }
            .onAppear {
                name = contact.name
                phones = contact.phones.map { p in
                    let label = p.label.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                    return PhoneRow(number: p.n, type: label != nil ? Self.custom : (types.contains(p.type) ? p.type : "other"), label: label)
                }
                emails = contact.emails.map { EmailRow(address: $0) }
            }
        }
    }
}
