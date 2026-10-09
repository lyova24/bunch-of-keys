import SwiftUI
import AppKit

struct GlassSurface: ViewModifier {
    var enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *), enabled, !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            if !store.ready {
                ProgressView("Opening vault service…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.serviceAvailable {
                ContentUnavailableView {
                    Label("Reopen bunch-of-keys", systemImage: "arrow.clockwise")
                } description: { Text("Quit and reopen the application. If another copy is running, close it first.") }
                actions: { Button("Quit") { NSApp.terminate(nil) } }
            } else if store.vault == nil {
                AuthenticationView(creating: store.vaults.isEmpty)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search credentials", text: $store.search).textFieldStyle(.plain)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                    }
                }.padding(10).modifier(GlassSurface(enabled: store.settings.liquidGlass)).padding(.horizontal, 14).padding(.vertical, 10)
                    .disabled(store.editor != nil)
                ZStack {
                    VaultOutline(store: store).id(store.vault?.id)
                    if store.filteredNodes.isEmpty && store.editor?.isInline != true {
                        VStack(spacing: 10) {
                            Image(systemName: store.search.isEmpty ? "key.horizontal" : "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                            Text(store.search.isEmpty ? "Add an entry or group using +" : "No matching entries.").foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }
                Divider()
                HStack {
                    if store.busy { ProgressView().controlSize(.small) }
                    else if let notice = store.notice { Label(notice, systemImage: "checkmark") }
                    else { Text("Local • Encrypted") }
                    Spacer()
                    Text("\(store.vault?.nodes.count ?? 0) items")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .navigationTitle(store.vault == nil ? "bunch-of-keys" : store.vaultName)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu { vaultMenu } label: { Label("Vaults", systemImage: "externaldrive") }
                    .disabled(store.busy || !store.ready || !store.serviceAvailable || store.editor != nil)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if store.vault != nil {
                    Button("Edit", systemImage: "square.and.pencil") { if let node = store.selectedNode { store.edit(node) } }
                        .disabled(store.selectedNode == nil || store.busy || store.editor != nil).help("Edit Selection (⌘E)")
                }
                Menu {
                    if store.vault != nil {
                        Button("New Entry", systemImage: "key.horizontal") { store.addEntry() }
                        Button("New Group", systemImage: "folder.badge.plus") { store.addGroup() }
                        Divider()
                        Button("Import YAML…") { store.importYAML() }
                    }
                    Button("New Vault…") { store.editor = EditorRoute(kind: .createVault) }
                } label: { Label("Add", systemImage: "plus") }
                    .disabled(store.busy || !store.ready || !store.serviceAvailable || store.editor != nil)
                if store.vault != nil {
                    Button("Lock Vault", systemImage: "lock") { store.lock() }.help("Lock Vault (⇧⌘L)")
                }
            }
        }
        .sheet(item: Binding(get: { store.editor?.isInline == false ? store.editor : nil }, set: { if $0 == nil && store.editor?.isInline == false { store.editor = nil } })) { route in EditorView(route: route).environmentObject(store).preferredColorScheme(store.colorScheme) }
        .sheet(isPresented: $store.showingKeys) { SSHKeysEditor().environmentObject(store).preferredColorScheme(store.colorScheme) }
        .sheet(isPresented: Binding(get: { store.sshPrompt != nil }, set: { if !$0 { store.sshPrompt = nil } })) { SSHPassphraseView().environmentObject(store) }
        .alert("bunch-of-keys", isPresented: Binding(get: { store.error != nil && store.editor == nil && store.sshPrompt == nil && !store.showingKeys }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Delete \(store.deleteTarget?.name ?? "item")?", isPresented: Binding(get: { store.deleteTarget != nil }, set: { if !$0 { store.deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let node = store.deleteTarget { Task { await store.mutate("delete_node", ["node_id": node.id]); store.deleteTarget = nil } }
            }
        } message: { Text("This removes the item and all of its contents from the vault.") }
    }
    @ViewBuilder var vaultMenu: some View {
        ForEach(store.vaults) { vault in
            Button(vault.name) { store.lock(); store.selectedVaultId = vault.id }
        }
        if store.vault != nil {
            Divider()
            Button("SSH Keys…") { store.showingKeys = true }
        }
        Divider()
        SettingsLink { Text("Settings…") }
    }
}
struct AuthenticationView: View {
    @EnvironmentObject var store: AppStore
    var creating: Bool
    @State private var name = ""
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var passwordFocused: Bool
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 42, weight: .light)).foregroundStyle(.tint)
            Text(creating ? "Create your first vault" : "Unlock your vault").font(.title2.weight(.semibold))
            VStack(spacing: 12) {
                if creating { TextField("Vault name", text: $name).textFieldStyle(.roundedBorder) }
                else {
                    Picker("Vault", selection: $store.selectedVaultId) {
                        ForEach(store.vaults) { Text($0.name).tag($0.id) }
                    }.labelsHidden().disabled(store.busy)
                }
                SecureField("Master password", text: $password).textFieldStyle(.roundedBorder).focused($passwordFocused)
                if creating {
                    SecureField("Confirm master password", text: $confirmation).textFieldStyle(.roundedBorder)
                    Text("Use at least 8 characters. There is no password recovery.").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { if await store.authenticate(name: creating ? name : nil, password: password) { password = ""; confirmation = "" } }
                } label: {
                    if store.busy { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                    else { Text(creating ? "Create Vault" : "Unlock").frame(maxWidth: .infinity) }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(store.busy || !store.serviceAvailable || (creating ? name.trimmingCharacters(in: .whitespaces).isEmpty || password.count < 8 || password != confirmation : password.isEmpty || store.selectedVaultId.isEmpty))
            }.frame(width: 280)
        }.padding(28).modifier(GlassSurface(enabled: store.settings.liquidGlass)).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { passwordFocused = true }
            .onChange(of: store.selectedVaultId) { _, _ in password = "" }
    }
}
struct InlineEditor: View {
    @ObservedObject var store: AppStore
    let routeId: UUID
    var body: some View {
        if let route = store.editor, route.id == routeId {
            EditorView(route: route).id(route.id).environmentObject(store).preferredColorScheme(store.colorScheme)
        }
    }
}
struct FieldRow: View {
    @ObservedObject var store: AppStore
    var entry: String
    var field: VaultField
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let ssh = field.ssh {
                    Text("\(ssh.user)@\(ssh.address)\(ssh.port.map { ":\($0)" } ?? "")").font(.system(.body, design: .monospaced)).lineLimit(1)
                    Label(ssh.key.name, systemImage: "key").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Button { store.copy(entry: entry, field: field.id) } label: {
                        Text(store.revealed[field.id] ?? field.value ?? "••••••••")
                            .font(.system(.body, design: .monospaced)).multilineTextAlignment(.leading).lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).help("Copy \(field.label)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if field.masked {
                    Button { store.reveal(entry: entry, field: field.id) } label: { Image(systemName: store.revealed[field.id] == nil ? "eye" : "eye.slash") }
                        .help("Reveal or hide \(field.label)").accessibilityLabel("Reveal or hide \(field.label)")
                }
                if field.kind == "url" {
                    Button { store.openURL(entry: entry, field: field.id) } label: { Image(systemName: "arrow.up.right.square") }.help("Open URL").accessibilityLabel("Open URL")
                }
                if field.kind == "ssh" {
                    Button { Task { await store.connect(entry: entry, field: field.id) } } label: { Image(systemName: "terminal") }
                        .disabled(store.activeSSH.contains(field.id)).help(store.activeSSH.contains(field.id) ? "Connection active" : "Connect in Terminal").accessibilityLabel("Connect in Terminal")
                } else {
                    Button { store.copy(entry: entry, field: field.id) } label: { Image(systemName: "doc.on.doc") }.help("Copy \(field.label)").accessibilityLabel("Copy \(field.label)")
                }
            }.buttonStyle(.borderless)
        }.padding(.horizontal, 6).padding(.vertical, 6).accessibilityElement(children: .contain)
    }
}
