import AppKit

@MainActor enum NativeSearchExpansion {
    static func run() {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("dev.keepy.search-expansion.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let field = VaultField(id: "field", label: "Username", kind: "text", masked: false, value: "synthetic", ssh: nil)
        let closed = VaultNode(id: "closed", name: "Match closed", type: "entry", fields: [field], tags: [.blue])
        let opened = VaultNode(id: "opened", name: "Match opened", type: "entry", fields: [field], tags: [.blue])
        let nested = VaultNode(id: "nested", name: "Nested", type: "group", children: [closed])
        let group = VaultNode(id: "group", name: "Group", type: "group", children: [nested, opened])
        let root = VaultNode(id: "root", name: "Match root", type: "entry", fields: [field], tags: [.blue])
        let store = AppStore(core: CoreClient(executable: URL(fileURLWithPath: "/usr/bin/false")), pasteboard: board)
        store.ready = true; store.vault = Vault(id: "search-vault", sshKeys: [], nodes: [group, root])
        let coordinator = VaultOutline.Coordinator(store)
        let scroll = VaultOutline.makeScrollView(coordinator: coordinator)
        let outline = coordinator.outline!
        defer { outline.detachKeyboardMonitor(); _ = scroll }
        func update() { coordinator.update(store.filteredNodes) }
        func expanded(_ id: String) -> Bool { outline.isItemExpanded(coordinator.boxes[id]) }
        update()
        outline.expandItem(coordinator.boxes["group"]!)
        outline.expandItem(coordinator.boxes["opened"]!)
        let original = coordinator.expanded
        precondition(original == ["group", "opened"])
        store.search = "Match"; update()
        precondition(expanded("nested") && expanded("closed") && expanded("root"))
        precondition(coordinator.expanded == original, "Automatic expansion must not overwrite browsing state")
        outline.collapseItem(coordinator.boxes["opened"]!)
        precondition(coordinator.expanded == original, "Filter-time interaction must stay temporary")
        store.search = "Match closed"; update()
        store.search = "Match"; update()
        precondition(coordinator.expanded == original)
        store.search = ""; update()
        precondition(expanded("group") && expanded("opened"))
        precondition(!expanded("nested") && !expanded("closed") && !expanded("root"))
        // Search and tag-only results intentionally have the same item objects.
        // Clearing text must nevertheless remove search-only entry expansion.
        store.tagFilter = [.blue]; update()
        precondition(expanded("group") && expanded("nested") && !expanded("closed") && !expanded("root"))
        store.search = "Match"; update()
        precondition(expanded("closed") && expanded("root"))
        store.search = ""; update()
        precondition(expanded("group") && expanded("nested") && expanded("opened"))
        precondition(!expanded("closed") && !expanded("root"))
        store.tagFilter.removeAll(); update()
        precondition(expanded("group") && expanded("opened") && !expanded("nested") && !expanded("root"))
        store.tagFilter = [.blue]; update()
        outline.expandItem(coordinator.boxes["root"]!)
        store.search = "Match"; update()
        store.search = ""; update()
        precondition(expanded("root"), "An entry manually opened before text search within a tag filter must be restored")
        store.tagFilter.removeAll(); update()
        precondition(!expanded("root"), "Clearing tags restores the original unfiltered browsing state")
        // A second filtering session starts from the user's new browsing state.
        outline.collapseItem(coordinator.boxes["group"]!)
        outline.expandItem(coordinator.boxes["root"]!)
        let next = coordinator.expanded
        store.search = "no matches"; update()
        precondition(outline.numberOfRows == 0)
        store.search = ""; update()
        precondition(!expanded("group") && expanded("root") && coordinator.expanded == next)
        outline.expandItem(coordinator.boxes["group"]!)
        precondition(expanded("opened") == next.contains("opened"), "Reopening must match the saved descendant state: \(next)")
        print("Native search expansion passed: original groups/entries, repeated queries, manual filter interaction, identical results, tags, empty results and repeated sessions.")
    }
}
