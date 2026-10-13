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
    @State private var showingTagFilters = false
    @StateObject private var tagNavigation = TagFilterNavigation()
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
                    Divider().frame(height: 18)
                    Button {
                        if showingTagFilters { showingTagFilters = false }
                        else { tagNavigation.prepare(store); showingTagFilters = true }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.tagFilter.isEmpty ? "tag" : "tag.fill")
                            if !store.tagFilter.isEmpty { Text("\(store.tagFilter.count)").font(.caption.weight(.semibold)) }
                        }.foregroundStyle(store.tagFilter.isEmpty ? Color.secondary : Color.accentColor)
                    }.buttonStyle(.plain)
                        .help("Filter by Tags (⇧Tab)")
                        .accessibilityLabel("Filter by Tags")
                        .accessibilityValue(store.tagFilter.isEmpty ? "All tags" : "\(store.tagFilter.count) selected")
                        .popover(isPresented: $showingTagFilters, arrowEdge: .bottom) {
                            TagFilterPalette(store: store, navigation: tagNavigation)
                                .background(TagFilterKeyboardRoute(store: store, navigation: tagNavigation, presented: $showingTagFilters, role: .palette).frame(width: 0, height: 0))
                        }
                }.padding(10).modifier(GlassSurface(enabled: store.settings.liquidGlass)).padding(.horizontal, 14).padding(.vertical, 10)
                    .disabled(store.editor != nil || store.busy)
                if !store.tagFilter.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(TagColor.allCases.filter { store.tagFilter.contains($0) }) { tag in
                            Circle().fill(tag.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        }
                        Text("Tags: \(TagColor.allCases.filter { store.tagFilter.contains($0) }.map(\.title).joined(separator: ", "))")
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button("Clear") { store.tagFilter.removeAll() }.buttonStyle(.plain).help("Clear Tag Filters")
                            .accessibilityLabel("Clear Tag Filters").disabled(store.editor != nil || store.busy)
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 8)
                }
                ZStack {
                    VaultOutline(store: store).id(store.vault?.id)
                    if store.filteredNodes.isEmpty && store.editor?.isInline != true {
                        VStack(spacing: 10) {
                            Image(systemName: store.isFiltering ? "magnifyingglass" : "key.horizontal").font(.largeTitle).foregroundStyle(.secondary)
                            Text(store.isFiltering ? "No matching items" : "Add an entry or group using +").foregroundStyle(.secondary)
                            if store.isFiltering {
                                Text("Try another search or tag color.").font(.caption).foregroundStyle(.secondary)
                                Button("Clear Filters") { store.clearFilters() }.disabled(store.busy)
                            }
                        }
                    }
                }
                Divider()
                HStack {
                    if store.busy { ProgressView().controlSize(.small) }
                    else if let notice = store.notice { Label(notice, systemImage: "checkmark") }
                    else { Text("Local • Encrypted") }
                    Spacer()
                    Text(store.isFiltering ? "\(itemCount(store.filteredNodes)) of \(itemCount(store.vault?.nodes ?? [])) items" : "\(itemCount(store.vault?.nodes ?? [])) items")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .background(TagFilterKeyboardRoute(store: store, navigation: tagNavigation, presented: $showingTagFilters, role: .workspace).frame(width: 0, height: 0))
        .onChange(of: store.editor?.id) { _, id in if id != nil { showingTagFilters = false } }
        .onChange(of: store.vault?.id) { _, _ in showingTagFilters = false }
        .onChange(of: store.canFilterTags) { _, allowed in if !allowed { showingTagFilters = false } }
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
    private func itemCount(_ nodes: [VaultNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + itemCount($1.children ?? []) }
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
struct TagFilterPalette: View {
    @ObservedObject var store: AppStore
    @ObservedObject var navigation = TagFilterNavigation()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filter by Tags").font(.headline)
            Text("Show items with any selected color.").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(TagColor.allCases) { tag in
                    let selected = store.tagFilter.contains(tag)
                    Button {
                        navigation.activeColor = tag
                        if selected { store.tagFilter.remove(tag) } else { store.tagFilter.insert(tag) }
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(tag.color).overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 0.5)).frame(width: 12, height: 12)
                            Text(tag.title)
                            Spacer()
                            if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint) }
                        }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                            .background(navigation.activeColor == tag ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(navigation.activeColor == tag ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel("\(tag.title) tag filter")
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .onHover { hovering in if hovering { navigation.activeColor = tag } }
                }
            }
            Divider()
            Button("Clear Tag Filters") {
                store.tagFilter.removeAll(); navigation.activeColor = .red
            }.disabled(store.tagFilter.isEmpty)
                .background(navigation.activeColor == nil ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .onHover { hovering in if hovering && !store.tagFilter.isEmpty { navigation.activeColor = nil } }
            Text("↑↓ Select · Return Toggle · Esc Close").font(.caption2).foregroundStyle(.secondary)
        }.padding(14).frame(width: 240).disabled(store.busy || store.editor != nil)
            .onChange(of: store.tagFilter) { _, colors in if colors.isEmpty && navigation.activeColor == nil { navigation.activeColor = .red } }
    }
}

@MainActor final class TagFilterNavigation: ObservableObject {
    // nil represents the Clear Tag Filters action at the end of the palette.
    @Published var activeColor: TagColor? = .red
    weak var workspaceWindow: NSWindow?
    private weak var previousResponder: NSResponder?
    func prepare(_ store: AppStore) {
        activeColor = TagColor.allCases.first { store.tagFilter.contains($0) } ?? .red
        previousResponder = workspaceWindow?.firstResponder
    }
    func move(_ offset: Int, canClear: Bool) {
        let colors: [TagColor?] = TagColor.allCases.map { $0 } + (canClear ? [nil] : [])
        let index = colors.firstIndex(of: activeColor) ?? 0
        activeColor = colors[(index + offset + colors.count) % colors.count]
    }
    func toggle(_ store: AppStore) {
        if let activeColor {
            if store.tagFilter.contains(activeColor) { store.tagFilter.remove(activeColor) }
            else { store.tagFilter.insert(activeColor) }
        } else {
            store.tagFilter.removeAll(); activeColor = .red
        }
        store.touch()
    }
    func restoreFocus(_ store: AppStore) {
        let responder = previousResponder
        let opener = workspaceWindow
        previousResponder = nil
        DispatchQueue.main.async { [weak store, weak opener, weak responder] in
            guard let store, store.canFilterTags, let opener, opener.isKeyWindow,
                  opener.attachedSheet == nil, NSApp.modalWindow == nil, let responder else { return }
            opener.makeFirstResponder(responder)
        }
    }
}

struct TagFilterKeyboardRoute: NSViewRepresentable {
    enum Role { case workspace, palette }
    var store: AppStore
    var navigation: TagFilterNavigation
    @Binding var presented: Bool
    var role: Role
    func makeNSView(context: Context) -> TagFilterKeyboardView {
        let view = TagFilterKeyboardView()
        view.configure(store: store, navigation: navigation, presented: $presented, role: role)
        return view
    }
    func updateNSView(_ view: TagFilterKeyboardView, context: Context) {
        view.configure(store: store, navigation: navigation, presented: $presented, role: role)
    }
    static func dismantleNSView(_ view: TagFilterKeyboardView, coordinator: ()) { view.detach() }
}

// Catch keys before AppKit's field editor or outline turns Tab/Return into
// navigation or credential actions. Each route observes only its own window.
final class TagFilterKeyboardView: NSView {
    private var monitor: Any?
    private weak var store: AppStore?
    private var navigation: TagFilterNavigation?
    private var presentation: Binding<Bool>?
    private(set) var role = TagFilterKeyboardRoute.Role.workspace
    var isPresented: Bool { presentation?.wrappedValue == true }
    override var acceptsFirstResponder: Bool { role == .palette }
    func configure(store: AppStore, navigation: TagFilterNavigation, presented: Binding<Bool>, role: TagFilterKeyboardRoute.Role) {
        self.store = store; self.navigation = navigation; self.presentation = presented; self.role = role
        if role == .workspace { navigation.workspaceWindow = window }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let window else { return }
        if role == .workspace { navigation?.workspaceWindow = window }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        if role == .palette {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.isPresented, self.window === window else { return }
                window?.makeFirstResponder(self)
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }
    func handle(_ event: NSEvent) -> Bool {
        guard let store, store.canFilterTags, let window, event.window === window,
              let navigation, let presentation,
              NSApp.modalWindow == nil, navigation.workspaceWindow?.attachedSheet == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.shift, .command, .control, .option])
        if isPresented {
            guard modifiers.isEmpty || (event.keyCode == 48 && modifiers == .shift) else { return false }
            switch event.keyCode {
            case 126, 123: navigation.move(-1, canClear: !store.tagFilter.isEmpty)
            case 125, 124: navigation.move(1, canClear: !store.tagFilter.isEmpty)
            case 48: navigation.move(modifiers == .shift ? -1 : 1, canClear: !store.tagFilter.isEmpty)
            case 36, 76:
                if !event.isARepeat { navigation.toggle(store) }
            case 53:
                presentation.wrappedValue = false
                navigation.restoreFocus(store)
            default: return false
            }
            store.touch()
            return true
        }
        guard role == .workspace, window.isKeyWindow, event.keyCode == 48, modifiers == .shift else { return false }
        if !event.isARepeat {
            navigation.prepare(store); presentation.wrappedValue = true; store.touch()
        }
        return true
    }
    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
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
