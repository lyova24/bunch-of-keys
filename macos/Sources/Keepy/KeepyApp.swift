import SwiftUI
import AppKit
import CoreServices

@main struct KeepyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()
    @StateObject private var updates = UpdateController()
    @StateObject private var shortcuts = TrayShortcutSettings()
    @StateObject private var tray = TrayMenuController()
    var body: some Scene {
        Window(AppLogo.name, id: "main") {
            WorkspaceView().environmentObject(store).preferredColorScheme(store.colorScheme)
                .modifier(WindowSurface(enabled: store.settings.liquidGlass))
                .background(TrayMenuBridge(controller: tray, store: store, shortcuts: shortcuts))
                .onAppear { delegate.attach(store, updates: updates, tray: tray) }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
            }
            CommandGroup(after: .newItem) {
                Button("New Entry") { store.addEntry() }.keyboardShortcut("n").disabled(store.vault == nil || store.busy || store.editor != nil)
                Button("New Group") { store.addGroup() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(store.vault == nil || store.busy || store.editor != nil)
                Divider()
                Button("Import YAML…") { store.importYAML() }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(store.vault == nil || store.busy || store.editor != nil)
                Button("New Vault…") { store.editor = EditorRoute(kind: .createVault) }.disabled(store.busy || !store.serviceAvailable || store.editor != nil)
            }
            CommandMenu("Vault") {
                Button("Rename Vault…") { store.manageVault(password: false) }.disabled(!store.canManageVault)
                Button("Change Master Password…") { store.manageVault(password: true) }.disabled(!store.canManageVault)
                Divider()
                Button("Lock Vault") { store.lock() }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(store.vault == nil)
                Button("Edit Selection…") { if let node = store.selectedNode { store.edit(node) } }.keyboardShortcut("e").disabled(store.selectedNode == nil || store.busy || store.editor != nil)
                Button("SSH Keys…") { store.showingKeys = true }.disabled(store.vault == nil || store.busy || store.editor != nil)
                Button("Touch ID…") { store.manageTouchID() }.disabled(!store.canManageTouchID).help(store.touchIDHelp)
            }
        }
        Settings {
            SettingsView().environmentObject(store).environmentObject(updates).environmentObject(shortcuts).preferredColorScheme(store.colorScheme)
                .modifier(WindowSurface(enabled: store.settings.liquidGlass))
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: AppStore?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var timer: Timer?
    private var launchedAtLogin = false
    private var tray: TrayMenuController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem || event?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil || ProcessInfo.processInfo.arguments.contains("--hidden")
        if launchedAtLogin { NSApp.hide(nil) }
    }
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["KEEPY_DATA_DIR"] == nil,
              let identifier = Bundle.main.bundleIdentifier else { return }
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }
    func attach(_ store: AppStore, updates: UpdateController, tray: TrayMenuController) {
        guard self.store == nil else { return }
        self.store = store
        self.tray = tray
        updates.start()
        if !UserDefaults.standard.bool(forKey: "compactWorkspaceLayout") {
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else { return }
                window.setContentSize(NSSize(width: 560, height: 620))
                window.center()
                UserDefaults.standard.set(true, forKey: "compactWorkspaceLayout")
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak store] _ in Task { @MainActor in store?.lock() } })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak store] _ in Task { @MainActor in store?.lock() } })
        observers.append(NotificationCenter.default.addObserver(forName: .coreStopped, object: nil, queue: .main) { [weak store] _ in
            Task { @MainActor in store?.clearSession(); store?.serviceAvailable = false; store?.error = "The vault service stopped. Reopen the application." }
        })
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { [weak store] event in
            Task { @MainActor in store?.touch() }; return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak store] _ in Task { @MainActor in await store?.refresh() } }
        Task { await store.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store?.touchIDInProgress == true { store?.lock() }
        if store?.busy == true && store?.touchIDInProgress != true {
            let alert = NSAlert()
            alert.messageText = "Keepy is saving changes"
            alert.informativeText = "Wait for the current operation to finish, then try again."
            alert.runModal()
            return .terminateCancel
        }
        if let store, store.hasPendingEdits && !store.touchIDInProgress {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved changes and quit?"
            alert.informativeText = "An editor or unsaved Settings is open. Choose Keep Editing to save your changes before quitting or restarting for an update."
            alert.addButton(withTitle: "Keep Editing")
            alert.addButton(withTitle: "Discard and Quit")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        timer?.invalidate()
        tray?.stop()
        Task { await store?.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil) }
        return true
    }
}
