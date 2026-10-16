import AppKit
import Foundation

@MainActor enum NativeTrayTags {
    static func run(executable: URL, encryptedKey: URL) async throws {
        let legacy = try JSONDecoder().decode(Vault.self, from: Data("{\"id\":\"legacy\",\"sshKeys\":[],\"nodes\":[{\"id\":\"e\",\"name\":\"Old\",\"type\":\"entry\",\"fields\":[{\"id\":\"f\",\"label\":\"Password\",\"kind\":\"secret\",\"masked\":true}]}]}".utf8))
        precondition(legacy.trayTags.isEmpty && legacy.trayCredentials.isEmpty && legacy.nodes[0].fields![0].tags.isEmpty)
        let board = NSPasteboard(name: .init("dev.keepy.tray-tags.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var openedURLs: [URL] = []
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board, openExternalURL: { openedURLs.append($0); return true })
        await store.refresh()
        let created = await store.authenticate(name: "Tray Tags Native", password: "synthetic-tray-password")
        precondition(created && store.vault!.trayTags.isEmpty)
        let id = store.vault!.id
        func mutate(_ command: String, _ args: [String: Any]) async {
            let saved = await store.mutate(command, args); precondition(saved, store.error ?? command)
        }
        func waitFor(_ predicate: () -> Bool) async throws {
            for _ in 0..<200 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("Credential action or live menu update did not complete")
        }
        await mutate("add_group", ["name": "Inherited", "tags": ["red"]])
        let group = store.vault!.nodes[0].id
        await mutate("add_group", ["parent_id": group, "name": "Nested"])
        let nested = store.vault!.node(group)!.children![0].id
        await mutate("add_entry", ["parent_id": nested, "name": "From group", "fields": [
            ["label": "Username", "kind": "text", "masked": false, "value": "synthetic-user"]
        ]])
        let child = store.vault!.node(nested)!.children![0].id
        await mutate("add_entry", ["name": "Multiple tags", "tags": ["red", "blue"], "fields": [
            ["label": "Username", "kind": "text", "masked": false, "value": "synthetic-multiple", "tags": ["red", "blue"]],
            ["label": "Website", "kind": "url", "masked": false, "value": "https://example.com/tray", "tags": ["blue"]]
        ]])
        let multi = store.vault!.nodes.last!.id
        let website = store.vault!.node(multi)!.fields![1].id
        await mutate("add_entry", ["name": "Direct field", "fields": [
            ["label": "Username", "kind": "text", "masked": false, "value": "not-tagged"],
            ["label": "Password", "kind": "secret", "masked": true, "value": "synthetic-field-secret", "tags": ["blue"]]
        ]])
        let direct = store.vault!.nodes.last!.id
        let password = store.vault!.node(direct)!.fields![1].id
        let draft = FieldDraft(store.vault!.node(direct)!.fields![1])
        precondition(draft.tags == [.blue] && draft.payload["tags"] as? [String] == ["blue"])
        await mutate("add_ssh_key", ["name": "Encrypted tray key", "private_key": try String(contentsOf: encryptedKey, encoding: .utf8)])
        let key = store.vault!.sshKeys.last!.id
        await mutate("add_entry", ["name": "Server", "fields": [
            ["label": "Connect", "kind": "ssh", "value": "", "masked": false, "tags": ["blue"], "ssh": ["key_id": key, "user": "deploy", "address": "localhost"]]
        ]])
        let server = store.vault!.nodes.last!.id
        await mutate("add_entry", ["name": "Excluded", "tags": ["orange"], "fields": [
            ["label": "Username", "kind": "text", "value": "excluded-value", "masked": false]
        ]])
        let excluded = store.vault!.nodes.last!.id
        let saved = await store.saveTrayTags([.red, .blue], vaultID: id)
        precondition(saved && store.vault!.trayCredentials.count == 5)
        precondition(store.vault!.trayCredentials[0].path == "Inherited › Nested" && store.vault!.trayCredentials[0].id.entryID == child)
        precondition(store.vault!.trayCredentials.filter { $0.id.entryID == direct }.map(\.id.fieldID) == [password])
        precondition(store.vault!.trayCredentials.filter { $0.id.entryID == multi }.count == 2, "Do not duplicate fields matching inherited and direct colors")
        store.tagFilter = [.blue]
        precondition(store.filteredNodes.first { $0.id == direct }!.fields!.map(\.id) == [password])
        store.clearFilters()
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
        func items() -> [NSMenuItem] {
            tray.menu.items.flatMap { $0.submenu?.items ?? [] }.filter { $0.representedObject is CredentialTarget }
        }
        func item(_ entry: String, _ field: String? = nil) -> NSMenuItem {
            items().first { item in
                guard let target = item.representedObject as? CredentialTarget else { return false }
                return target.entryID == entry && (field == nil || target.fieldID == field)
            }!
        }
        precondition(items().count == 7 && Set(items().compactMap { $0.representedObject as? CredentialTarget }).count == 5)
        precondition(!tray.menu.items.contains { $0.representedObject is CredentialTarget }, "Credentials must live inside tag submenus")
        let groups = tray.menu.items.filter { $0.representedObject is TagColor }
        precondition(groups.map(\.title) == ["Red", "Blue"] && groups.allSatisfy { $0.image != nil })
        precondition(groups[0].submenu!.items.count == 3 && groups[1].submenu!.items.count == 4)
        for group in groups {
            let targets = group.submenu!.items.compactMap { $0.representedObject as? CredentialTarget }
            precondition(Set(targets).count == targets.count, "No duplicate credentials inside one tag group")
        }
        let titles = (tray.menu.items + items()).map { $0.title + ($0.toolTip ?? "") }.joined()
        precondition(!titles.contains("synthetic-user") && !titles.contains("synthetic-field-secret"))
        let captured = item(direct, password)
        store.search = "no match"; store.tagFilter = [.orange]; store.selection = excluded
        NSApp.sendAction(captured.action!, to: captured.target, from: captured)
        try await waitFor { board.string(forType: .string) == "synthetic-field-secret" }
        precondition(opens == 0 && store.search == "no match" && store.selection == excluded, "Tray copy must not open or navigate the window")
        store.clearClipboard()
        NSApp.sendAction(item(multi, website).action!, to: item(multi, website).target, from: item(multi, website))
        try await waitFor { openedURLs.count == 1 }
        precondition(openedURLs[0].absoluteString == "https://example.com/tray" && opens == 0)
        store.clearFilters()
        let coordinator = VaultOutline.Coordinator(store)
        let scroll = VaultOutline.makeScrollView(coordinator: coordinator)
        let outline = coordinator.outline!
        defer { outline.detachKeyboardMonitor(); _ = scroll }
        coordinator.update(store.filteredNodes)
        outline.expandItem(coordinator.boxes[direct])
        let fieldBox = coordinator.boxes["field:\(direct):\(password)"]!
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: fieldBox)), byExtendingSelection: false)
        coordinator.activate()
        try await waitFor { board.string(forType: .string) == "synthetic-field-secret" }
        let context = NSMenu(); coordinator.populateMenu(context, for: fieldBox)
        let tags = context.items.first { $0.title == "Tags" }!.submenu!
        precondition(tags.items.first { $0.title == "Blue" }!.state == .on)
        let green = tags.items.first { $0.title == "Green" }!
        NSApp.sendAction(green.action!, to: green.target, from: green)
        try await waitFor { store.vault!.node(direct)!.fields![1].tags.contains(.green) }
        precondition(store.vault!.node(direct)!.fields![1].value == nil)
        let sshItem = item(server)
        NSApp.sendAction(sshItem.action!, to: sshItem.target, from: sshItem)
        try await waitFor { store.sshPrompt != nil && opens == 1 }
        precondition(store.sshPrompt!.entry == server && store.activeSSH.isEmpty, "Encrypted SSH must request its passphrase without launching a connection")
        store.sshPrompt = nil
        store.busy = true; tray.menuNeedsUpdate(tray.menu)
        precondition(items().allSatisfy { !$0.isEnabled })
        let busyAction = await store.activateTrayCredential(captured.representedObject as! CredentialTarget)
        precondition(!busyAction)
        store.busy = false; store.editor = EditorRoute(kind: .entry(nil))
        let blocked = await store.setFieldTags([], entry: direct, field: password)
        let editingAction = await store.activateTrayCredential(captured.representedObject as! CredentialTarget)
        precondition(!blocked && !editingAction)
        store.editor = nil
        let retagged = await store.setFieldTags([.orange], entry: direct, field: password)
        precondition(retagged)
        try await waitFor { !items().contains { ($0.representedObject as? CredentialTarget)?.fieldID == password } }
        board.clearContents()
        let stale = await store.activateTrayCredential(captured.representedObject as! CredentialTarget)
        precondition(!stale && board.string(forType: .string) == nil)
        let cleared = await store.saveTrayTags([], vaultID: id)
        precondition(cleared)
        try await waitFor { items().isEmpty && tray.menu.items.contains { $0.title == "Choose tags to show credentials here." } }
        let empty = await store.saveTrayTags([.gray], vaultID: id)
        precondition(empty)
        try await waitFor { tray.menu.items.contains { $0.title == "No credentials match the selected tags." } }
        let emptyGroup = tray.menu.items.first { $0.representedObject as? TagColor == .gray }!
        precondition(emptyGroup.image != nil && emptyGroup.submenu!.items[0].title == "No credentials match this tag." && !emptyGroup.submenu!.items[0].isEnabled)
        let restored = await store.saveTrayTags([.blue], vaultID: id)
        precondition(restored)
        let retaggedBack = await store.setFieldTags([.blue], entry: direct, field: password)
        precondition(retaggedBack)
        store.settings.clipboardClearSeconds = 1
        let copied = await store.activateTrayCredential(captured.representedObject as! CredentialTarget)
        precondition(copied && board.string(forType: .string) == "synthetic-field-secret")
        try await waitFor { board.string(forType: .string) == nil }
        let lateAction = Task { await store.activateTrayCredential(captured.representedObject as! CredentialTarget) }
        store.lock()
        _ = await lateAction.value
        precondition(items().isEmpty && tray.menu.items[0].title == "Vault locked" && board.string(forType: .string) == nil)
        NSApp.sendAction(captured.action!, to: captured.target, from: captured)
        try await Task.sleep(for: .milliseconds(50))
        precondition(opens == 1 && board.string(forType: .string) == nil)
        tray.stop(); await store.shutdown()
        let reopened = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await reopened.refresh(); reopened.selectedVaultId = id
        let unlocked = await reopened.authenticate(password: "synthetic-tray-password")
        precondition(unlocked && reopened.vault!.trayTags == [.blue] && reopened.vault!.node(direct)!.fields![1].tags == [.blue])
        precondition(reopened.vault!.trayCredentials.count == 4)
        let another = await reopened.authenticate(name: "Other Tray Tags Native", password: "synthetic-other-password")
        precondition(another && reopened.vault!.trayTags.isEmpty)
        let wrongVaultAction = await reopened.activateTrayCredential(captured.representedObject as! CredentialTarget)
        precondition(!wrongVaultAction)
        await reopened.shutdown()
        print("Native tray tags passed: field tags, editor payload, context menus, inheritance, deduplication, copy/URL/SSH actions, Enter parity, clipboard expiry, live updates, stale-action guards and encrypted restart persistence.")
    }
}
