import AppKit
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, overview, tagNames, tray, sshKeys, touchID, password
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .overview: return "Vault Details"
        case .tagNames: return "Tag Names"
        case .tray: return "Tray Tags"
        case .sshKeys: return "SSH Keys"
        case .touchID: return "Touch ID"
        case .password: return "Master Password"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .overview: return "externaldrive"
        case .tagNames: return "tag"
        case .tray: return "menubar.rectangle"
        case .sshKeys: return "key.horizontal"
        case .touchID: return "touchid"
        case .password: return "lock.rotation"
        }
    }
}

extension AppStore {
    var settingsPages: [SettingsDestination] { vault == nil ? [.general] : SettingsDestination.allCases }
    var canEditVaultSettings: Bool {
        vault != nil && serviceAvailable && !busy && sshPrompt == nil && deleteTarget == nil &&
        (editor == nil || settingsDestination == .sshKeys)
    }
    func openVaultSettings(_ page: SettingsDestination) {
        guard vault != nil, !busy, serviceAvailable,
              editor == nil || page == .sshKeys,
              sshPrompt == nil, deleteTarget == nil else { return }
        settingsRequest = page
        openSettingsWindow?()
    }
    @discardableResult func selectSettingsPage(_ page: SettingsDestination, discard: Bool = false) -> Bool {
        guard settingsPages.contains(page), !busy, !settingsSaving, !touchIDInProgress else { return false }
        guard page != settingsDestination else { settingsRequest = nil; return true }
        guard discard || (!settingsHaveChanges && !vaultSettingsHaveChanges) else { return false }
        if showingTouchIDSetup { cancelTouchIDSetup() }
        showingKeys = false; vaultSettingsHaveChanges = false; settingsHaveChanges = false
        error = nil; notice = nil; settingsDestination = page; settingsRequest = nil
        settingsResetID = UUID()
        return true
    }
    func resetSettingsDraft() {
        vaultSettingsHaveChanges = false; settingsHaveChanges = false; error = nil
        settingsResetID = UUID()
    }
}

struct SettingsAccessBridge: View {
    let store: AppStore
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            let action = openSettings
            store.openSettingsWindow = { action() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @ViewState private var pendingPage: SettingsDestination?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                destination(.general)
                if store.vault != nil {
                    Divider().padding(.vertical, 8)
                    Text("Current Vault").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(store.vaultName).font(.headline).lineLimit(2).help(store.vaultName).padding(.bottom, 8)
                    ForEach(SettingsDestination.allCases.filter { $0 != .general }) { destination($0) }
                }
                Spacer()
            }.padding(14).frame(width: 190).frame(maxHeight: .infinity)
                .background(.primary.opacity(0.035))
            Divider()
            Group {
                if !store.settingsPresented { Color.clear }
                else if store.settingsDestination == .general { GeneralSettingsView() }
                else if let vault = store.vault {
                    ScrollView {
                        VStack(alignment: .leading) {
                            if store.editor != nil && store.settingsDestination != .sshKeys {
                                Text("Finish the open entry or group editor to change vault settings.").foregroundStyle(.secondary).padding(24)
                            } else {
                                vaultPage(vault)
                                    .disabled(!store.canEditVaultSettings && !store.touchIDInProgress)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }.id("\(vault.id):\(store.settingsDestination.rawValue):\(store.settingsResetID)")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 760, height: 640)
            .background(SettingsWindowGuard(store: store))
            .onAppear {
                store.settingsPresented = true
                if let page = store.settingsRequest { request(page) }
            }
            .onChange(of: store.settingsRequest) { _, page in if let page { request(page) } }
            .onChange(of: store.vault?.id) { _, _ in pendingPage = nil }
            .confirmationDialog("Discard unsaved settings?", isPresented: Binding(get: { pendingPage != nil }, set: {
                if !$0 { pendingPage = nil; store.settingsRequest = nil }
            }), titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    if let page = pendingPage { _ = store.selectSettingsPage(page, discard: true) }
                    pendingPage = nil
                }
                Button("Keep Editing", role: .cancel) { pendingPage = nil; store.settingsRequest = nil }
            }
    }
    private func destination(_ page: SettingsDestination) -> some View {
        Button { request(page) } label: {
            Label(page.title, systemImage: page.symbol).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 8).contentShape(Rectangle())
                .background(store.settingsDestination == page ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityValue(store.settingsDestination == page ? "Selected" : "Not selected")
            .disabled(store.busy || store.settingsSaving || store.touchIDInProgress)
    }
    private func request(_ page: SettingsDestination) {
        if store.settingsPages.contains(page), !store.selectSettingsPage(page), !store.busy, !store.settingsSaving, !store.touchIDInProgress { pendingPage = page }
    }
    @ViewBuilder private func vaultPage(_ vault: Vault) -> some View {
        switch store.settingsDestination {
        case .general: EmptyView()
        case .overview: RenameVaultEditor(vault: VaultSummary(id: vault.id, name: store.vaultName))
        case .tagNames: TagNamesEditor(vaultID: vault.id)
        case .tray: TrayTagsEditor(vaultID: vault.id)
        case .sshKeys: SSHKeysEditor(vaultID: vault.id)
        case .touchID: TouchIDSettingsView()
        case .password: ChangeMasterPasswordEditor(vaultID: vault.id)
        }
    }
}

// Keep SwiftUI's window delegate for scene lifecycle, forwarding methods this
// proxy does not handle. Closing Settings must protect unsaved drafts too.
struct SettingsWindowGuard: NSViewRepresentable {
    let store: AppStore
    func makeNSView(context: Context) -> SettingsGuardView { SettingsGuardView(store: store) }
    func updateNSView(_ view: SettingsGuardView, context: Context) {}
}
@MainActor final class SettingsGuardView: NSView {
    let guardDelegate: SettingsCloseDelegate
    init(store: AppStore) { guardDelegate = SettingsCloseDelegate(store: store); super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.delegate !== guardDelegate else { return }
        guardDelegate.previous = window.delegate; window.delegate = guardDelegate
    }
}
@MainActor final class SettingsCloseDelegate: NSObject, NSWindowDelegate {
    let store: AppStore
    weak var previous: NSWindowDelegate?
    init(store: AppStore) { self.store = store }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || previous?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
    func windowDidBecomeKey(_ notification: Notification) {
        store.settingsPresented = true
        previous?.windowDidBecomeKey?(notification)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !store.busy, !store.settingsSaving else { NSSound.beep(); return false }
        if store.settingsHaveChanges || store.vaultSettingsHaveChanges {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved settings?"
            alert.informativeText = "Save your changes before closing Settings, or discard this draft."
            alert.addButton(withTitle: "Keep Editing"); alert.addButton(withTitle: "Discard Changes")
            guard alert.runModal() == .alertSecondButtonReturn else { return false }
        }
        guard previous?.windowShouldClose?(sender) ?? true else { return false }
        if store.showingTouchIDSetup { store.cancelTouchIDSetup() }
        store.showingKeys = false; store.settingsPresented = false; store.resetSettingsDraft()
        return true
    }
}

struct SettingsSaveStatus: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if let notice = store.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
    }
}
