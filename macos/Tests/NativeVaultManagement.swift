import Foundation
import AppKit

@MainActor enum NativeVaultManagement {
    static func run(executable: URL) async throws {
        let board = NSPasteboard(name: .init("dev.keepy.vault-management.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let keychain = TestBiometricKeychain()
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board, biometricKeychain: keychain)
        await store.refresh()
        let created = await store.authenticate(name: "Vault Management Test", password: "synthetic-old-password")
        precondition(created)
        let id = store.vault!.id
        let added = await store.mutate("add_entry", ["name": "Preserved", "tags": ["blue"], "fields": [
            ["label": "Secret", "kind": "secret", "masked": true, "value": "synthetic-preserved-secret"]
        ]])
        precondition(added)
        let before = store.vault!
        precondition(store.vaultNameError(" ") != nil && store.vaultNameError(String(repeating: "x", count: 81)) != nil)
        precondition(store.vaultNameError("Vault Management Test") != nil)
        precondition(store.vaultNameError("Vault Management Test", excluding: id) == nil)
        precondition(PasswordChangeValidation.error(current: "old-password", new: "short", confirmation: "short") != nil)
        precondition(PasswordChangeValidation.error(current: "old-password", new: "old-password", confirmation: "old-password") != nil)
        precondition(PasswordChangeValidation.error(current: "old-password", new: "new-password", confirmation: "mismatch") != nil)
        store.editor = EditorRoute(kind: .entry(nil))
        store.manageVault(password: false)
        let blocked = await store.renameVault(id: id, name: "Should not save")
        precondition(!blocked && store.editor?.isInline == true, "Unsaved editors must be protected")
        store.editor = nil; store.settingsHaveChanges = true
        precondition(!store.canManageVault)
        store.settingsHaveChanges = false
        store.manageVault(password: false)
        precondition(store.editor != nil)
        store.editor = nil // Cancel does not send a mutation.
        precondition(store.vaultName == "Vault Management Test")
        let renamed = await store.renameVault(id: id, name: "  Renamed Management Test  ")
        precondition(renamed && store.vaultName == "Renamed Management Test" && store.vault == before)
        store.manageTouchID(); await store.enableTouchID(password: "synthetic-old-password")
        precondition(store.touchIDEnrolled)
        store.cancelTouchIDSetup()
        store.manageVault(password: true)
        let wrong = await store.changeMasterPassword(id: id, current: "wrong-password", new: "synthetic-new-password", confirmation: "synthetic-new-password")
        precondition(!wrong && store.vault == before && store.error != nil)
        precondition(keychain.entries[id] != nil)
        store.error = nil
        let changed = await store.changeMasterPassword(id: id, current: "synthetic-old-password", new: "synthetic-new-password", confirmation: "synthetic-new-password")
        precondition(changed && store.vault == nil && store.editor == nil && store.notice != nil)
        precondition(!store.touchIDEnrolled && keychain.entries[id] == nil)
        let oldRejected = await store.authenticate(password: "synthetic-old-password")
        precondition(!oldRejected && store.vault == nil)
        let newAccepted = await store.authenticate(password: "synthetic-new-password")
        precondition(newAccepted && store.vault == before && store.vaultName == "Renamed Management Test")
        let secret = try await store.fieldString("reveal_field", entry: before.nodes[0].id, field: before.nodes[0].fields![0].id)
        precondition(secret == "synthetic-preserved-secret")
        // Lock while Argon2 and the atomic save are in flight. A late response
        // may not resurrect a session, report success or reopen the editor.
        store.manageVault(password: true)
        let change = Task { await store.changeMasterPassword(id: id, current: "synthetic-new-password", new: "synthetic-final-password", confirmation: "synthetic-final-password") }
        for _ in 0..<100 {
            if store.busy { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        store.lock()
        let late = await change.value
        precondition(!late && store.vault == nil && store.editor == nil && store.notice == nil)
        await store.shutdown()
        let restarted = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await restarted.refresh()
        precondition(restarted.vaults.contains { $0.id == id && $0.name == "Renamed Management Test" })
        await restarted.shutdown()
        print("Native vault management passed: validation, rename, editor guards, password verification, Touch ID invalidation, locking, late responses and restart.")
    }
}
