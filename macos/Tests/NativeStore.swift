import Foundation
import AppKit

@MainActor enum NativeStore {
    static func run(executable: URL, vaultId: String, entryId: String, fieldId: String) async throws {
        // A private pasteboard never alters the user's clipboard during tests.
        let board = NSPasteboard(name: .init("dev.bunchofkeys.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await store.refresh()
        store.selectedVaultId = vaultId
        let unlocked = await store.authenticate(password: "synthetic-test-password")
        precondition(unlocked && store.vault != nil)
        let originalEntry = store.vault!.node(entryId)!
        let originalTags = originalEntry.tags
        store.selection = entryId; store.tagFilter = [.yellow]
        precondition(store.selectedNode == nil && store.destination == nil, "Hidden rows must not remain action targets while filtering")
        store.clearFilters()
        precondition(store.selectedNode?.id == entryId, "Clearing filters restores the saved selection")
        store.selection = nil
        let contextGroup = store.vault!.nodes.first { $0.isGroup && !($0.children ?? []).isEmpty }!
        let contextChild = contextGroup.children!.first!
        let childTagged = await store.setTags([.blue], for: contextChild)
        precondition(childTagged)
        let siblingSaved = await store.mutate("add_entry", ["parent_id": contextGroup.id, "name": "Unmatched native tag-test sibling", "fields": []])
        precondition(siblingSaved)
        let sibling = store.vault!.node(contextGroup.id)!.children!.last!.id
        store.selection = contextGroup.id; store.tagFilter = [.blue]
        let filteredGroup = store.filteredNodes.compactMap { $0.find(contextGroup.id) }.first!
        precondition(filteredGroup.find(sibling) == nil, "Tag filtering must prune unmatched siblings")
        precondition(store.selectedNode == store.vault!.node(contextGroup.id) && store.selectedNode!.find(sibling) != nil, "A visible row must resolve to its complete vault node for actions and editing")
        store.clearFilters(); store.selection = nil
        let childRestored = await store.setTags(contextChild.tags, for: contextChild)
        precondition(childRestored)
        let siblingRemoved = await store.mutate("delete_node", ["node_id": sibling])
        precondition(siblingRemoved)
        store.search = originalEntry.name
        store.tagFilter = [.purple]
        precondition(store.isFiltering && store.filteredNodes.contains { $0.find(entryId) != nil })
        store.clearFilters()
        precondition(!store.isFiltering && store.search.isEmpty && store.tagFilter.isEmpty)
        let tagged = await store.setTags(originalTags + [.red], for: originalEntry)
        precondition(tagged && store.vault!.node(entryId)!.tags.contains(.red))
        store.toggleTag(.red, for: originalEntry)
        for _ in 0..<100 {
            if store.vault?.node(entryId)?.tags.contains(.red) == false { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(Set(store.vault!.node(entryId)!.tags) == Set(originalTags), "Tag toggles must use the current node even when a menu captured an older node")
        let savedSecret = try await store.fieldString("copy_field", entry: entryId, field: fieldId)
        precondition(savedSecret == "synthetic-secret", "Tag edits must preserve encrypted field values")
        store.copy(entry: entryId, field: fieldId)
        for _ in 0..<100 {
            if board.string(forType: .string) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(board.string(forType: .string) == "synthetic-secret", "Copy did not populate the private test pasteboard: \(store.error ?? "no service error")")
        board.clearContents(); board.setString("other-application", forType: .string)
        store.clearClipboard()
        precondition(board.string(forType: .string) == "other-application", "Do not clear someone else's clipboard write")
        board.clearContents()
        store.copy(entry: entryId, field: fieldId)
        for _ in 0..<100 {
            if board.string(forType: .string) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(board.string(forType: .string) == "synthetic-secret", "Second copy did not populate the private test pasteboard: \(store.error ?? "no service error")")
        store.reveal(entry: entryId, field: fieldId)
        store.search = "Renamed"; store.tagFilter = [.blue]
        store.edit(store.vault!.node(entryId)!)
        precondition(!store.isFiltering && store.editor != nil, "Editing must reveal the complete unfiltered item")
        let whileEditing = await store.setTags([], for: originalEntry)
        precondition(!whileEditing && Set(store.vault!.node(entryId)!.tags) == Set(originalTags), "Do not change tags behind an unsaved editor")
        store.search = "session-search"; store.tagFilter = [.red]
        store.lock()
        precondition(store.vault == nil && store.editor == nil && store.revealed.isEmpty)
        precondition(store.tagFilter.isEmpty && store.search.isEmpty && !store.isFiltering, "Lock clears temporary search and tag filters")
        precondition(board.string(forType: .string) == nil, "Lock clears owned clipboard data immediately")
        try await Task.sleep(for: .milliseconds(100))
        precondition(store.vault == nil && store.revealed.isEmpty, "Late reveal must not restore secrets after lock")
        store.search = "old-session"; store.tagFilter = [.red]
        let otherCreated = await store.authenticate(name: "Tag Filter Session Test", password: "synthetic-other-password")
        precondition(otherCreated && store.vault!.id != vaultId && !store.isFiltering, "A new vault must not inherit another vault's filters")
        store.search = "other-vault"; store.tagFilter = [.green]
        store.selectedVaultId = vaultId
        let originalUnlocked = await store.authenticate(password: "synthetic-test-password")
        precondition(originalUnlocked && store.vault!.id == vaultId && !store.isFiltering, "Switching vaults clears temporary search and tag filters")
        precondition(Set(store.vault!.node(entryId)!.tags) == Set(originalTags))
        await store.shutdown()
        print("Native store passed: tag editing, filter cleanup, clipboard ownership, lock cleanup, and late-response protection.")
    }
}
