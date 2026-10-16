import AppKit
import SwiftUI

@MainActor enum NativeVaultSettings {
    static func run(executable: URL) async throws {
        let suite = "dev.keepy.settings-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = TrayShortcutSettings(defaults: defaults)
        precondition(!preferences.showFullCredentialNames, "Existing installations and new profiles start with compact tray labels")
        precondition(preferences.set(enabled: false, shortcut: .default))
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await store.refresh()
        precondition(store.settingsPages == [.general])
        precondition(!store.selectSettingsPage(.tagNames))
        var settingsOpens = 0
        store.openSettingsWindow = { settingsOpens += 1 }
        store.openVaultSettings(.overview)
        precondition(settingsOpens == 0 && store.settingsRequest == nil)
        let created = await store.authenticate(name: "Settings lifecycle", password: "synthetic-settings-password")
        precondition(created)
        let id = store.vault!.id
        precondition(store.settingsPages == SettingsDestination.allCases)
        let groupAdded = await store.mutate("add_group", ["name": "Company › Region › Production", "tags": ["green"]])
        precondition(groupAdded)
        let groupID = store.vault!.nodes[0].id
        let entryAdded = await store.mutate("add_entry", ["parent_id": groupID, "name": "Server", "fields": [
            ["label": "Password", "kind": "secret", "masked": true, "value": "synthetic-settings-secret"]
        ]])
        precondition(entryAdded)
        let configured = await store.saveTrayTags([.green], vaultID: id)
        precondition(configured)
        let credential = store.vault!.trayCredentials[0]
        precondition(credential.title(showFullNames: false) == "Server › Password")
        precondition(credential.title(showFullNames: true) == "Server › Password — Company › Region › Production")
        let long = TrayCredential(id: credential.id, name: String(repeating: "Ж", count: 100), label: "Password", path: String(repeating: "folder/", count: 100), action: credential.action)
        precondition(long.title(showFullNames: false).count == 60 && long.title(showFullNames: true).count == 100)
        let tray = TrayMenuController()
        tray.start(store: store, shortcuts: preferences, openWindow: {}, openSettings: {})
        defer { tray.stop() }
        tray.menuNeedsUpdate(tray.menu)
        func menuItem() -> NSMenuItem { tray.menu.items.flatMap { $0.submenu?.items ?? [] }.first { $0.representedObject is CredentialTarget }! }
        precondition(menuItem().title == "Server › Password" && menuItem().toolTip!.contains(credential.fullTitle))
        precondition(!tray.menu.items.contains { ["Tag Names…", "Tray Tags…"].contains($0.title) })
        preferences.setShowFullCredentialNames(true)
        for _ in 0..<100 {
            if menuItem().title == credential.fullTitle { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(menuItem().title == credential.fullTitle, "Changing the preference must update an existing native tray menu")
        let restarted = TrayShortcutSettings(defaults: defaults)
        precondition(restarted.showFullCredentialNames)
        restarted.setShowFullCredentialNames(false)
        precondition(!TrayShortcutSettings(defaults: defaults).showFullCredentialNames)
        precondition(menuItem().representedObject as? CredentialTarget == credential.id)
        store.openVaultSettings(.tagNames)
        precondition(settingsOpens == 1 && store.editor == nil && store.settingsRequest == .tagNames)
        precondition(store.selectSettingsPage(.tagNames))
        store.vaultSettingsHaveChanges = true
        precondition(store.hasPendingEdits && !store.canUseTrayCredentials)
        store.addEntry(); store.addGroup(); store.edit(store.vault!.nodes[0])
        precondition(store.editor == nil && store.vaultSettingsHaveChanges, "Workspace editors must not replace Settings drafts")
        precondition(!store.selectSettingsPage(.tray) && store.settingsDestination == .tagNames)
        precondition(store.selectSettingsPage(.tray, discard: true) && !store.vaultSettingsHaveChanges)
        store.settingsHaveChanges = true
        precondition(!store.selectSettingsPage(.general))
        precondition(store.selectSettingsPage(.general, discard: true))
        store.settingsSaving = true
        precondition(!store.selectSettingsPage(.tray) && store.hasPendingEdits)
        store.settingsSaving = false
        store.editor = EditorRoute(kind: .entry(nil))
        store.openVaultSettings(.sshKeys)
        precondition(store.settingsRequest == .sshKeys && store.editor?.isInline == true)
        precondition(store.selectSettingsPage(.sshKeys) && store.canEditVaultSettings)
        store.openVaultSettings(.password)
        precondition(store.settingsRequest == nil, "Other settings must not replace an entry draft")
        store.editor = nil
        store.vaultSettingsHaveChanges = true
        store.lock()
        precondition(store.settingsPages == [.general] && store.settingsDestination == .general && !store.vaultSettingsHaveChanges && store.settingsRequest == nil)
        let lateSave = await store.saveTagNames(["green": "Late"], vaultID: id)
        precondition(!lateSave)
        let unlocked = await store.authenticate(password: "synthetic-settings-password")
        precondition(unlocked && store.settingsDestination == .general)
        let other = await store.authenticate(name: "Other settings vault", password: "synthetic-other-settings-password")
        precondition(other && store.vault!.id != id && store.vault!.tagNames.isEmpty && store.vault!.trayTags.isEmpty)
        await store.shutdown()
        print("Native vault settings passed: compact/full tray labels, live menu updates, persistence, tooltip context, unlocked-only navigation, dirty/busy guards, entry-editor routing, locking and vault isolation.")
    }
}
