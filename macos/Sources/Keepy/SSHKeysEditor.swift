import SwiftUI
import AppKit

struct SSHKeysEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var name = ""
    @State private var privateKey = ""
    @State private var deleteKey = false
    var selected: SSHKey? { store.vault?.sshKeys.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH Keys").font(.title2.weight(.semibold))
            Picker("Key", selection: Binding(get: { selection ?? "" }, set: { selection = $0.isEmpty ? nil : $0 })) {
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
                    var args: [String: Any] = ["name": name]
                    if let selected {
                        args["key_id"] = selected.id
                        if !privateKey.isEmpty { args["private_key"] = privateKey }
                    } else { args["private_key"] = privateKey }
                    if await store.mutate(selected == nil ? "add_ssh_key" : "update_ssh_key", args) { privateKey = ""; name = ""; selection = nil }
                }
            }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selected == nil && privateKey.isEmpty) || store.busy)
            EditorError()
            HStack { Spacer(); Button("Done") { privateKey = ""; store.error = nil; dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 480, height: 540).disabled(store.busy)
            .onChange(of: selection) { _, _ in name = selected?.name ?? ""; privateKey = ""; store.error = nil }
            .onAppear { store.error = nil }
            .confirmationDialog("Delete this SSH key?", isPresented: $deleteKey, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let selected { Task { if await store.mutate("delete_ssh_key", ["key_id": selected.id]) { selection = nil; privateKey = ""; name = "" } } }
                }
            } message: { Text("Keys used by SSH connection fields cannot be deleted.") }
    }
    func importKey() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2 * 1024 * 1024 else { throw CoreError(message: "The key file is too large.") }
                privateKey = try String(contentsOf: url, encoding: .utf8)
                if name.isEmpty { name = url.lastPathComponent }
            } catch { store.fail(error) }
        }
    }
}
