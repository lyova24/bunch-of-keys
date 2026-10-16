import SwiftUI

// Colors are stable identifiers; names are presentation metadata of one vault.
enum TagNaming {
    static func name(_ color: TagColor, in names: [String: String]) -> String { names[color.rawValue] ?? color.title }
    static func label(_ color: TagColor, in names: [String: String]) -> String {
        names[color.rawValue].map { "\($0) (\(color.title))" } ?? color.title
    }
    static func normalized(_ names: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for color in TagColor.allCases {
            let name = (names[color.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && name.lowercased() != color.title.lowercased() { result[color.rawValue] = name }
        }
        return result
    }
    static func error(_ names: [String: String]) -> String? {
        let names = normalized(names)
        for color in TagColor.allCases {
            let value = names[color.rawValue] ?? ""
            if value.unicodeScalars.count > 40 { return "Tag names must contain at most 40 characters." }
            if value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 }) {
                return "Tag names must not contain control characters or line breaks."
            }
        }
        let effective = TagColor.allCases.map { name($0, in: names).lowercased() }
        if Set(effective).count != effective.count { return "Tag names must be unique, including default color names (case-insensitive)." }
        return nil
    }
}
extension AppStore {
    func tagLabel(_ color: TagColor) -> String { TagNaming.label(color, in: vault?.tagNames ?? [:]) }
    func tagDescription(_ colors: [TagColor]) -> String { colors.map(tagLabel).joined(separator: ", ") }
    func manageTagNames() {
        guard canManageVault else { return }
        openVaultSettings(.tagNames)
    }
    @discardableResult func saveTagNames(_ names: [String: String], vaultID: String) async -> Bool {
        guard vault?.id == vaultID, serviceAvailable, !busy, !showingKeys, !showingTouchIDSetup,
              !settingsHaveChanges, sshPrompt == nil, deleteTarget == nil else { return false }
        guard editor == nil else { return false }
        if let message = TagNaming.error(names) { error = message; return false }
        return await mutate("set_tag_names", ["vault_id": vaultID, "names": TagNaming.normalized(names)])
    }
}
struct TagNamesEditor: View {
    @EnvironmentObject var store: AppStore
    let vaultID: String
    @ViewState private var names: [String: String] = [:]
    @ViewState private var original: [String: String] = [:]
    private var changed: Bool { TagNaming.normalized(names) != original }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tag Names").font(.title2.weight(.semibold))
            Text("Name the existing colors in this vault. Names are encrypted; tag assignments and filters stay the same.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(TagColor.allCases) { color in
                HStack(spacing: 10) {
                    Circle().fill(color.color).frame(width: 12, height: 12).accessibilityHidden(true)
                    Text(color.title).frame(width: 58, alignment: .leading)
                    TextField(color.title, text: Binding(get: { names[color.rawValue] ?? "" }, set: { names[color.rawValue] = $0; store.error = nil }))
                        .textFieldStyle(.roundedBorder).accessibilityLabel("\(color.title) tag name")
                    Button("Reset") { names[color.rawValue] = ""; store.error = nil }
                        .disabled((names[color.rawValue] ?? "").isEmpty).accessibilityLabel("Reset \(color.title) tag name")
                }
            }
            Text("Up to 40 characters. Spaces at the ends are removed. Leave empty or Reset to use the color name. Names must be unique without regard to case, including other colors' default names.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = TagNaming.error(names) ?? store.error {
                Text(message).font(.callout).foregroundStyle(.red).accessibilityLabel(message)
            }
            HStack {
                Button("Cancel") { reset() }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Save") { Task { if await store.saveTagNames(names, vaultID: vaultID) { original = store.vault?.tagNames ?? [:]; reset(); store.notice = "Tag names saved." } } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!changed || TagNaming.error(names) != nil)
            }
            SettingsSaveStatus()
        }.padding(24).frame(maxWidth: .infinity).disabled(store.busy)
            .onAppear { original = store.vault?.tagNames ?? [:]; names = original; store.error = nil }
            .onChange(of: names) { _, _ in store.vaultSettingsHaveChanges = changed }
            .onDisappear { store.vaultSettingsHaveChanges = false }
    }
    private func reset() { names = original; store.vaultSettingsHaveChanges = false; store.error = nil }
}
