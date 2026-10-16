import SwiftUI
import AppKit

struct CredentialTarget: Hashable {
    let vaultID: String
    let entryID: String
    let fieldID: String
}
struct TrayCredential: Equatable, Identifiable {
    let id: CredentialTarget
    let name: String
    let label: String
    let path: String
    let action: CredentialAction
    var fullTitle: String { "\(name) › \(label)" + (path.isEmpty ? "" : " — \(path)") }
    var title: String { fullTitle.count > 100 ? String(fullTitle.prefix(99)) + "…" : fullTitle }
}
extension Vault {
    var trayCredentials: [TrayCredential] {
        let enabled = Set(trayTags)
        guard !enabled.isEmpty else { return [] }
        var result: [TrayCredential] = [], seen = Set<CredentialTarget>()
        func visit(_ nodes: [VaultNode], ancestors: [String], inherited: Bool) {
            for node in nodes {
                let matches = inherited || !enabled.isDisjoint(with: node.tags)
                if node.isGroup { visit(node.children ?? [], ancestors: ancestors + [node.name], inherited: matches) }
                else {
                    for field in node.fields ?? [] where matches || !enabled.isDisjoint(with: field.tags) {
                        let target = CredentialTarget(vaultID: id, entryID: node.id, fieldID: field.id)
                        if seen.insert(target).inserted {
                            result.append(TrayCredential(id: target, name: node.name, label: field.label,
                                path: ancestors.joined(separator: " › "), action: field.action))
                        }
                    }
                }
            }
        }
        visit(nodes, ancestors: [], inherited: false)
        return result
    }
}
extension AppStore {
    var canUseTrayCredentials: Bool { canManageVault && error == nil }
    func manageTrayTags() {
        guard canManageVault, let id = vault?.id else { return }
        error = nil
        editor = EditorRoute(kind: .trayTags(id))
    }
    @discardableResult func activateTrayCredential(_ target: CredentialTarget) async -> Bool {
        guard canUseTrayCredentials, vault?.id == target.vaultID,
              vault?.trayCredentials.contains(where: { $0.id == target }) == true else { return false }
        return await performFieldAction(entry: target.entryID, field: target.fieldID)
    }
    func saveTrayTags(_ colors: Set<TagColor>, vaultID: String) async -> Bool {
        guard vault?.id == vaultID, serviceAvailable, !busy, !showingKeys, !showingTouchIDSetup,
              !settingsHaveChanges, sshPrompt == nil, deleteTarget == nil else { return false }
        if let editor {
            guard case .trayTags(let id) = editor.kind, id == vaultID else { return false }
        }
        return await mutate("set_tray_tags", ["vault_id": vaultID, "tags": TagColor.allCases.filter { colors.contains($0) }.map(\.rawValue)])
    }
}
struct TrayTagsEditor: View {
    @EnvironmentObject var store: AppStore
    let vaultID: String
    @State private var selected = Set<TagColor>()
    @State private var original = Set<TagColor>()
    @State private var confirmDiscard = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tray Tags").font(.title2.weight(.semibold))
            Text("Choose which tags show credentials in the menu bar for this vault. Fields inside tagged entries and groups are included.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Text("Tag"); Spacer(); Text("Show in tray") }.font(.caption).foregroundStyle(.secondary)
            ForEach(TagColor.allCases) { tag in
                HStack {
                    Circle().fill(tag.color).frame(width: 12, height: 12).accessibilityHidden(true)
                    Text(tag.title)
                    Spacer()
                    Toggle("Show in tray", isOn: Binding(get: { selected.contains(tag) }, set: {
                        if $0 { selected.insert(tag) } else { selected.remove(tag) }
                    })).labelsHidden().toggleStyle(.switch).accessibilityLabel("\(tag.title): Show in tray")
                }
            }
            Text("Only unlocked vaults show credentials. Selecting a credential copies it, opens its URL, or connects via SSH, just like Return in Keepy. Finish open editors first.")
                .font(.caption).foregroundStyle(.secondary)
            EditorError()
            HStack {
                Button("Cancel") { if selected != original { confirmDiscard = true } else { close() } }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Save") {
                    Task { if await store.saveTrayTags(selected, vaultID: vaultID) { close() } }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(selected == original)
            }
        }.padding(24).frame(width: 400).disabled(store.busy).interactiveDismissDisabled(store.busy)
            .onAppear { selected = Set(store.vault?.trayTags ?? []); original = selected; store.error = nil }
            .confirmationDialog("Discard tag changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { close() }
            }
    }
    private func close() { store.editor = nil; store.error = nil }
}
