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
        store.copy(entry: entryId, field: fieldId)
        for _ in 0..<100 {
            if board.string(forType: .string) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(board.string(forType: .string) == "synthetic-secret")
        board.clearContents(); board.setString("other-application", forType: .string)
        store.clearClipboard()
        precondition(board.string(forType: .string) == "other-application", "Do not clear someone else's clipboard write")
        board.clearContents()
        store.copy(entry: entryId, field: fieldId)
        for _ in 0..<100 {
            if board.string(forType: .string) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(board.string(forType: .string) == "synthetic-secret")
        store.reveal(entry: entryId, field: fieldId)
        store.editor = EditorRoute(kind: .entry(store.vault!.node(entryId)))
        store.lock()
        precondition(store.vault == nil && store.editor == nil && store.revealed.isEmpty)
        precondition(board.string(forType: .string) == nil, "Lock clears owned clipboard data immediately")
        try await Task.sleep(for: .milliseconds(100))
        precondition(store.vault == nil && store.revealed.isEmpty, "Late reveal must not restore secrets after lock")
        await store.shutdown()
        print("Native store passed: clipboard ownership, lock cleanup, and late-response protection.")
    }
}
