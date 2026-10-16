import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct EditorRoute: Identifiable {
    enum Kind { case entry(VaultNode?), group(VaultNode?), keys, createVault, renameVault(VaultSummary), changeMasterPassword(String), trayTags(String) }
    var id = UUID()
    var kind: Kind
    var parentId: String?
    var insertionIndex: Int?
    var isInline: Bool {
        switch kind { case .entry, .group: return true; default: return false }
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var vaults: [VaultSummary] = []
    @Published var settings = Preferences()
    @Published var vault: Vault?
    @Published var selectedVaultId = "" {
        didSet {
            if oldValue != selectedVaultId {
                if touchIDInProgress { lock() }
                touchIDEnrolled = false; touchIDMessage = nil
            }
        }
    }
    @Published var selection: String?
    @Published var search = ""
    @Published var tagFilter = Set<TagColor>()
    @Published var revealed: [String: String] = [:]
    @Published var activeSSH = Set<String>()
    @Published var busy = false
    @Published var ready = false
    @Published var serviceAvailable = true
    @Published var error: String?
    @Published var notice: String?
    @Published var editor: EditorRoute?
    @Published var showingKeys = false
    @Published var settingsHaveChanges = false
    @Published var showingTouchIDSetup = false
    @Published var touchIDEnrolled = false
    @Published var touchIDUnavailableReason: String?
    @Published var touchIDMessage: String?
    @Published var touchIDInProgress = false
    var hasPendingEdits: Bool {
        UpdatePolicy.blocksRestart(busy: busy, editor: editor != nil, keys: showingKeys,
                                  prompt: sshPrompt != nil || showingTouchIDSetup, settings: settingsHaveChanges)
    }
    @Published var deleteTarget: VaultNode?
    @Published var sshPrompt: (entry: String, field: String)?
    let core: CoreClient
    private let pasteboard: NSPasteboard
    let biometricKeychain: BiometricKeychain
    private let openExternalURL: (URL) -> Bool
    init(core: CoreClient = CoreClient(), pasteboard: NSPasteboard = .general, biometricKeychain: BiometricKeychain? = nil, openExternalURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.core = core; self.pasteboard = pasteboard; self.openExternalURL = openExternalURL
        self.biometricKeychain = biometricKeychain ?? SystemBiometricKeychain()
    }
    private var epoch = 0
    private var polling = false
    private var lastTouch = Date.distantPast
    private var clipboardChange: Int?
    private var clipboardTask: Task<Void, Never>?
    private var startupRegistrationSynchronized = false
    private var pendingLock: Task<Void, Never>?
    var selectedNode: VaultNode? {
        guard let node = vault?.node(selection),
              !isFiltering || filteredNodes.contains(where: { $0.find(node.id) != nil }) else { return nil }
        return node
    }
    var vaultName: String { vaults.first { $0.id == vault?.id }?.name ?? "Vault" }
    var destination: String? {
        guard let node = selectedNode else { return nil }
        return node.isGroup ? node.id : vault?.parent(of: node.id)
    }
    var isFiltering: Bool { !search.isEmpty || !tagFilter.isEmpty }
    var canFilterTags: Bool {
        ready && serviceAvailable && vault != nil && !busy && editor == nil &&
        !showingKeys && !showingTouchIDSetup && sshPrompt == nil && deleteTarget == nil && error == nil
    }
    var filteredNodes: [VaultNode] { (vault?.nodes ?? []).compactMap { $0.filtered(search, tags: tagFilter) } }
    func clearFilters() { search = ""; tagFilter.removeAll() }
    var colorScheme: ColorScheme? { settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil }

    func refresh() async {
        guard !polling, !busy, serviceAvailable else { return }
        polling = true; defer { polling = false }
        let generation = epoch
        do {
            await pendingLock?.value
            let data = try await core.request("bootstrap")
            let result = try CoreClient.decoder.decode(Bootstrap.self, from: data)
            guard generation == epoch else { return }
            vaults = result.vaults; settings = result.settings
            if !startupRegistrationSynchronized {
                startupRegistrationSynchronized = true
                synchronizeStartupRegistration(for: result.settings)
            }
            if vault != result.current {
                if result.current == nil { clearSession() }
                else { vault = result.current }
            }
            activeSSH = Set(result.activeSsh.map { $0.fieldId })
            if selectedVaultId.isEmpty { selectedVaultId = vaults.first?.id ?? "" }
            ready = true
        } catch { fail(error) }
    }
    private func synchronizeStartupRegistration(for preferences: Preferences) {
        guard preferences.autostart,
              ProcessInfo.processInfo.environment["KEEPY_DATA_DIR"] == nil,
              Bundle.main.bundleIdentifier == "dev.keepy.desktop",
              SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
    }
    func touch() {
        guard serviceAvailable, Date().timeIntervalSince(lastTouch) > 1 else { return }
        lastTouch = Date()
        Task { _ = try? await core.request("touch") }
    }
    func clearSession() {
        biometricKeychain.cancel(); showingTouchIDSetup = false
        vault = nil; selection = nil; clearFilters(); revealed.removeAll(); activeSSH.removeAll()
        editor = nil; showingKeys = false; sshPrompt = nil; deleteTarget = nil; notice = nil
        clearClipboard()
    }
    func lock() {
        epoch += 1; clearSession()
        let previous = pendingLock
        pendingLock = Task {
            await previous?.value
            do { _ = try await core.request("lock_vault") } catch { fail(error) }
        }
    }
    func fail(_ failure: Error) {
        if (failure as? CoreError)?.message.contains("service") == true { epoch += 1; clearSession(); serviceAvailable = false }
        error = failure.localizedDescription; ready = true
    }
    func authenticate(name: String? = nil, password: String) async -> Bool {
        guard !busy, serviceAvailable else { return false }
        touchIDMessage = nil
        busy = true; defer { busy = false }; touch()
        epoch += 1
        let authenticationEditor = editor
        clearSession()
        editor = authenticationEditor
        let generation = epoch
        do {
            await pendingLock?.value
            guard generation == epoch else { return false }
            let data: Data
            if let name { data = try await core.request("create_vault", ["name": name, "password": password]) }
            else { data = try await core.request("unlock_vault", ["vault_id": selectedVaultId, "password": password]) }
            let result = try CoreClient.decoder.decode(Vault.self, from: data)
            guard epoch == generation else { return false }
            revealed.removeAll(); selection = nil; search = ""; vault = result
            selectedVaultId = result.id
            let bootstrap = try CoreClient.decoder.decode(Bootstrap.self, from: await core.request("bootstrap"))
            guard epoch == generation, vault?.id == result.id else { return false }
            vaults = bootstrap.vaults; editor = nil
            await refreshTouchID()
            return epoch == generation && vault?.id == result.id
        } catch { fail(error); return false }
    }
    @discardableResult func mutate(_ command: String, _ args: [String: Any]) async -> Bool {
        guard !busy, serviceAvailable else { return false }
        busy = true; defer { busy = false }; touch()
        let generation = epoch
        do {
            let result = try CoreClient.decoder.decode(Vault.self, from: await core.request(command, args))
            guard generation == epoch else { return false }
            vault = result; revealed.removeAll()
            if let selection, result.node(selection) == nil { self.selection = nil }
            return true
        } catch {
            guard generation == epoch else { return false }
            fail(error); return false
        }
    }
    func addEntry() { guard vault != nil, !busy, editor == nil else { return }; clearFilters(); editor = EditorRoute(kind: .entry(nil), parentId: destination) }
    func addGroup() { guard vault != nil, !busy, editor == nil else { return }; clearFilters(); editor = EditorRoute(kind: .group(nil), parentId: destination) }
    func edit(_ node: VaultNode) {
        guard let current = vault?.node(node.id), !busy, editor == nil else { return }
        clearFilters(); editor = EditorRoute(kind: current.isGroup ? .group(current) : .entry(current), parentId: vault?.parent(of: current.id))
    }
    @discardableResult func setTags(_ tags: [TagColor], for node: VaultNode) async -> Bool {
        guard vault?.node(node.id) != nil, editor == nil else { return false }
        return await mutate("set_node_tags", ["node_id": node.id, "tags": TagColor.allCases.filter { tags.contains($0) }.map(\.rawValue)])
    }
    func toggleTag(_ tag: TagColor, for node: VaultNode) {
        guard let current = vault?.node(node.id), !busy, editor == nil else { return }
        var tags = Set(current.tags)
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
        Task { await setTags(TagColor.allCases.filter { tags.contains($0) }, for: current) }
    }
    @discardableResult func setFieldTags(_ tags: [TagColor], entry: String, field: String) async -> Bool {
        guard canManageVault, vault?.node(entry)?.fields?.contains(where: { $0.id == field }) == true else { return false }
        return await mutate("set_field_tags", ["entry_id": entry, "field_id": field, "tags": TagColor.allCases.filter { tags.contains($0) }.map(\.rawValue)])
    }
    func toggleFieldTag(_ tag: TagColor, entry: String, field: String) {
        guard canManageVault, let current = vault?.node(entry)?.fields?.first(where: { $0.id == field }) else { return }
        var tags = Set(current.tags)
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
        Task { await setFieldTags(TagColor.allCases.filter { tags.contains($0) }, entry: entry, field: field) }
    }
    func selectCreatedNode(parent: String?, index: Int?) {
        let children = parent.flatMap { vault?.node($0)?.children } ?? vault?.nodes ?? []
        if let index, children.indices.contains(index) { selection = children[index].id }
        else { selection = children.last?.id }
    }
    func move(_ id: String, parent: String?, index: Int) {
        Task { await mutate("move_node", ["node_id": id, "parent_id": parent as Any? ?? NSNull(), "index": index]) }
    }
    func moveField(_ id: String, entry: String, index: Int) {
        Task { await mutate("move_field", ["entry_id": entry, "field_id": id, "index": index]) }
    }
    func fieldString(_ command: String, entry: String, field: String) async throws -> String {
        let data = try await core.request(command, ["entry_id": entry, "field_id": field])
        return try JSONDecoder().decode(String.self, from: data)
    }
    func reveal(entry: String, field: String) {
        if revealed[field] != nil { revealed[field] = nil; return }
        let generation = epoch
        Task {
            do {
                let value = try await fieldString("reveal_field", entry: entry, field: field)
                if generation == epoch, vault != nil { revealed[field] = value }
            } catch { fail(error) }
        }
    }
    func copy(entry: String, field: String) {
        let generation = epoch
        Task { if generation == epoch { _ = await copyCredential(entry: entry, field: field) } }
    }
    private func copyCredential(entry: String, field: String) async -> Bool {
        let generation = epoch
        do {
            let value = try await fieldString("copy_field", entry: entry, field: field)
            guard generation == epoch, vault != nil else { return false }
            clipboardTask?.cancel()
            let pasteboard = self.pasteboard
            pasteboard.clearContents(); pasteboard.setString(value, forType: .string)
            clipboardChange = pasteboard.changeCount; notice = "Copied"
            let seconds = settings.clipboardClearSeconds
            clipboardTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                self?.clearClipboard()
            }
            Task { try? await Task.sleep(for: .seconds(2)); if generation == epoch, notice == "Copied" { notice = nil } }
            return true
        } catch {
            guard generation == epoch else { return false }
            fail(error); return false
        }
    }
    func clearClipboard() {
        clipboardTask?.cancel(); clipboardTask = nil
        if let clipboardChange, pasteboard.changeCount == clipboardChange { pasteboard.clearContents() }
        clipboardChange = nil
    }
    func openURL(entry: String, field: String) {
        let generation = epoch
        Task { if generation == epoch { _ = await openCredentialURL(entry: entry, field: field) } }
    }
    private func openCredentialURL(entry: String, field: String) async -> Bool {
        let generation = epoch
        do {
            let string = try await fieldString("open_url", entry: entry, field: field)
            guard generation == epoch, vault != nil, let url = URL(string: string), ["https", "http"].contains(url.scheme), url.host != nil else { return false }
            if !openExternalURL(url) { throw CoreError(message: "The system browser could not be opened.") }
            return true
        } catch {
            guard generation == epoch else { return false }
            fail(error); return false
        }
    }
    @discardableResult func performFieldAction(entry: String, field: String) async -> Bool {
        guard canManageVault, error == nil, let current = vault?.node(entry)?.fields?.first(where: { $0.id == field }) else { return false }
        touch()
        switch current.action {
        case .copy: return await copyCredential(entry: entry, field: field)
        case .openURL: return await openCredentialURL(entry: entry, field: field)
        case .connectSSH: return await connect(entry: entry, field: field)
        }
    }
    func connect(entry: String, field: String, passphrase: String? = nil) async -> Bool {
        guard !activeSSH.contains(field) else { return false }
        activeSSH.insert(field)
        let generation = epoch
        do {
            var args: [String: Any] = ["entry_id": entry, "field_id": field]
            if let passphrase { args["passphrase"] = passphrase }
            _ = try await core.request("connect_ssh", args)
            guard epoch == generation, vault != nil else { return false }
            activeSSH.insert(field); sshPrompt = nil
            return true
        } catch {
            guard epoch == generation, vault != nil else { return false }
            activeSSH.remove(field)
            if error.localizedDescription == "SSH key passphrase is required" { sshPrompt = (entry, field) }
            else { fail(error) }
            return false
        }
    }
    func importYAML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml")!, UTType(filenameExtension: "yml")!]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Import entries and groups into the unlocked vault."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 64 * 1024 * 1024 else { throw CoreError(message: "The import file is too large.") }
                    let source = try String(contentsOf: url, encoding: .utf8)
                    await self?.mutate("import_yaml_file", ["source": source])
                } catch { self?.fail(error) }
            }
        }
    }
    func saveSettings(_ preferences: Preferences) async -> Bool {
        guard serviceAvailable else { return false }
        let previous = settings
        do {
            if preferences.autostart != previous.autostart {
                if preferences.autostart { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            }
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            let payload = try JSONSerialization.jsonObject(with: encoder.encode(preferences))
            do { _ = try await core.request("update_settings", ["settings": payload]) }
            catch {
                if preferences.autostart != previous.autostart {
                    if previous.autostart { try? SMAppService.mainApp.register() }
                    else { try? await SMAppService.mainApp.unregister() }
                }
                throw error
            }
            settings = preferences; return true
        } catch { fail(error); return false }
    }
    func shutdown() async { epoch += 1; clearSession(); await pendingLock?.value; _ = try? await core.request("lock_vault"); await core.stop() }

    var touchIDVaultID: String { vault?.id ?? selectedVaultId }
    var touchIDHelp: String { touchIDUnavailableReason ?? "Manage Touch ID unlocking for this vault on this Mac." }
    var canManageTouchID: Bool {
        vault != nil && ready && serviceAvailable && !busy && editor == nil && !showingKeys &&
        sshPrompt == nil && deleteTarget == nil && !settingsHaveChanges
    }

    func refreshTouchID() async {
        let id = touchIDVaultID, generation = epoch
        guard !id.isEmpty, serviceAvailable, !touchIDInProgress else { return }
        touchIDUnavailableReason = biometricKeychain.unavailableReason
        do {
            let saved = try biometricKeychain.binding(vaultID: id)
            guard let saved else { touchIDEnrolled = false; return }
            let current = try JSONDecoder().decode(String.self, from: await core.request("biometric_binding", ["vault_id": id]))
            guard generation == epoch, touchIDVaultID == id, !touchIDInProgress else { return }
            if saved == current { touchIDEnrolled = true }
            else {
                try biometricKeychain.remove(vaultID: id)
                touchIDEnrolled = false
                touchIDMessage = "The vault's password protection changed. Unlock with the master password and set up Touch ID again."
            }
        } catch {
            guard generation == epoch, touchIDVaultID == id, !touchIDInProgress else { return }
            touchIDUnavailableReason = error.localizedDescription
            touchIDMessage = error.localizedDescription
            // Allow removal of an inaccessible enrollment from the unlocked vault.
            touchIDEnrolled = true
        }
    }

    func manageTouchID() {
        guard canManageTouchID else { return }
        touchIDMessage = nil; showingTouchIDSetup = true
        Task { await refreshTouchID() }
    }

    func cancelTouchIDSetup() {
        epoch += 1; biometricKeychain.cancel(); showingTouchIDSetup = false
    }

    func disableTouchID() {
        guard canManageTouchID, let id = vault?.id else { return }
        epoch += 1
        do {
            try biometricKeychain.remove(vaultID: id)
            touchIDEnrolled = false; touchIDMessage = "Touch ID disabled for this vault."
            touchIDUnavailableReason = biometricKeychain.unavailableReason
        } catch { touchIDMessage = error.localizedDescription }
    }

    func enableTouchID(password: String) async {
        guard canManageTouchID, let id = vault?.id, !touchIDEnrolled else { return }
        epoch += 1
        busy = true; touchIDInProgress = true; touchIDMessage = nil; touch()
        defer { busy = false; touchIDInProgress = false }
        let generation = epoch
        var saved = false
        do {
            var credential = try await core.request("enroll_biometric", ["vault_id": id, "password": password])
            defer { credential.resetBytes(in: 0..<credential.count) }
            guard generation == epoch, vault?.id == id else { return }
            guard credential.count <= 4096 else { throw TouchIDError.missing }
            struct Identity: Decodable { var vaultId: String; var binding: String }
            let identity = try CoreClient.decoder.decode(Identity.self, from: credential)
            guard identity.vaultId == id else { throw TouchIDError.missing }
            try await biometricKeychain.enroll(credential, vaultID: id, binding: identity.binding, reason: "Enable Touch ID for \(vaultName)")
            saved = true
            guard generation == epoch, vault?.id == id, showingTouchIDSetup else {
                try biometricKeychain.remove(vaultID: id); return
            }
            // Catch backend idle locking during a long native authentication.
            let state = try CoreClient.decoder.decode(Bootstrap.self, from: await core.request("bootstrap"))
            guard generation == epoch, state.current?.id == id else {
                try biometricKeychain.remove(vaultID: id); clearSession(); return
            }
            touchIDEnrolled = true; touchIDUnavailableReason = nil; touchIDMessage = "Touch ID enabled for this vault."
        } catch {
            if saved { try? biometricKeychain.remove(vaultID: id) }
            guard generation == epoch else { return }
            touchIDMessage = error.localizedDescription
        }
    }

    func unlockWithTouchID() async {
        guard !busy, serviceAvailable, vault == nil, touchIDEnrolled,
              touchIDUnavailableReason == nil, !selectedVaultId.isEmpty else { return }
        let id = selectedVaultId
        epoch += 1; clearSession()
        let generation = epoch
        busy = true; touchIDInProgress = true; touchIDMessage = nil; error = nil
        defer { busy = false; touchIDInProgress = false }
        do {
            await pendingLock?.value
            guard generation == epoch, selectedVaultId == id else { return }
            let ticket = try JSONDecoder().decode(String.self, from: await core.request("begin_biometric_unlock", ["vault_id": id]))
            guard generation == epoch, selectedVaultId == id else { return }
            let name = vaults.first { $0.id == id }?.name ?? "vault"
            var credential = try await biometricKeychain.retrieve(vaultID: id, reason: "Unlock \(name) in Keepy")
            defer { credential.resetBytes(in: 0..<credential.count) }
            guard generation == epoch, selectedVaultId == id else { return }
            let data = try await core.unlockBiometric(vaultID: id, ticket: ticket, credential: credential)
            let result = try CoreClient.decoder.decode(Vault.self, from: data)
            guard generation == epoch, selectedVaultId == id, result.id == id else { return }
            vault = result; selection = nil; revealed.removeAll(); clearFilters()
        } catch {
            guard generation == epoch, selectedVaultId == id else { return }
            _ = try? await core.request("lock_vault")
            touchIDMessage = error.localizedDescription
            if case TouchIDError.missing = error {
                try? biometricKeychain.remove(vaultID: id); touchIDEnrolled = false
            } else if error.localizedDescription.hasPrefix("Touch ID enrollment is no longer valid") {
                try? biometricKeychain.remove(vaultID: id); touchIDEnrolled = false
            }
        }
    }
}

extension AppStore {
    var canManageVault: Bool {
        canManageTouchID && !showingTouchIDSetup
    }
    func manageVault(password: Bool) {
        guard canManageVault, let id = vault?.id else { return }
        error = nil; notice = nil
        editor = EditorRoute(kind: password ? .changeMasterPassword(id) : .renameVault(VaultSummary(id: id, name: vaultName)))
    }
    func vaultNameError(_ name: String, excluding id: String? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a vault name." }
        if name.unicodeScalars.count > 80 || name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Use at most 80 characters without control characters."
        }
        if vaults.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) {
            return "A vault with this name already exists."
        }
        return nil
    }
    private func canSubmitVaultManagement(_ id: String, password: Bool) -> Bool {
        guard vault?.id == id, serviceAvailable, !busy, !showingKeys, !showingTouchIDSetup,
              !settingsHaveChanges, sshPrompt == nil, deleteTarget == nil else { return false }
        guard let editor else { return true }
        switch editor.kind {
        case .renameVault(let target): return !password && target.id == id
        case .changeMasterPassword(let target): return password && target == id
        default: return false
        }
    }
    func renameVault(id: String, name: String) async -> Bool {
        guard canSubmitVaultManagement(id, password: false) else { return false }
        if let validation = vaultNameError(name, excluding: id) { error = validation; return false }
        let generation = epoch
        busy = true; error = nil; touch()
        defer { busy = false }
        do {
            let summary = try CoreClient.decoder.decode(VaultSummary.self, from: await core.request("rename_vault", ["vault_id": id, "name": name]))
            guard generation == epoch, vault?.id == id, summary.id == id else { return false }
            vaults = vaults.map { $0.id == id ? summary : $0 }
            editor = nil; notice = "Vault renamed."
            return true
        } catch {
            guard generation == epoch, vault?.id == id else { return false }
            fail(error); return false
        }
    }
    func changeMasterPassword(id: String, current: String, new: String, confirmation: String) async -> Bool {
        guard canSubmitVaultManagement(id, password: true) else { return false }
        if let validation = PasswordChangeValidation.error(current: current, new: new, confirmation: confirmation) {
            error = validation; return false
        }
        let generation = epoch
        busy = true; error = nil; touch()
        defer { busy = false }
        do {
            _ = try await core.request("change_master_password", ["vault_id": id, "current_password": current, "new_password": new, "confirmation": confirmation])
            guard generation == epoch, vault?.id == id else { return false }
            // The service already locked after persisting the new envelope.
            // Clear all native session state and invalidate local Touch ID too.
            let hadTouchID = touchIDEnrolled
            epoch += 1; clearSession()
            selectedVaultId = id; touchIDEnrolled = false
            if hadTouchID {
                do { try biometricKeychain.remove(vaultID: id) }
                catch { touchIDMessage = "The password changed. Set up Touch ID again after unlocking with the new password." }
            }
            notice = "Master password changed. Unlock with your new password."
            return true
        } catch {
            guard generation == epoch, vault?.id == id else { return false }
            fail(error); return false
        }
    }
}
