import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let fieldDragType = UTType(exportedAs: "dev.bunchofkeys.field")

struct EditorView: View {
    var route: EditorRoute
    var body: some View {
        switch route.kind {
        case .entry(let node): EntryEditor(node: node, parentId: route.parentId, insertionIndex: route.insertionIndex, routeId: route.id.uuidString)
        case .group(let node): GroupEditor(node: node, parentId: route.parentId, insertionIndex: route.insertionIndex, routeId: route.id.uuidString)
        case .keys: SSHKeysEditor()
        case .createVault: NewVaultEditor()
        }
    }
}
struct EditorError: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if let error = store.error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
    }
}
struct EntryEditor: View {
    @EnvironmentObject var store: AppStore
    var node: VaultNode?
    var parentId: String?
    var insertionIndex: Int?
    var routeId: String
    @State private var name = ""
    @State private var fields: [FieldDraft] = []
    @State private var loaded = false
    @State private var dragging: String?
    @State private var dirty = false
    @State private var initialName = ""
    @State private var initialFields: [FieldDraft] = []
    var hasChanges: Bool { name != initialName || fields != initialFields }
    @State private var confirmDiscard = false
    var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fields.allSatisfy {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.kind != "ssh" || (!$0.user.isEmpty && !$0.address.isEmpty && !$0.keyId.isEmpty && ($0.port.isEmpty || (Int($0.port).map { (1...65535).contains($0) } ?? false))))
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(node == nil ? "New Entry" : "Edit Entry").font(.title2.weight(.semibold)); Spacer()
                if node == nil { DraftHandle(id: routeId) }
            }
            if node == nil { Text("In \(parentId.flatMap { store.vault?.node($0)?.name } ?? store.vaultName)").font(.caption).foregroundStyle(.secondary) }
            TextField("Entry name", text: $name).textFieldStyle(.roundedBorder).onChange(of: name) { _, _ in if loaded { dirty = true } }
            if !loaded { ProgressView("Loading fields…").frame(maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($fields) { $field in
                            FieldEditor(field: $field, dragging: $dragging)
                                .onDrop(of: [fieldDragType], delegate: FieldDrop(target: field.id, fields: $fields, dragging: $dragging, dirty: $dirty))
                        }
                        HStack {
                            Menu("Add Field") {
                                ForEach(["text", "secret", "url", "ssh"], id: \.self) { kind in
                                    Button(kind == "ssh" ? "SSH" : kind.capitalized) {
                                        var field = FieldDraft(); field.kind = kind; field.masked = kind == "secret"
                                        field.label = kind == "ssh" ? "SSH" : kind.capitalized
                                        field.keyId = store.vault?.sshKeys.first?.id ?? ""
                                        fields.append(field); dirty = true
                                    }.disabled(kind == "ssh" && store.vault?.sshKeys.isEmpty != false)
                                }
                                Divider()
                                Button("Manage SSH Keys…") { store.showingKeys = true }
                            }
                            Spacer()
                            Text("Drag the grip to reorder fields").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 12).onDrop(of: [fieldDragType], delegate: FieldDrop(target: nil, fields: $fields, dragging: $dragging, dirty: $dirty))
                    }
                }
            }
            EditorError()
            HStack {
                Button("Cancel") { if hasChanges { confirmDiscard = true } else { close() } }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Save") {
                    Task {
                        let command = node == nil ? "add_entry" : "update_entry"
                        var args: [String: Any] = ["name": name, "fields": fields.map(\.payload)]
                        if let node { args["entry_id"] = node.id } else { args["parent_id"] = parentId as Any? ?? NSNull(); if let insertionIndex { args["index"] = insertionIndex } }
                        if await store.mutate(command, args) {
                            if let node { store.selection = node.id }
                            else { store.selectCreatedNode(parent: parentId, index: insertionIndex) }
                            fields.removeAll(); close()
                        }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!valid || !loaded || store.busy)
            }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .disabled(store.busy)
            .task {
                guard !loaded else { return }
                store.error = nil; name = node?.name ?? ""
                var drafts = (node?.fields ?? []).map(FieldDraft.init)
                do {
                    if let node {
                        for index in drafts.indices where drafts[index].masked {
                            drafts[index].value = try await store.fieldString("reveal_field", entry: node.id, field: drafts[index].id)
                        }
                    }
                    if node == nil { var draft = FieldDraft(); draft.label = "Password"; draft.kind = "secret"; draft.masked = true; drafts = [draft] }
                    fields = drafts; initialName = name; initialFields = drafts; loaded = true; dirty = false
                } catch { store.fail(error) }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { fields.removeAll(); close() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("RemoveDraftField"))) { notification in
                if let id = notification.object as? String { fields.removeAll { $0.id == id }; dirty = true }
            }
    }
    func close() { store.editor = nil; store.error = nil }

}
struct FieldEditor: View {
    @EnvironmentObject var store: AppStore
    @Binding var field: FieldDraft
    @Binding var dragging: String?
    @State private var showValue = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).padding(5)
                    .onDrag {
                        dragging = field.id
                        let item = NSItemProvider()
                        let id = field.id
                        item.registerDataRepresentation(forTypeIdentifier: fieldDragType.identifier, visibility: .ownProcess) { completion in
                            completion(Data(id.utf8), nil); return nil
                        }
                        return item
                    }.help("Drag to reorder")
                TextField("Field label", text: $field.label).textFieldStyle(.roundedBorder)
                Picker("Type", selection: $field.kind) {
                    Text("Text").tag("text"); Text("Secret").tag("secret"); Text("URL").tag("url"); Text("SSH").tag("ssh")
                }.labelsHidden().frame(width: 100)
                    .onChange(of: field.kind) { _, kind in if kind == "secret" { field.masked = true }; if kind == "ssh" { field.keyId = store.vault?.sshKeys.first?.id ?? "" } }
                Button { NotificationCenter.default.post(name: .init("RemoveDraftField"), object: field.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Remove field").accessibilityLabel("Remove field")
            }
            if field.kind == "ssh" {
                HStack { TextField("User", text: $field.user); TextField("Host", text: $field.address); TextField("Port", text: $field.port).frame(width: 65) }.textFieldStyle(.roundedBorder)
                Picker("SSH Key", selection: $field.keyId) {
                    Text("Select a key").tag("")
                    ForEach(store.vault?.sshKeys ?? []) { key in Text(key.name).tag(key.id) }
                }
                Button("Manage SSH Keys…") { store.showingKeys = true }.font(.caption)
            } else {
                if field.masked && !showValue { SecureField("Value", text: $field.value).textFieldStyle(.roundedBorder) }
                else { TextEditor(text: $field.value).font(.system(.body, design: .monospaced)).frame(minHeight: 55, maxHeight: 100).border(.quaternary) }
                HStack {
                    Toggle("Mask value", isOn: $field.masked)
                    Spacer()
                    if field.masked { Toggle("Show while editing", isOn: $showValue).toggleStyle(.button) }
                }.font(.caption)
            }
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
struct FieldDrop: DropDelegate {
    var target: String?
    @Binding var fields: [FieldDraft]
    @Binding var dragging: String?
    @Binding var dirty: Bool
    func validateDrop(info: DropInfo) -> Bool { dragging != nil && info.hasItemsConforming(to: [fieldDragType]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, let source = fields.firstIndex(where: { $0.id == dragging }) else { return }
        let destination = target.flatMap { id in fields.firstIndex { $0.id == id } } ?? fields.count
        withAnimation { fields.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + (target == nil ? 0 : 1) : destination) }
        dirty = true
    }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
struct GroupEditor: View {
    @EnvironmentObject var store: AppStore
    var node: VaultNode?
    var parentId: String?
    var insertionIndex: Int?
    var routeId: String
    @State private var name = ""
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(node == nil ? "New Group" : "Rename Group").font(.title2.weight(.semibold)); Spacer(); if node == nil { DraftHandle(id: routeId) } }
            if node == nil { Text("In \(parentId.flatMap { store.vault?.node($0)?.name } ?? store.vaultName)").font(.caption).foregroundStyle(.secondary) }
            TextField("Group name", text: $name).textFieldStyle(.roundedBorder)
            EditorError()
            HStack {
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction); Spacer()
                Button("Save") {
                    Task {
                        var args: [String: Any] = node.map { ["node_id": $0.id, "name": name] } ?? ["parent_id": parentId as Any? ?? NSNull(), "name": name]
                        if node == nil, let insertionIndex { args["index"] = insertionIndex }
                        if await store.mutate(node == nil ? "add_group" : "rename_node", args) {
                            if let node { store.selection = node.id }
                            else { store.selectCreatedNode(parent: parentId, index: insertionIndex) }
                            close()
                        }
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
            }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).onAppear { if !loaded { name = node?.name ?? ""; store.error = nil; loaded = true } }
    }
    func close() { store.editor = nil; store.error = nil }

}
struct NewVaultEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Vault").font(.title2.weight(.semibold))
            TextField("Vault name", text: $name)
            SecureField("Master password", text: $password)
            SecureField("Confirm master password", text: $confirmation)
            Text("Use at least 8 characters. There is no password recovery.").font(.caption).foregroundStyle(.secondary)
            EditorError()
            HStack {
                Button("Cancel") { password = ""; confirmation = ""; dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button("Create Vault") {
                    Task { if await store.authenticate(name: name, password: password) { password = ""; confirmation = ""; dismiss() } }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 8 || password != confirmation || store.busy)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 400).disabled(store.busy).onAppear { store.error = nil }
    }
}
struct SSHPassphraseView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Unlock SSH Key", systemImage: "key").font(.title2.weight(.semibold))
            Text("This key needs a passphrase. It is used only for this connection.").foregroundStyle(.secondary)
            SecureField("SSH key passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
            EditorError()
            HStack {
                Button("Cancel") { passphrase = ""; dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button("Connect") {
                    guard let prompt = store.sshPrompt else { return }
                    busy = true
                    Task { if await store.connect(entry: prompt.entry, field: prompt.field, passphrase: passphrase) { passphrase = ""; dismiss() }; busy = false }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(passphrase.isEmpty || busy)
            }
        }.padding(24).frame(width: 420).disabled(busy)
    }
}

struct DraftHandle: View {
    var id: String
    var body: some View {
        Label("Move draft", systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)
            .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .onDrag {
                let item = NSItemProvider()
                item.registerDataRepresentation(forTypeIdentifier: "dev.bunchofkeys.draft", visibility: .ownProcess) { completion in
                    completion(Data(id.utf8), nil); return nil
                }
                return item
            }.help("Drag this draft into a group or position in the tree")
    }
}
