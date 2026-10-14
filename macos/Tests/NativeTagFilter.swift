import AppKit
import SwiftUI

// Activation belongs to WindowServer and cannot reliably be requested by a
// command-line test process. Only that external state is controlled here; key
// events, local monitors and first responders use the actual AppKit pipeline.
// Real app activation and popover presentation are also verified manually.
@MainActor private final class TagKeyboardWindow: NSWindow {
    var activeForTest = true
    override var isKeyWindow: Bool { activeForTest }
}
@MainActor private final class TagKeyboardProbe: NSView {
    var receivedKeys: [UInt16] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { receivedKeys.append(event.keyCode) }
}

@MainActor enum NativeTagFilter {
    static func run(executable: URL) async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("dev.keepy.tag-keyboard-test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = AppStore(core: CoreClient(executable: executable), pasteboard: board)
        await store.refresh()
        let created = await store.authenticate(name: "Tag Keyboard Test", password: "synthetic-keyboard-password")
        precondition(created)
        let saved = await store.mutate("add_entry", [
            "name": "Keyboard entry", "tags": TagColor.allCases.map(\.rawValue),
            "fields": [["label": "Account", "kind": "text", "masked": false, "value": "synthetic-keyboard-value"]]
        ])
        precondition(saved)
        let entry = store.vault!.nodes.first!
        let window = TagKeyboardWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 620))
        window.contentView = content
        let search = NSTextField(frame: NSRect(x: 20, y: 570, width: 400, height: 24))
        search.placeholderString = "Search credentials"
        content.addSubview(search)
        let coordinator = VaultOutline.Coordinator(store)
        let scroll = VaultOutline.makeScrollView(coordinator: coordinator)
        scroll.frame = NSRect(x: 0, y: 0, width: 620, height: 540)
        content.addSubview(scroll)
        let outline = coordinator.outline!
        coordinator.update(store.filteredNodes)
        let navigation = TagFilterNavigation()
        var presented = false
        let presentation = Binding<Bool>(get: { presented }, set: { presented = $0 })
        let route = TagFilterKeyboardView(frame: .zero)
        route.configure(store: store, navigation: navigation, presented: presentation, role: .workspace)
        content.addSubview(route)
        let popup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        popup.isReleasedWhenClosed = false
        defer { route.detach(); popup.close(); window.close() }

        func send(_ code: UInt16, _ characters: String, to target: NSWindow, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                        context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: repeatKey, keyCode: code)!
            NSApp.sendEvent(event)
        }
        func waitFor(_ message: String, _ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            preconditionFailure(message)
        }
        func attachPalette() async throws -> TagFilterKeyboardView {
            let palette = TagFilterKeyboardView(frame: NSRect(x: 0, y: 0, width: 260, height: 320))
            palette.configure(store: store, navigation: navigation, presented: presentation, role: .palette)
            popup.contentView = palette
            try await waitFor("Palette did not acquire its native first responder") { popup.firstResponder === palette }
            return palette
        }
        func open(from responder: NSResponder) async throws -> TagFilterKeyboardView {
            window.activeForTest = true
            precondition(window.makeFirstResponder(responder))
            send(48, "\t", to: window, modifiers: .shift)
            precondition(presented, "Shift-Tab must open from the workspace's actual first responder")
            return try await attachPalette()
        }
        func close(_ palette: TagFilterKeyboardView, restoring responder: NSResponder? = nil) async throws {
            send(53, "\u{1b}", to: popup)
            precondition(!presented, "Escape must close the palette")
            if let responder {
                try await waitFor("Escape did not restore the native opener focus") { window.firstResponder === responder }
            } else {
                // AppKit's private field editor additionally needs actual OS
                // activation; its restored typing focus is checked in the app.
                try await Task.sleep(for: .milliseconds(20))
            }
            palette.detach(); popup.contentView = nil
        }
        precondition(window.makeFirstResponder(search))
        let searchResponder = window.firstResponder!
        precondition(searchResponder is NSTextView, "Exercise the actual native search field editor")
        let palette = try await open(from: search)
        send(36, "\r", to: popup)
        precondition(store.tagFilter == [.red], "An empty palette must start at Red")
        send(125, "\u{f701}", to: popup, modifiers: [.function, .numericPad])
        send(36, "\r", to: popup)
        precondition(store.tagFilter == [.red, .orange] && presented, "Return must keep the palette open for multiple colors")
        send(124, "\u{f703}", to: popup, modifiers: [.function, .numericPad])
        send(76, "\u{3}", to: popup)
        precondition(store.tagFilter == [.red, .orange, .yellow])
        send(36, "\r", to: popup, repeatKey: true)
        precondition(store.tagFilter == [.red, .orange, .yellow], "Holding Return must not toggle repeatedly")
        send(123, "\u{f702}", to: popup, modifiers: [.function, .numericPad])
        send(36, "\r", to: popup)
        precondition(store.tagFilter == [.red, .yellow])
        send(126, "\u{f700}", to: popup, modifiers: [.function, .numericPad], repeatKey: true)
        send(126, "\u{f700}", to: popup, modifiers: [.function, .numericPad])
        send(36, "\r", to: popup)
        precondition(store.tagFilter.isEmpty && presented, "Return on Clear must remove all filters and keep the palette open")
        send(36, "\r", to: popup)
        precondition(store.tagFilter == [.red], "Clear must reset the highlighted color to Red")
        send(126, "\u{f700}", to: popup, modifiers: [.function, .numericPad])
        send(36, "\r", to: popup)
        send(48, "\t", to: popup, modifiers: .shift)
        send(36, "\r", to: popup)
        precondition(store.tagFilter == [.gray], "Shift-Tab must wrap to Gray when no filters are selected")
        send(48, "\t", to: popup)
        send(36, "\r", to: popup)
        precondition(store.tagFilter.isEmpty, "Tab must navigate to Clear after Gray")
        try await close(palette)
        store.tagFilter = [.purple, .blue]
        let selectedPalette = try await open(from: search)
        send(36, "\r", to: popup)
        precondition(store.tagFilter == [.purple], "Opening must highlight the first selected color")
        try await close(selectedPalette)

        store.clearFilters(); coordinator.update(store.filteredNodes)
        outline.expandItem(coordinator.boxes[entry.id]!)
        outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let outlinePalette = try await open(from: outline)
        send(36, "\r", to: window)
        precondition(store.tagFilter == [.red], "Workspace-window keys must work before popup focus settles")
        send(76, "\u{3}", to: popup)
        precondition(store.tagFilter.isEmpty && presented)
        let displacedFocus = TagKeyboardProbe(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        content.addSubview(displacedFocus)
        window.makeFirstResponder(displacedFocus)
        try await close(outlinePalette, restoring: outline)
        displacedFocus.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(50))
        precondition(board.string(forType: .string) == nil && store.editor == nil && store.error == nil, "Palette keys must not activate the selected credential")

        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let probe = TagKeyboardProbe(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        other.contentView = probe; other.makeFirstResponder(probe)
        defer { other.close() }
        send(48, "\t", to: other, modifiers: .shift)
        precondition(!presented && store.tagFilter.isEmpty, "The workspace route must not intercept another window's keyboard events")
        window.activeForTest = false
        send(48, "\t", to: window, modifiers: .shift)
        precondition(!presented, "An inactive workspace must ignore Shift-Tab")
        window.activeForTest = true
        let modifiers: [NSEvent.ModifierFlags] = [[], [.shift, .command], [.shift, .control], [.shift, .option]]
        for flags in modifiers {
            window.makeFirstResponder(search)
            send(48, "\t", to: window, modifiers: flags)
            precondition(!presented, "Only exact Shift-Tab may open the palette")
        }
        store.busy = true
        send(48, "\t", to: window, modifiers: .shift)
        precondition(!presented)
        store.busy = false
        let editor = EditorRoute(kind: .entry(entry))
        store.editor = editor
        send(48, "\t", to: window, modifiers: .shift)
        precondition(!presented && store.editor?.id == editor.id, "Editor navigation must remain untouched")
        store.editor = nil
        store.showingKeys = true
        send(48, "\t", to: window, modifiers: .shift)
        precondition(!presented)
        store.showingKeys = false
        store.sshPrompt = (entry.id, entry.fields!.first!.id)
        send(48, "\t", to: window, modifiers: .shift)
        precondition(!presented)
        store.sshPrompt = nil
        store.vault = nil
        send(48, "\t", to: window, modifiers: .shift)
        precondition(!presented, "Locked vault navigation must remain untouched")
        await store.shutdown()
        print("Native tag keyboard passed: AppKit event routing, field-editor and outline focus, arrow/Tab navigation, Return, clear, Escape and context guards.")
    }
}
