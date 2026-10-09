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
    static func run(executable: URL) async throws {
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
        print("Native outline passed: field ordering, node moves, cycle protection, search guard and unsaved draft identity.")
    }
}
