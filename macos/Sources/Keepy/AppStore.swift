import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct EditorRoute: Identifiable {
    enum Kind { case entry(VaultNode?), group(VaultNode?), keys, createVault }
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
    @Published var selectedVaultId = ""
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
    var hasPendingEdits: Bool {
        UpdatePolicy.blocksRestart(busy: busy, editor: editor != nil, keys: showingKeys,
                                  prompt: sshPrompt != nil, settings: settingsHaveChanges)
    }
    @Published var deleteTarget: VaultNode?
    @Published var sshPrompt: (entry: String, field: String)?
    let core: CoreClient
    private let pasteboard: NSPasteboard
    init(core: CoreClient = CoreClient(), pasteboard: NSPasteboard = .general) {
        self.core = core; self.pasteboard = pasteboard
    }
    private var epoch = 0
    private var polling = false
    private var lastTouch = Date.distantPast
    private var clipboardChange: Int?
    private var clipboardTask: Task<Void, Never>?
    private var startupRegistrationSynchronized = false
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
        !showingKeys && sshPrompt == nil && deleteTarget == nil && error == nil
    }
    var filteredNodes: [VaultNode] { (vault?.nodes ?? []).compactMap { $0.filtered(search, tags: tagFilter) } }
    func clearFilters() { search = ""; tagFilter.removeAll() }
    var colorScheme: ColorScheme? { settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil }

    func refresh() async {
        guard !polling, !busy, serviceAvailable else { return }
        polling = true; defer { polling = false }
        let generation = epoch
        do {
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
        vault = nil; selection = nil; clearFilters(); revealed.removeAll(); activeSSH.removeAll()
        editor = nil; showingKeys = false; sshPrompt = nil; deleteTarget = nil; notice = nil
        clearClipboard()
    }
    func lock() {
        epoch += 1; clearSession()
        Task { do { _ = try await core.request("lock_vault") } catch { fail(error) } }
    }
    func fail(_ failure: Error) {
        if (failure as? CoreError)?.message.contains("service") == true { epoch += 1; clearSession(); serviceAvailable = false }
        error = failure.localizedDescription; ready = true
    }
    func authenticate(name: String? = nil, password: String) async -> Bool {
        guard !busy, serviceAvailable else { return false }
        busy = true; defer { busy = false }; touch()
        epoch += 1
        let authenticationEditor = editor
        clearSession()
        editor = authenticationEditor
        let generation = epoch
        do {
            let data: Data
            if let name { data = try await core.request("create_vault", ["name": name, "password": password]) }
            else { data = try await core.request("unlock_vault", ["vault_id": selectedVaultId, "password": password]) }
            let result = try CoreClient.decoder.decode(Vault.self, from: data)
            guard epoch == generation else { return false }
            revealed.removeAll(); selection = nil; search = ""; vault = result
            selectedVaultId = result.id
            let bootstrap = try CoreClient.decoder.decode(Bootstrap.self, from: await core.request("bootstrap"))
            vaults = bootstrap.vaults; editor = nil
            return true
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
        } catch { fail(error); return false }
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
        Task {
            do {
                let value = try await fieldString("copy_field", entry: entry, field: field)
                guard generation == epoch, vault != nil else { return }
                clipboardTask?.cancel()
                let pasteboard = self.pasteboard
                pasteboard.clearContents(); pasteboard.setString(value, forType: .string)
                clipboardChange = pasteboard.changeCount; notice = "Copied"
                let seconds = settings.clipboardClearSeconds
                clipboardTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.clearClipboard()
                }
                Task { try? await Task.sleep(for: .seconds(2)); if notice == "Copied" { notice = nil } }
            } catch { fail(error) }
        }
    }
    func clearClipboard() {
        clipboardTask?.cancel(); clipboardTask = nil
        if let clipboardChange, pasteboard.changeCount == clipboardChange { pasteboard.clearContents() }
        clipboardChange = nil
    }
    func openURL(entry: String, field: String) {
        let generation = epoch
        Task {
            do {
                let string = try await fieldString("open_url", entry: entry, field: field)
                guard generation == epoch, let url = URL(string: string), ["https", "http"].contains(url.scheme), url.host != nil else { return }
                if !NSWorkspace.shared.open(url) { throw CoreError(message: "The system browser could not be opened.") }
            } catch { fail(error) }
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
            if epoch == generation { activeSSH.insert(field); sshPrompt = nil }
            return true
        } catch {
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
    func shutdown() async { epoch += 1; clearSession(); _ = try? await core.request("lock_vault"); await core.stop() }
}
