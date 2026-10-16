import SwiftUI
import AppKit

struct SSHKeysEditor: View {
    @EnvironmentObject var store: AppStore
    let vaultID: String
    @ViewState private var selection: String?
    @ViewState private var name = ""
    @ViewState private var privateKey = ""
    @ViewState private var deleteKey = false
    @ViewState private var pendingSelection: String?
    private var changed: Bool { !privateKey.isEmpty || name != (selected?.name ?? "") }
    var selected: SSHKey? { store.vault?.sshKeys.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH Keys").font(.title2.weight(.semibold))
            Picker("Key", selection: Binding(get: { selection ?? "" }, set: { if changed { pendingSelection = $0 } else { choose($0) } })) {
                Text("New Key").tag("")
                ForEach(store.vault?.sshKeys ?? []) { key in Text(key.name).tag(key.id) }
            }
            TextField("Key name", text: $name).textFieldStyle(.roundedBorder)
            if let selected {
                Text(selected.algorithm).font(.callout).foregroundStyle(.secondary)
                Text(selected.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("Leave the private key empty to keep the stored key. Replacing it preserves connection references.").font(.caption).foregroundStyle(.secondary)
            } else { Text("Paste or import an OpenSSH private key. It is stored only inside the encrypted vault.").font(.caption).foregroundStyle(.secondary) }
            TextEditor(text: $privateKey).font(.system(.caption, design: .monospaced)).frame(minHeight: 140).border(.quaternary)
            HStack {
                Button("Import Key File…") { importKey() }; Spacer()
                if selected != nil { Button("Delete…", role: .destructive) { deleteKey = true } }
            }
            Button(selected == nil ? "Add Key" : "Save Key") {
                Task {
                    guard store.vault?.id == vaultID else { return }
                    var args: [String: Any] = ["name": name]
                    if let selected {
                        args["key_id"] = selected.id
                        if !privateKey.isEmpty { args["private_key"] = privateKey }
                    } else { args["private_key"] = privateKey }
                    if await store.mutate(selected == nil ? "add_ssh_key" : "update_ssh_key", args) { choose(""); store.notice = "SSH key saved." }
                }
            }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selected == nil && privateKey.isEmpty) || store.busy)
            EditorError()
            HStack { Button("Cancel") { choose(selection ?? "") }.keyboardShortcut(.cancelAction); Spacer() }
            SettingsSaveStatus()
        }.padding(24).frame(maxWidth: .infinity).disabled(store.busy)
            .onChange(of: name) { _, _ in store.vaultSettingsHaveChanges = changed }
            .onChange(of: privateKey) { _, _ in store.vaultSettingsHaveChanges = changed }
            .onAppear { store.showingKeys = true; store.error = nil }
            .onDisappear { privateKey = ""; store.showingKeys = false; store.vaultSettingsHaveChanges = false }
            .confirmationDialog("Discard SSH key changes?", isPresented: Binding(get: { pendingSelection != nil }, set: { if !$0 { pendingSelection = nil } }), titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { if let target = pendingSelection { choose(target) }; pendingSelection = nil }
                Button("Keep Editing", role: .cancel) { pendingSelection = nil }
            }
            .confirmationDialog("Delete this SSH key?", isPresented: $deleteKey, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let selected { Task { guard store.vault?.id == vaultID else { return }; if await store.mutate("delete_ssh_key", ["key_id": selected.id]) { choose("") } } }
                }
            } message: { Text("Keys used by SSH connection fields cannot be deleted.") }
    }
    private func choose(_ id: String) { selection = id.isEmpty ? nil : id; name = selected?.name ?? ""; privateKey = ""; store.error = nil; store.vaultSettingsHaveChanges = false }
    func importKey() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, store.vault?.id == vaultID, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2 * 1024 * 1024 else { throw CoreError(message: "The key file is too large.") }
                privateKey = try String(contentsOf: url, encoding: .utf8)
                if name.isEmpty { name = url.lastPathComponent }
            } catch { store.fail(error) }
        }
    }
}
