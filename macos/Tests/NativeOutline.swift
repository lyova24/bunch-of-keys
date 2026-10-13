import AppKit
import SwiftUI

// Exercises the same native drop handlers used by AppKit, with private
// pasteboards and a real encrypted service; no desktop input is synthesized.
@MainActor private final class TestDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(_ board: NSPasteboard) { draggingPasteboard = board }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
@MainActor enum NativeOutline {
    static func verifyTrailingGeometry() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("dev.bunchofkeys.geometry-test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let field = VaultField(id: "geometry-field", label: "Username", kind: "text", masked: false, value: "synthetic", ssh: nil)
        let leaf = VaultNode(id: "geometry-leaf", name: "A long nested entry title that must leave room for its colored tag", type: "entry", fields: [field], tags: [.blue])
        var nested = leaf
        for depth in (0..<4).reversed() {
            let entry = VaultNode(id: "geometry-entry-\(depth)", name: "Another long credential title at depth \(depth)", type: "entry", fields: [], tags: [.purple])
            nested = VaultNode(id: "geometry-group-\(depth)", name: "A long tagged folder title at depth \(depth)", type: "group", children: [entry, nested], tags: TagColor.allCases)
        }
        let rootEntry = VaultNode(id: "geometry-root-entry", name: "Root credential", type: "entry", fields: [], tags: [.green])
        let filler = (0..<24).map { VaultNode(id: "geometry-filler-\($0)", name: "Additional credential \($0)", type: "entry", fields: []) }
        for style in [NSScroller.Style.overlay, .legacy] {
            for hasScroller in [false, true] {
                let store = AppStore(core: CoreClient(executable: URL(fileURLWithPath: "/usr/bin/false")), pasteboard: board)
                store.vault = Vault(id: "geometry-vault", sshKeys: [], nodes: [nested, rootEntry] + filler)
                let coordinator = VaultOutline.Coordinator(store); coordinator.didFocus = true
                let scroll = VaultOutline.makeScrollView(coordinator: coordinator)
                scroll.scrollerStyle = style; scroll.hasVerticalScroller = hasScroller; scroll.autohidesScrollers = false
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 480), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = scroll
                defer { window.close() }
                let outline = coordinator.outline!
                coordinator.update(store.filteredNodes); outline.expandItem(nil, expandChildren: true)
                for width in [480, 960, 480] {
                    window.setContentSize(NSSize(width: width, height: 480))
                    for _ in 0..<3 {
                        window.contentView?.layoutSubtreeIfNeeded(); outline.layoutSubtreeIfNeeded()
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    var trailingEdges: [CGFloat] = []
                    for row in 0..<outline.numberOfRows {
                        guard let item = outline.item(atRow: row) as? OutlineNode, item.node?.tags.isEmpty == false else { continue }
                        let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as! NodeOutlineCell
                        cell.layoutSubtreeIfNeeded()
                        let dots = cell.subviews.compactMap { $0 as? TagDotsView }.first!
                        let right = dots.convert(dots.bounds, to: scroll.contentView).maxX
                        let margin = scroll.contentView.bounds.maxX - right
                        precondition(abs(margin - 16) < 0.75, "Tagged rows must keep a 16-point viewport margin, including native inset, indentation, scrollers and resizing (got \(margin))")
                        // NSTextField's frame extends two points past its alignment
                        // rect, so the ten-point constraint leaves an eight-point gap.
                        precondition(cell.textField!.frame.maxX <= dots.frame.minX - 7, "Long titles must truncate before their tag markers")
                        trailingEdges.append(right)
                    }
                    precondition(trailingEdges.count == 10, "Geometry coverage must include root and deeply nested tagged groups and entries")
                    precondition(trailingEdges.max()! - trailingEdges.min()! < 0.75, "Tag trailing edges must align at every hierarchy depth")
                    let fieldItem = coordinator.boxes["field:\(leaf.id):\(field.id)"]!
                    let fieldRow = outline.row(forItem: fieldItem)
                    let fieldCell = outline.view(atColumn: 0, row: fieldRow, makeIfNecessary: true) as! HostedOutlineCell
                    fieldCell.layoutSubtreeIfNeeded()
                    let fieldRight = fieldCell.host.convert(fieldCell.host.bounds, to: scroll.contentView).maxX
                    let fieldMargin = scroll.contentView.bounds.maxX - fieldRight
                    precondition(fieldMargin >= 11.25 && fieldMargin <= 16.75, "Hosted fields must preserve 12–16 points of native outer spacing before their inner action padding (got \(fieldMargin), cell \(fieldCell.frame), host \(fieldCell.host.frame))")
                }
                store.editor = EditorRoute(kind: .entry(leaf))
                coordinator.update(store.filteredNodes)
                window.contentView?.layoutSubtreeIfNeeded(); outline.layoutSubtreeIfNeeded()
                let editorItem = coordinator.boxes["editor:\(store.editor!.id)"]!
                let editorCell = outline.view(atColumn: 0, row: outline.row(forItem: editorItem), makeIfNecessary: true) as! HostedOutlineCell
                editorCell.layoutSubtreeIfNeeded()
                let editorRight = editorCell.host.convert(editorCell.host.bounds, to: scroll.contentView).maxX
                let editorMargin = scroll.contentView.bounds.maxX - editorRight
                precondition(editorMargin >= 11.25 && editorMargin <= 16.75, "Nested editor content must preserve native outer spacing inside the viewport (got \(editorMargin))")
            }
        }
        print("Native outline geometry passed: aligned 16-point tag margins, nested hosted content, 480/960-point resize and overlay/legacy scrollers.")
    }
    static func run(executable: URL) async throws {
        try await verifyTrailingGeometry()
        let board = NSPasteboard(name: .init("dev.bunchofkeys.outline-test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await store.refresh()
        let created = await store.authenticate(name: "Outline Test", password: "synthetic-outline-password")
        precondition(created)
        let workSaved = await store.mutate("add_group", ["name": "Work"])
        precondition(workSaved)
        let work = store.vault!.nodes.last!.id
        let otherSaved = await store.mutate("add_group", ["name": "Other"])
        precondition(otherSaved)
        let other = store.vault!.nodes.last!.id
        let entrySaved = await store.mutate("add_entry", ["parent_id": work, "name": "Server", "fields": [
            ["label": "Password", "kind": "secret", "masked": true, "value": "synthetic-outline-secret"],
            ["label": "Username", "kind": "text", "masked": false, "value": "deploy"]
        ]])
        precondition(entrySaved)
        let entry = store.vault!.node(work)!.children!.first!
        let secret = entry.fields!.first!.id
        let taggedWork = await store.setTags([.red], for: store.vault!.node(work)!)
        let taggedEntry = await store.setTags([.blue, .purple], for: entry)
        precondition(taggedWork && taggedEntry)
        let coordinator = VaultOutline.Coordinator(store)
        let outline = VaultOutlineView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
        let column = NSTableColumn(identifier: .init("test"))
        outline.addTableColumn(column); outline.outlineTableColumn = column
        outline.dataSource = coordinator; outline.delegate = coordinator; coordinator.outline = outline
        coordinator.update(store.filteredNodes)
        let info = TestDrag(board)
        func payload(_ type: String, _ value: String) {
            board.clearContents(); board.setData(Data(value.utf8), forType: .init(type))
        }
        func waitFor(_ predicate: () -> Bool) async throws {
            for _ in 0..<200 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            preconditionFailure("Native drop did not persist: \(store.error ?? "no response")")
        }
        for (id, tags) in [(work, [TagColor.red]), (entry.id, [TagColor.blue, .purple])] {
            let item = coordinator.boxes[id]!
            let cell = coordinator.outlineView(outline, viewFor: column, item: item) as! NSTableCellView
            let dots = cell.subviews.compactMap { $0 as? TagDotsView }.first!
            precondition(dots.tags == tags)
            precondition(tags.allSatisfy { cell.accessibilityLabel()?.contains($0.title) == true }, "Rows must expose tag color names to VoiceOver")
        }
        let menu = NSMenu()
        coordinator.populateMenu(menu, for: coordinator.boxes[entry.id])
        let tagsMenu = menu.item(withTitle: "Tags")!.submenu!
        precondition(tagsMenu.items.filter { $0.state == .on }.map(\.title) == ["Blue", "Purple"])
        precondition(tagsMenu.items.filter { $0.representedObject != nil }.count == TagColor.allCases.count)
        precondition(tagsMenu.item(withTitle: "Remove All Tags")!.isEnabled)
        store.busy = true
        coordinator.populateMenu(menu, for: coordinator.boxes[entry.id])
        precondition(!menu.item(withTitle: "Tags")!.isEnabled)
        precondition(menu.item(withTitle: "Tags")!.submenu!.items.filter { !$0.isSeparatorItem }.allSatisfy { !$0.isEnabled })
        store.busy = false
        coordinator.populateMenu(menu, for: coordinator.boxes[entry.id])
        coordinator.toggleTag(menu.item(withTitle: "Tags")!.submenu!.item(withTitle: "Green")!)
        try await waitFor { store.vault?.node(entry.id)?.tags.contains(.green) == true }
        coordinator.update(store.filteredNodes)
        precondition(store.vault?.node(entry.id)?.tags == [.green, .blue, .purple])
        store.tagFilter = [.blue]
        coordinator.update(store.filteredNodes)
        precondition(coordinator.roots.map(\.id) == [work], "A tagged child must retain its parent context")
        precondition(outline.isItemExpanded(coordinator.boxes[work]!))
        precondition(coordinator.outlineView(outline, pasteboardWriterForItem: coordinator.boxes[entry.id]!) == nil)
        payload("dev.bunchofkeys.node", entry.id)
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: nil, proposedChildIndex: 0).isEmpty)
        precondition(!coordinator.outlineView(outline, acceptDrop: info, item: nil, childIndex: 0), "Filtered tree positions must never be used for moves")
        store.search = "No matching item"
        coordinator.update(store.filteredNodes)
        precondition(coordinator.roots.isEmpty)
        store.clearFilters(); coordinator.update(store.filteredNodes)
        payload("dev.bunchofkeys.saved-field", "\(entry.id):\(secret)")
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: coordinator.boxes[entry.id], proposedChildIndex: 2) == .move)
        precondition(coordinator.outlineView(outline, acceptDrop: info, item: coordinator.boxes[entry.id], childIndex: 2))
        try await waitFor { store.vault?.node(entry.id)?.fields?.last?.id == secret }
        precondition(store.vault?.node(entry.id)?.fields?.last?.value == nil, "Moving must not reveal secrets")
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: coordinator.boxes[other], proposedChildIndex: 0).isEmpty)
        store.search = "Server"
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: coordinator.boxes[entry.id], proposedChildIndex: 0).isEmpty)
        store.search = ""
        payload("dev.bunchofkeys.node", work)
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: coordinator.boxes[work], proposedChildIndex: -1).isEmpty)
        payload("dev.bunchofkeys.node", entry.id)
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: coordinator.boxes[other], proposedChildIndex: -1) == .move)
        precondition(coordinator.outlineView(outline, acceptDrop: info, item: coordinator.boxes[other], childIndex: -1))
        try await waitFor { store.vault?.parent(of: entry.id) == other }
        coordinator.update(store.filteredNodes)
        store.selection = work; store.addEntry()
        let route = store.editor!
        coordinator.update(store.filteredNodes)
        coordinator.populateMenu(menu, for: coordinator.boxes[entry.id])
        precondition(!menu.item(withTitle: "Tags")!.isEnabled, "An editor must disable context tag mutation")
        let host = coordinator.editorHost
        let nodeCount = store.vault!.nodes
        payload("dev.bunchofkeys.draft", route.id.uuidString)
        let draft = coordinator.boxes["draft:\(route.id)"]!
        precondition(coordinator.outlineView(outline, shouldSelectItem: draft), "Draft rows must be selectable for native dragging")
        outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: draft)), byExtendingSelection: false)
        coordinator.update(store.filteredNodes)
        precondition((outline.item(atRow: outline.selectedRow) as? OutlineNode)?.id == draft.id, "Keep the draft selected while native dragging starts")
        let writer = coordinator.outlineView(outline, pasteboardWriterForItem: draft) as! NSPasteboardItem
        precondition(writer.data(forType: .init("dev.bunchofkeys.draft")) == Data(route.id.uuidString.utf8))
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: coordinator.boxes[other], proposedChildIndex: 0) == .move)
        precondition(coordinator.outlineView(outline, acceptDrop: info, item: coordinator.boxes[other], childIndex: 0))
        coordinator.update(store.filteredNodes)
        precondition(store.editor?.id == route.id && store.editor?.parentId == other && store.editor?.insertionIndex == 0)
        precondition((outline.item(atRow: outline.selectedRow) as? OutlineNode)?.id == draft.id, "Keep the moved draft selected")
        precondition(coordinator.editorHost === host, "Keep the hosting view and its unsaved SwiftUI state when moving a draft")
        precondition(coordinator.boxes[other]?.children.first?.id == draft.id)
        precondition(store.vault!.nodes == nodeCount, "Moving an unsaved draft must not persist it")
        await store.shutdown()
        print("Native outline passed: tag dots and accessibility, context tag menus, filtered move guards, field ordering, node moves, cycle protection and unsaved draft identity.")
    }
}
