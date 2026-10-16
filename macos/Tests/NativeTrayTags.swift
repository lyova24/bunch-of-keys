import AppKit
import Foundation

@MainActor enum NativeTrayTags {
    static func run(executable: URL) async throws {
        let legacy = try JSONDecoder().decode(Vault.self, from: Data("{\"id\":\"legacy\",\"sshKeys\":[],\"nodes\":[]}".utf8))
        precondition(legacy.trayTags.isEmpty && legacy.trayEntries.isEmpty)
        let board = NSPasteboard(name: .init("dev.keepy.tray-tags.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await store.refresh()
        let created = await store.authenticate(name: "Tray Tags Native", password: "synthetic-tray-password")
        precondition(created && store.vault!.trayTags.isEmpty)
        let id = store.vault!.id
        let grouped = await store.mutate("add_group", ["name": "Inherited", "tags": ["red"]])
        precondition(grouped)
        let group = store.vault!.nodes[0].id
        let nestedSaved = await store.mutate("add_group", ["parent_id": group, "name": "Nested"])
        precondition(nestedSaved)
        let nested = store.vault!.node(group)!.children![0].id
        let childSaved = await store.mutate("add_entry", ["parent_id": nested, "name": "From group", "fields": [
            ["label": "Username", "kind": "text", "masked": false, "value": "synthetic-user"]
        ]])
        precondition(childSaved)
        let child = store.vault!.node(nested)!.children![0].id
        let multiple = await store.mutate("add_entry", ["name": "Multiple tags", "tags": ["red", "blue"], "fields": []])
        precondition(multiple)
        let multi = store.vault!.nodes.last!.id
        let excludedSaved = await store.mutate("add_entry", ["name": "Excluded", "tags": ["orange"], "fields": []])
        precondition(excludedSaved)
        let excluded = store.vault!.nodes.last!.id
        let saved = await store.saveTrayTags([.red, .blue], vaultID: id)
        precondition(saved && store.vault!.trayEntries.map(\.id) == [child, multi])
        precondition(store.vault!.trayEntries[0].path == "Inherited › Nested")
        let suite = "dev.keepy.tray-tags-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcut = TrayShortcutSettings(defaults: defaults)
        precondition(shortcut.set(enabled: false, shortcut: .default))
        let tray = TrayMenuController()
        var opens = 0
        tray.start(store: store, shortcuts: shortcut, openWindow: { opens += 1 }, openSettings: {})
        defer { tray.stop() }
        tray.menuNeedsUpdate(tray.menu)
        func items() -> [NSMenuItem] { tray.menu.items.filter { $0.representedObject is String } }
        func waitFor(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("Tray menu did not update from the current vault")
        }
        precondition(items().count == 2 && !tray.menu.items.map(\.title).joined().contains("synthetic-user"))
        let captured = items().first!
        let coordinator = VaultOutline.Coordinator(store)
        let scroll = VaultOutline.makeScrollView(coordinator: coordinator)
        let outline = coordinator.outline!
        defer { outline.detachKeyboardMonitor(); _ = scroll }
        store.search = "no match"; store.tagFilter = [.orange]
        coordinator.update(store.filteredNodes)
        NSApp.sendAction(captured.action!, to: captured.target, from: captured)
        precondition(opens == 1 && store.selection == child && !store.isFiltering)
        coordinator.update(store.filteredNodes)
        precondition(outline.isItemExpanded(coordinator.boxes[group]) && outline.isItemExpanded(coordinator.boxes[nested]))
        precondition((outline.item(atRow: outline.selectedRow) as? OutlineNode)?.node?.id == child)
        let token = store.entryNavigation?.token
        store.busy = true; tray.menuNeedsUpdate(tray.menu)
        precondition(items().allSatisfy { !$0.isEnabled })
        NSApp.sendAction(captured.action!, to: captured.target, from: captured)
        precondition(opens == 1 && store.entryNavigation?.token == token)
        store.busy = false; store.editor = EditorRoute(kind: .entry(nil))
        let blocked = await store.saveTrayTags([], vaultID: id)
        precondition(!blocked && !store.selectTrayEntry(child))
        store.editor = nil
        let blue = await store.saveTrayTags([.blue], vaultID: id)
        precondition(blue)
        try await waitFor { items().count == 1 && items()[0].representedObject as? String == multi }
        let retagged = await store.setTags([.blue], for: store.vault!.node(excluded)!)
        precondition(retagged)
        try await waitFor { items().count == 2 }
        let cleared = await store.saveTrayTags([], vaultID: id)
        precondition(cleared)
        try await waitFor { items().isEmpty && tray.menu.items.contains { $0.title == "Choose tags to show credentials here." } }
        let empty = await store.saveTrayTags([.green], vaultID: id)
        precondition(empty)
        try await waitFor { tray.menu.items.contains { $0.title == "No credentials match the selected tags." } }
        let restored = await store.saveTrayTags([.blue], vaultID: id)
        precondition(restored)
        store.lock()
        precondition(items().isEmpty && tray.menu.items[0].title == "Vault locked")
        precondition(!store.selectTrayEntry(child))
        NSApp.sendAction(captured.action!, to: captured.target, from: captured)
        precondition(opens == 1)
        tray.stop(); await store.shutdown()
        let reopened = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await reopened.refresh(); reopened.selectedVaultId = id
        let unlocked = await reopened.authenticate(password: "synthetic-tray-password")
        precondition(unlocked && reopened.vault!.trayTags == [.blue] && Set(reopened.vault!.trayEntries.map(\.id)) == [multi, excluded])
        let another = await reopened.authenticate(name: "Other Tray Tags Native", password: "synthetic-other-password")
        precondition(another && reopened.vault!.trayTags.isEmpty)
        await reopened.shutdown()
        print("Native tray tags passed: legacy defaults, inherited OR matching, deduplication, native menu actions, tree reveal, editor guards, automatic updates, empty/locked states and per-vault restart persistence.")
    }
}
