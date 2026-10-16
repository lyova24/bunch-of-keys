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
    private var observations = Set<AnyCancellable>()
    private struct MenuState: Equatable {
        var vaultID: String?
        var name: String
        var groups: [TrayTagGroup]
        var configured: Bool
        var canOpen: Bool
        var canManage: Bool
        var fullNames: Bool
    }
    private var state: MenuState?
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
        store.$vault.sink { [weak self] vault in
            guard let self else { return }
            self.updateIcon(locked: vault == nil)
            if vault == nil {
                if self.tracking { self.menu.cancelTracking() }
                self.render(nil)
            }
        }.store(in: &observations)
        store.objectWillChange.sink { [weak self] _ in
            // Published values are committed after objectWillChange. Read the
            // latest state on the next main turn and skip unchanged menus so
            // background refresh cannot disrupt keyboard navigation.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.render(self.store?.vault)
            }
        }.store(in: &observations)
        shortcuts.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.render(self?.store?.vault) }
        }.store(in: &observations)
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
    func menuNeedsUpdate(_ menu: NSMenu) { render(store?.vault, force: true) }
    private func render(_ vault: Vault?, force: Bool = false) {
        guard let store else { return }
        let next = MenuState(vaultID: vault?.id,
            name: vault == nil ? "Vault locked" : store.vaults.first(where: { $0.id == vault?.id })?.name ?? "Vault",
            groups: vault?.trayTagGroups ?? [], configured: vault?.trayTags.isEmpty == false,
            canOpen: store.canUseTrayCredentials, canManage: store.canManageVault, fullNames: shortcuts?.showFullCredentialNames ?? false)
        guard force || state != next else { return }
        state = next
        menu.removeAllItems()
        add(next.name, enabled: false)
        add("Open Keepy", action: #selector(showWorkspace))
        add("Lock Vault", action: #selector(lock), enabled: vault != nil)
        menu.addItem(.separator())
        if vault != nil {
            add("Tagged Credentials", enabled: false)
            if next.groups.allSatisfy({ $0.credentials.isEmpty }) {
                add(next.configured ? "No credentials match the selected tags." : "Choose tags to show credentials here.", enabled: false)
            }
            for group in next.groups {
                let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                groupItem.image = group.id.menuImage; groupItem.toolTip = group.title
                groupItem.representedObject = group.id
                let submenu = NSMenu(title: group.title); submenu.autoenablesItems = false
                if group.credentials.isEmpty {
                    let empty = NSMenuItem(title: "No credentials match this tag.", action: nil, keyEquivalent: "")
                    empty.isEnabled = false; submenu.addItem(empty)
                }
                for credential in group.credentials {
                    let item = NSMenuItem(title: credential.title(showFullNames: next.fullNames), action: #selector(activateCredential(_:)), keyEquivalent: "")
                    item.target = self; item.representedObject = credential.id; item.isEnabled = next.canOpen
                    item.toolTip = "\(credential.action.title): \(credential.fullTitle)"
                    item.image = NSImage(systemSymbolName: credential.action.symbol, accessibilityDescription: nil)
                    submenu.addItem(item)
                }
                groupItem.submenu = submenu; menu.addItem(groupItem)
            }
            add("Current Vault Settings…", action: #selector(configureVault), enabled: next.canManage)
            menu.addItem(.separator())
        }
        add("Settings…", action: #selector(showSettings))
        add("Quit Keepy", action: #selector(quit), key: "q")
    }
    @objc private func activateCredential(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? CredentialTarget, let store else { return }
        Task {
            await store.activateTrayCredential(target)
            // Copy and URL actions stay in the background. SSH passphrases and
            // actionable errors need the existing main-window UI.
            if store.vault?.id == target.vaultID, store.sshPrompt != nil || store.error != nil { showWorkspace() }
        }
    }
    @objc private func configureVault() {
        guard store?.canManageVault == true else { return }
        store?.openVaultSettings(.overview); showSettings()
    }
    private func add(_ title: String, action: Selector? = nil, key: String = "", enabled: Bool = true) {
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
        shortcuts?.stop(); observations.removeAll(); state = nil
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
