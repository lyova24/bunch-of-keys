import AppKit

@MainActor private final class OutlineKeyboardWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor enum NativeOutlineKeyboard {
    static func run() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("dev.keepy.initial-keyboard-test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let child = VaultNode(id: "child", name: "Child", type: "entry", fields: [])
        let group = VaultNode(id: "group", name: "Group", type: "group", children: [child])
        let last = VaultNode(id: "last", name: "Last", type: "entry", fields: [])
        func makeStore(_ nodes: [VaultNode]) -> AppStore {
            let store = AppStore(core: CoreClient(executable: URL(fileURLWithPath: "/usr/bin/false")), pasteboard: board)
            store.ready = true
            store.vault = Vault(id: UUID().uuidString, sshKeys: [], nodes: nodes)
            return store
        }
        func send(_ code: UInt16, to window: NSWindow) {
            let characters: [UInt16: String] = [123: "\u{f702}", 124: "\u{f703}", 125: "\u{f701}", 126: "\u{f700}"]
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [.function, .numericPad], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters[code]!,
                charactersIgnoringModifiers: characters[code]!, isARepeat: false, keyCode: code)!
            // Hidden command-line windows cannot become the OS key window.
            // Exercise NSWindow's real responder dispatch once focus is in the
            // tree, and NSApplication's local monitor for neutral responders.
            if window.firstResponder is VaultOutlineView { window.sendEvent(event) }
            else { NSApp.sendEvent(event) }
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(40)) }
        // Recreate the native view for each vault lifetime, as WorkspaceView.id does.
        for _ in 0..<2 {
            let store = makeStore([group, last])
            let coordinator = VaultOutline.Coordinator(store)
            let scroll = VaultOutline.makeScrollView(coordinator: coordinator)
            let outline = coordinator.outline!
            coordinator.update(store.filteredNodes)
            try await settle()
            precondition(!coordinator.didFocus && outline.selectedRow == -1 && store.selection == nil,
                         "A detached outline must not consume its initial focus attempt or select a row")
            let window = OutlineKeyboardWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
            window.contentView = content
            scroll.frame = content.bounds
            content.addSubview(scroll)
            defer { outline.detachKeyboardMonitor(); window.close() }
            try await settle()
            precondition(coordinator.didFocus && window.firstResponder === outline)
            precondition(outline.selectedRow == -1 && store.selection == nil, "Focus must not highlight a row")
            send(125, to: window)
            precondition(store.selection == group.id && outline.selectedRow == 0,
                         "The first Down must select the first row (row: \(outline.selectedRow), selection: \(store.selection ?? "nil"))")
            send(124, to: window)
            precondition(outline.isItemExpanded(coordinator.boxes[group.id]!))
            send(125, to: window)
            precondition(store.selection == child.id, "Subsequent arrows must use native expanded-tree navigation")
            outline.deselectAll(nil)
            send(126, to: window)
            precondition(store.selection == last.id, "The first Up must select the last visible row")
            outline.deselectAll(nil)
            window.makeFirstResponder(window)
            send(125, to: window)
            precondition(window.firstResponder === outline && store.selection == group.id,
                         "A neutral window responder must route the very first arrow to the tree")

            let search = NSTextField(frame: NSRect(x: 0, y: 470, width: 300, height: 24))
            content.addSubview(search)
            window.makeFirstResponder(search)
            let responder = window.firstResponder
            precondition(responder is NSTextView)
            outline.deselectAll(nil)
            coordinator.didFocus = false
            coordinator.update(store.filteredNodes)
            try await settle()
            precondition(window.firstResponder === responder && !coordinator.didFocus,
                         "Refresh must not steal active search field-editor focus")
            send(123, to: window)
            precondition(outline.selectedRow == -1 && window.firstResponder === responder)

            for blocked in 0..<5 {
                window.makeFirstResponder(window)
                store.busy = blocked == 0
                store.showingKeys = blocked == 1
                store.editor = blocked == 2 ? EditorRoute(kind: .group(nil)) : nil
                store.error = blocked == 3 ? "Synthetic error" : nil
                store.vault = blocked == 4 ? nil : Vault(id: "keyboard", sshKeys: [], nodes: [group, last])
                precondition(!coordinator.claimKeyboardFocus(), "Blocked/locked workspace must preserve focus")
            }
            store.busy = false; store.showingKeys = false; store.editor = nil; store.error = nil
            store.vault = Vault(id: "reopened", sshKeys: [], nodes: [])
            coordinator.update([])
            try await settle()
            precondition(outline.selectedRow == -1, "An empty tree must stay unselected")
            send(125, to: window)
            precondition(outline.selectedRow == -1)
            store.vault = Vault(id: "reopened", sshKeys: [], nodes: [last])
            coordinator.update(store.filteredNodes)
            try await settle()
            precondition(outline.selectedRow == -1 && store.selection == nil)
            send(125, to: window)
            precondition(store.selection == last.id)
        }
        print("Native initial keyboard passed: delayed attachment, no initial selection, arrows, expansion, neutral responder routing, search focus, blocked states, empty trees and new vault lifetimes.")
    }
}
