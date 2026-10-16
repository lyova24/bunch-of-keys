import AppKit
import Combine
import SwiftUI

/// A public AppKit status item gives mouse and global-keyboard access the same
/// native menu, including arrow-key navigation and Escape dismissal.
@MainActor final class TrayMenuController: NSObject, ObservableObject, NSMenuDelegate {
    private(set) var statusItem: NSStatusItem?
    let menu = NSMenu()
    private weak var store: AppStore?
    private weak var shortcuts: TrayShortcutSettings?
    private var observation: AnyCancellable?
    private var openWindow: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var tracking = false

    func start(store: AppStore, shortcuts: TrayShortcutSettings, openWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        guard statusItem == nil else { return }
        self.store = store; self.shortcuts = shortcuts; self.openWindow = openWindow; self.openSettings = openSettings
        menu.delegate = self; menu.autoenablesItems = false
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "KeepyMenuBar"
        item.menu = menu; statusItem = item
        observation = store.$vault.sink { [weak self] vault in
            guard let self else { return }
            self.updateIcon(locked: vault == nil)
            if self.tracking, self.menu.items.count > 2 {
                self.menu.items[0].title = vault == nil ? "Vault locked" : store.vaults.first(where: { $0.id == vault?.id })?.name ?? "Vault"
                self.menu.items[2].isEnabled = vault != nil
            }
        }
        shortcuts.start { [weak self] in self?.showMenu() }
    }
    private func updateIcon(locked: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = AppLogo.menuBarImage
        button.imagePosition = .imageLeading
        if locked {
            let attachment = NSTextAttachment()
            attachment.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
            attachment.bounds = NSRect(x: 0, y: 0, width: 8, height: 9)
            let lock = NSAttributedString(attachment: attachment)
            let title = NSMutableAttributedString(string: " "); title.append(lock)
            button.attributedTitle = title
        } else { button.title = "" }
        button.setAccessibilityLabel(locked ? "Keepy, vault locked" : "Keepy, vault unlocked")
        button.toolTip = "Keepy"
    }
    func showMenu() {
        guard !tracking else { return }
        statusItem?.button?.performClick(nil)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let store else { return }
        menu.removeAllItems()
        let header = NSMenuItem(title: store.vault == nil ? "Vault locked" : store.vaultName, action: nil, keyEquivalent: "")
        header.isEnabled = false; menu.addItem(header)
        add("Open Keepy", action: #selector(showWorkspace))
        add("Lock Vault", action: #selector(lock), enabled: store.vault != nil)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings))
        add("Quit Keepy", action: #selector(quit), key: "q")
    }
    private func add(_ title: String, action: Selector, key: String = "", enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.isEnabled = enabled; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) { tracking = true }
    func menuDidClose(_ menu: NSMenu) { tracking = false }
    @objc private func showWorkspace() {
        openWindow?(); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func lock() { store?.lock() }
    @objc private func showSettings() {
        openSettings?(); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func stop() {
        shortcuts?.stop(); observation = nil
        menu.cancelTracking()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}

struct TrayMenuBridge: View {
    let controller: TrayMenuController
    let store: AppStore
    let shortcuts: TrayShortcutSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            controller.start(store: store, shortcuts: shortcuts,
                             openWindow: { openWindow(id: "main") }, openSettings: { openSettings() })
        }
    }
}
