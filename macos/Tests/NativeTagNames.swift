import AppKit
import Foundation

@MainActor enum NativeTagNames {
    static func run(executable: URL) async throws {
        let legacy = try JSONDecoder().decode(Vault.self, from: Data("{\"id\":\"old\",\"sshKeys\":[],\"nodes\":[]}".utf8))
        precondition(legacy.tagNames.isEmpty)
        precondition(TagNaming.label(.green, in: [:]) == "Green")
        precondition(TagNaming.normalized(["green":"  Production  ","red":" red "]) == ["green":"Production"])
        for input in [["green":"Blue"], ["green":"Production","red":"pRODUCTion"], ["green":"Работа","red":"работа"], ["green":String(repeating:"Ж",count:41)], ["green":"bad\nname"]] {
            precondition(TagNaming.error(input) != nil)
        }
        precondition(TagNaming.error(["green":String(repeating:"Ж",count:40)]) == nil)
        let board = NSPasteboard(name:.init("dev.keepy.tag-names.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = AppStore(core:CoreClient(executable:executable),pasteboard:board)
        await store.refresh()
        let created = await store.authenticate(name:"Tag names native",password:"synthetic-tag-names-password")
        precondition(created)
        let id = store.vault!.id
        let grouped = await store.mutate("add_group",["name":"Work","tags":["green"]]); precondition(grouped)
        let group = store.vault!.nodes[0].id
        let added = await store.mutate("add_entry",["parent_id":group,"name":"Account","tags":["red"],"fields":[
            ["label":"Password","kind":"secret","masked":true,"value":"synthetic-named-tag-secret","tags":["blue"]]
        ]]); precondition(added)
        let entry = store.vault!.node(group)!.children![0].id
        let tray = await store.saveTrayTags([.green],vaultID:id); precondition(tray)
        store.tagFilter = [.green]; store.search = "Account"; store.selection = entry
        let suite = "dev.keepy.named-tray.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = TrayShortcutSettings(defaults: defaults)
        precondition(shortcuts.set(enabled: false, shortcut: .default))
        let trayMenu = TrayMenuController()
        trayMenu.start(store: store, shortcuts: shortcuts, openWindow: {}, openSettings: {})
        defer { trayMenu.stop() }
        trayMenu.menuNeedsUpdate(trayMenu.menu)
        func groupTitle() -> String? { trayMenu.menu.items.first { $0.representedObject as? TagColor == .green }?.title }
        precondition(groupTitle() == "Green")
        let filtered = store.filteredNodes, nodes = store.vault!.nodes, credentials = store.vault!.trayCredentials
        let coordinator = VaultOutline.Coordinator(store)
        let scroll = VaultOutline.makeScrollView(coordinator:coordinator)
        defer { coordinator.outline?.detachKeyboardMonitor(); _ = scroll }
        coordinator.update(store.filteredNodes)
        let editNames = trayMenu.menu.items.first { $0.title == "Tag Names…" }!
        NSApp.sendAction(editNames.action!, to: editNames.target, from: editNames)
        precondition(store.editor != nil && store.tagFilter == [.green] && store.search == "Account")
        // Dismissing a draft does not call the persistence operation.
        store.editor = nil
        precondition(store.vault!.tagNames.isEmpty && store.filteredNodes == filtered)
        store.manageTagNames()
        let renamed = await store.saveTagNames(["green":"  Production ","red":"Personal","blue":"Password only"],vaultID:id)
        precondition(renamed); store.editor = nil
        for _ in 0..<100 {
            if groupTitle() == "Production (Green)" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(groupTitle() == "Production (Green)", "Already-created tray groups must update when a tag is renamed")
        let namedGroup = trayMenu.menu.items.first { $0.representedObject as? TagColor == .green }!
        precondition(namedGroup.image != nil && namedGroup.submenu!.items.count == 1)
        precondition(store.tagLabel(.green) == "Production (Green)" && store.tagLabel(.yellow) == "Yellow")
        precondition(store.vault!.nodes == nodes && store.filteredNodes == filtered && store.vault!.trayCredentials == credentials)
        precondition(store.tagFilter == [.green] && store.search == "Account" && store.selection == entry)
        coordinator.update(store.filteredNodes)
        precondition(coordinator.previousTagNames == store.vault!.tagNames)
        let groupBox = coordinator.boxes[group]!
        let cell = coordinator.outlineView(coordinator.outline!, viewFor:nil, item:groupBox)!
        precondition(cell.accessibilityLabel()!.contains("Production (Green)"))
        let dots = cell.subviews.compactMap { $0 as? TagDotsView }.first!
        precondition(dots.toolTip == "Production (Green)" && dots.accessibilityLabel()!.contains("Production (Green)"))
        let menu = NSMenu(); coordinator.populateMenu(menu,for:groupBox)
        let tagMenu = menu.items.first { $0.title == "Tags" }!.submenu!
        let namedItem = tagMenu.items.first { $0.title == "Production (Green)" }!
        precondition(namedItem.state == .on && namedItem.representedObject as? String == "green")
        let before = store.vault!
        let invalid = await store.saveTagNames(["green":"Blue"],vaultID:id)
        precondition(!invalid && store.vault == before && store.filteredNodes == filtered && store.tagFilter == [.green])
        store.error = nil
        let dataRoot = URL(fileURLWithPath:ProcessInfo.processInfo.environment["KEEPY_DATA_DIR"]!)
        let file = dataRoot.appendingPathComponent("vaults/\(id).bok")
        let backup = file.appendingPathExtension("before-name-save")
        let bytes = try Data(contentsOf:file)
        try FileManager.default.moveItem(at:file,to:backup)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        let failed = await store.saveTagNames(["green":"Failed update"],vaultID:id)
        precondition(!failed && store.error != nil && store.vault == before && store.filteredNodes == filtered && store.tagFilter == [.green])
        let preservedBytes = try Data(contentsOf:backup)
        precondition(preservedBytes == bytes)
        try FileManager.default.removeItem(at:file)
        try FileManager.default.moveItem(at:backup,to:file)
        store.error = nil
        store.editor = EditorRoute(kind:.entry(nil))
        let blocked = await store.saveTagNames([:],vaultID:id); precondition(!blocked)
        store.editor = nil
        store.lock(); precondition(store.tagLabel(.green) == "Green")
        await store.shutdown()
        let reopened = AppStore(core:CoreClient(executable:executable),pasteboard:board)
        await reopened.refresh(); reopened.selectedVaultId = id
        let unlocked = await reopened.authenticate(password:"synthetic-tag-names-password")
        precondition(unlocked && reopened.vault!.tagNames == before.tagNames && reopened.vault!.nodes == nodes)
        let other = await reopened.authenticate(name:"Other tag names native",password:"synthetic-other-password")
        precondition(other && reopened.vault!.tagNames.isEmpty && reopened.tagLabel(.green) == "Green")
        let wrong = await reopened.saveTagNames(["green":"Wrong vault"],vaultID:id); precondition(!wrong)
        reopened.selectedVaultId = id
        let original = await reopened.authenticate(password:"synthetic-tag-names-password"); precondition(original)
        reopened.tagFilter = [.green]
        let reset = await reopened.saveTagNames(["green":"","red":"Red","blue":"Blue"],vaultID:id)
        precondition(reset && reopened.vault!.tagNames.isEmpty && reopened.tagFilter == [.green] && reopened.vault!.nodes == nodes)
        await reopened.shutdown()
        print("Native tag names passed: legacy defaults, Unicode validation, named rows/context menus, live filter stability, cancellation, failed-write rollback, encrypted restart, reset and vault isolation.")
    }
}
