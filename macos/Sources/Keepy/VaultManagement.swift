import AppKit
import SwiftUI


enum PasswordChangeValidation {
    static func error(current: String, new: String, confirmation: String) -> String? {
        if current.isEmpty { return "Enter your current master password." }
        if new.unicodeScalars.count < 8 { return "Use at least 8 characters for the new password." }
        if new == current { return "Choose a new password different from the current password." }
        if new != confirmation { return "New password and confirmation do not match." }
        return nil
    }
}

struct RenameVaultEditor: View {
    @EnvironmentObject var store: AppStore
    let vault: VaultSummary
    @ViewState private var name = ""
    @ViewState private var edited = false
    @FocusState private var focused: Bool
    private var normalized: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validation: String? { store.vaultNameError(name, excluding: vault.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Vault").font(.title2.weight(.semibold))
            TextField("Vault name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onChange(of: name) { _, _ in edited = true; store.error = nil }
            Text("The vault's contents, password and file location stay the same.").font(.caption).foregroundStyle(.secondary)
            if edited, let validation { Text(validation).foregroundStyle(.red).font(.callout) }
            EditorError()
            HStack {
                Button("Cancel") { name = ""; store.editor = nil; store.error = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Rename") { Task { if await store.renameVault(id: vault.id, name: name) { name = "" } } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(validation != nil || normalized == vault.name)
            }
        }.padding(24).frame(width: 400).disabled(store.busy).interactiveDismissDisabled(store.busy)
            .onAppear { name = vault.name; edited = false; focused = true; store.error = nil }
            .onDisappear { name = "" }
    }
}

struct ChangeMasterPasswordEditor: View {
    @EnvironmentObject var store: AppStore
    let vaultID: String
    @ViewState private var current = ""
    @ViewState private var new = ""
    @ViewState private var confirmation = ""
    @ViewState private var attempted = false
    @FocusState private var focused: Bool
    private var validation: String? { PasswordChangeValidation.error(current: current, new: new, confirmation: confirmation) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Master Password").font(.title2.weight(.semibold))
            SecureField("Current master password", text: $current).focused($focused)
            SecureField("New master password", text: $new)
            SecureField("Confirm new master password", text: $confirmation)
            Text("Use at least 8 characters. The vault locks after saving. Set up Touch ID again after unlocking with the new password.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Existing backups keep the password used when they were created.")
                .font(.caption).foregroundStyle(.secondary)
            if attempted, let validation { Text(validation).font(.callout).foregroundStyle(.red) }
            EditorError()
            HStack {
                Button("Cancel") { clear(); store.editor = nil; store.error = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Change Password") {
                    attempted = true
                    guard validation == nil else { return }
                    Task { if await store.changeMasterPassword(id: vaultID, current: current, new: new, confirmation: confirmation) { clear() } }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(current.isEmpty || new.isEmpty || confirmation.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 400).disabled(store.busy).interactiveDismissDisabled(store.busy)
            .onAppear { focused = true; store.error = nil }
            .onDisappear { clear() }
            .onChange(of: current) { _, _ in store.error = nil }
            .onChange(of: new) { _, _ in store.error = nil }
            .onChange(of: confirmation) { _, _ in store.error = nil }
    }
    private func clear() { current = ""; new = ""; confirmation = "" }
}
