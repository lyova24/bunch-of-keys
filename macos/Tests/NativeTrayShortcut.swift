import AppKit
import Carbon
import SwiftUI

@MainActor private final class ShortcutTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor enum NativeTrayShortcut {
    static func run(executable: URL) async throws {
        _ = NSApplication.shared
        let suite = "dev.keepy.shortcut-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TrayShortcutSettings(defaults: defaults)
        defer { settings.stop() }
        precondition(settings.enabled && settings.shortcut == .default)
        precondition(TrayShortcut.default.title == "⌘F8")
        // Deliver a Carbon event through the installed application handler;
        // Registration conflicts are exercised against the real system below.
        func deliver(_ id: EventHotKeyID) {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyReleased),
                                     GetCurrentEventTime(), 0, &event) == noErr)
            defer { ReleaseEvent(event) }
            var id = id
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           MemoryLayout<EventHotKeyID>.size, &id) == noErr)
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
        }
        var activations = 0
        settings.hotKey.action = { activations += 1 }
        let modifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        let first = TrayShortcut(keyCode: UInt32(kVK_F19), modifiers: modifiers, key: "F19")
        let second = TrayShortcut(keyCode: UInt32(kVK_F20), modifiers: modifiers, key: "F20")
        let blocker = GlobalTrayHotKey()
        defer { blocker.stop() }
        precondition(settings.set(enabled: true, shortcut: first))
        deliver(settings.hotKey.eventID)
        try await Task.sleep(for: .milliseconds(30))
        precondition(activations == 1, "A matching Carbon event must reach the registered action")
        let stale = settings.hotKey.eventID
        precondition(blocker.replace(with: first) == eventHotKeyExistsErr, "A registered shortcut must be exclusive")
        precondition(blocker.replace(with: second) == noErr)
        precondition(!settings.set(enabled: true, shortcut: second))
        precondition(settings.shortcut == first && settings.hotKey.shortcut == first && settings.error != nil)
        let persisted = TrayShortcutSettings(defaults: defaults)
        precondition(persisted.shortcut == first && persisted.enabled, "A failed registration must not persist")
        persisted.stop()
        blocker.replace(with: nil)
        precondition(settings.set(enabled: true, shortcut: second))
        deliver(stale)
        deliver(settings.hotKey.eventID)
        try await Task.sleep(for: .milliseconds(30))
        precondition(activations == 2, "Stale events must be ignored and other handlers must not consume current events")
        precondition(blocker.replace(with: first) == noErr, "Replacing must release the old combination")
        blocker.replace(with: nil)
        precondition(settings.set(enabled: false, shortcut: second))
        precondition(settings.hotKey.shortcut == nil)
        precondition(blocker.replace(with: second) == noErr, "Disabling must unregister")
        blocker.replace(with: nil)
        let disabled = TrayShortcutSettings(defaults: defaults)
        precondition(!disabled.enabled && disabled.shortcut == second)
        disabled.stop()
        precondition(settings.set(enabled: true, shortcut: second))

        let window = ShortcutTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                                        styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let button = ShortcutRecorderButton(frame: NSRect(x: 20, y: 20, width: 200, height: 26))
        button.settings = settings; window.contentView!.addSubview(button)
        defer { button.finish(); window.close() }
        func send(_ key: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = []) {
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key)!)
        }
        button.begin()
        precondition(settings.recording && settings.hotKey.shortcut == nil)
        send(0, "a")
        precondition(settings.recording && settings.shortcut == second, "Unmodified typing must not become a global shortcut")
        send(53, "\u{1b}")
        precondition(!settings.recording && settings.hotKey.shortcut == second, "Escape must restore the previous registration")
        button.begin()
        send(UInt16(kVK_F19), "\u{f716}", flags: [.command, .control, .option, .shift])
        precondition(!settings.recording && settings.shortcut == first && settings.hotKey.shortcut == first)
        button.begin()
        precondition(blocker.replace(with: second) == noErr)
        send(UInt16(kVK_F20), "\u{f717}", flags: [.command, .control, .option, .shift])
        precondition(!settings.recording && settings.shortcut == first && settings.hotKey.shortcut == first && settings.error != nil)
        blocker.replace(with: nil)
        button.begin(); button.finish()
        precondition(settings.hotKey.shortcut == first, "Losing focus must restore the shortcut")

        let host = NSHostingView(rootView: ShortcutRecorder(settings: settings))
        window.contentView = host
        func recorder(in view: NSView) -> ShortcutRecorderButton? {
            (view as? ShortcutRecorderButton) ?? view.subviews.lazy.compactMap { recorder(in: $0) }.first
        }
        try await Task.sleep(for: .milliseconds(40))
        let hosted = recorder(in: host)!
        precondition(settings.set(enabled: true, shortcut: second))
        try await Task.sleep(for: .milliseconds(40))
        precondition(hosted.title == second.title, "The recorder must observe preference changes outside its own key handler")
        precondition(settings.set(enabled: true, shortcut: first))
        try await Task.sleep(for: .milliseconds(40))
        precondition(hosted.title == first.title, "Reset must refresh the displayed shortcut")

        let store = AppStore(core: CoreClient(executable: executable))
        let tray = TrayMenuController()
        tray.start(store: store, shortcuts: settings, openWindow: {}, openSettings: {})
        tray.menuNeedsUpdate(tray.menu)
        precondition(tray.menu.items.map(\.title) == ["Vault locked", "Open Keepy", "Lock Vault", "", "Settings…", "Quit Keepy"])
        precondition(!tray.menu.items[2].isEnabled)
        store.vaults = [VaultSummary(id: "test", name: "Shortcut Test Vault")]
        store.vault = Vault(id: "test", sshKeys: [], nodes: [])
        tray.menuNeedsUpdate(tray.menu)
        precondition(tray.menu.items[0].title == "Shortcut Test Vault" && tray.menu.items[2].isEnabled)
        tray.menuWillOpen(tray.menu)
        store.vault = nil
        precondition(tray.menu.items[0].title == "Vault locked" && !tray.menu.items[2].isEnabled, "Auto-lock must update an already open menu")
        tray.menuDidClose(tray.menu)
        tray.menuNeedsUpdate(tray.menu)
        precondition(tray.menu.items[0].title == "Vault locked" && !tray.menu.items[2].isEnabled)
        tray.stop()
        await store.shutdown()
        precondition(blocker.replace(with: first) == noErr, "Shutdown must release the registration")
        blocker.replace(with: nil)
        defaults.set(Data("invalid".utf8), forKey: "trayMenuShortcut")
        let recovered = TrayShortcutSettings(defaults: defaults)
        precondition(recovered.shortcut == .default && recovered.enabled)
        recovered.stop()
        print("Native tray shortcut passed: exclusive registration, conflicts, persistence, disabling, recording, cancellation, cleanup and locked/unlocked menus.")
    }
}
