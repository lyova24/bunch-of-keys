import Foundation
import SwiftUI
import AppKit

enum TagColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}

struct VaultSummary: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}
struct Preferences: Codable, Equatable {
    var autostart = false
    var autoLockSeconds = 300
    var clipboardClearSeconds = 30
    var appearance = "system"
    var liquidGlass = true
}
struct Bootstrap: Decodable {
    var vaults: [VaultSummary]
    var settings: Preferences
    var current: Vault?
    var activeSsh: [ActiveConnection]
}
struct ActiveConnection: Decodable { var entryId: String; var fieldId: String }
struct Vault: Decodable, Equatable {
    var id: String
    var sshKeys: [SSHKey]
    var nodes: [VaultNode]
    var trayTags: [TagColor]
    init(id: String, sshKeys: [SSHKey], nodes: [VaultNode], trayTags: [TagColor] = []) {
        self.id = id; self.sshKeys = sshKeys; self.nodes = nodes; self.trayTags = trayTags
    }
    private enum CodingKeys: String, CodingKey { case id, sshKeys, nodes, trayTags }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sshKeys = try values.decode([SSHKey].self, forKey: .sshKeys)
        nodes = try values.decode([VaultNode].self, forKey: .nodes)
        trayTags = try values.decodeIfPresent([TagColor].self, forKey: .trayTags) ?? []
    }
    func node(_ id: String?) -> VaultNode? {
        guard let id else { return nil }
        return nodes.lazy.compactMap { $0.find(id) }.first
    }
    func parent(of id: String, in nodes: [VaultNode]? = nil, parent: String? = nil) -> String? {
        for node in nodes ?? self.nodes {
            if node.id == id { return parent }
            if let children = node.children, children.contains(where: { $0.find(id) != nil }) {
                return self.parent(of: id, in: children, parent: node.id)
            }
        }
        return nil
    }
}
struct VaultNode: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var type: String
    var children: [VaultNode]?
    var fields: [VaultField]?
    var tags: [TagColor] = []
    init(id: String, name: String, type: String, children: [VaultNode]? = nil, fields: [VaultField]? = nil, tags: [TagColor] = []) {
        self.id = id; self.name = name; self.type = type; self.children = children; self.fields = fields; self.tags = tags
    }
    private enum CodingKeys: String, CodingKey { case id, name, type, children, fields, tags }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(String.self, forKey: .type)
        children = try values.decodeIfPresent([VaultNode].self, forKey: .children)
        fields = try values.decodeIfPresent([VaultField].self, forKey: .fields)
        tags = try values.decodeIfPresent([TagColor].self, forKey: .tags) ?? []
    }
    var isGroup: Bool { type == "group" }
    func find(_ id: String) -> VaultNode? {
        if self.id == id { return self }
        return children?.lazy.compactMap { $0.find(id) }.first
    }
    func filtered(_ query: String, tags: Set<TagColor> = [], inheritedTagMatch: Bool = false) -> VaultNode? {
        // First keep tagged branches, then search within that result. Matching
        // group names retain the same subtree behavior as ordinary text search.
        tagged(tags, inheritedMatch: inheritedTagMatch)?.filteredText(query)
    }
    private func tagged(_ colors: Set<TagColor>, inheritedMatch: Bool) -> VaultNode? {
        if colors.isEmpty || inheritedMatch || !colors.isDisjoint(with: tags) { return self }
        if !isGroup {
            let matching = (fields ?? []).filter { !colors.isDisjoint(with: $0.tags) }
            guard !matching.isEmpty else { return nil }
            var node = self; node.fields = matching; return node
        }
        let children = (children ?? []).compactMap { $0.tagged(colors, inheritedMatch: false) }
        if children.isEmpty { return nil }
        var node = self; node.children = children; return node
    }
    private func filteredText(_ query: String) -> VaultNode? {
        if query.isEmpty { return self }
        let matches = name.localizedCaseInsensitiveContains(query) || (fields ?? []).contains {
            $0.label.localizedCaseInsensitiveContains(query) ||
            (!$0.masked && ($0.value?.localizedCaseInsensitiveContains(query) ?? false)) ||
            ($0.ssh?.address.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.ssh?.user.localizedCaseInsensitiveContains(query) ?? false)
        }
        if matches { return self }
        let children = (children ?? []).compactMap { $0.filteredText(query) }
        if children.isEmpty { return nil }
        var node = self; node.children = children; return node
    }
}
struct SSHKey: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var algorithm: String
    var fingerprint: String
    var encrypted: Bool
}
struct SSHConnection: Decodable, Equatable {
    var user: String
    var address: String
    var port: Int?
    var key: SSHKey
}
struct VaultField: Decodable, Identifiable, Equatable {
    var id: String
    var label: String
    var kind: String
    var masked: Bool
    var value: String?
    var ssh: SSHConnection?
    var tags: [TagColor] = []
    init(id: String, label: String, kind: String, masked: Bool, value: String? = nil, ssh: SSHConnection? = nil, tags: [TagColor] = []) {
        self.id = id; self.label = label; self.kind = kind; self.masked = masked; self.value = value; self.ssh = ssh; self.tags = tags
    }
    private enum CodingKeys: String, CodingKey { case id, label, kind, masked, value, ssh, tags }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); label = try values.decode(String.self, forKey: .label)
        kind = try values.decode(String.self, forKey: .kind); masked = try values.decode(Bool.self, forKey: .masked)
        value = try values.decodeIfPresent(String.self, forKey: .value); ssh = try values.decodeIfPresent(SSHConnection.self, forKey: .ssh)
        tags = try values.decodeIfPresent([TagColor].self, forKey: .tags) ?? []
    }
}
struct FieldDraft: Identifiable, Equatable {
    var id = UUID().uuidString.lowercased()
    var label = ""
    var kind = "text"
    var value = ""
    var masked = false
    var user = ""
    var address = ""
    var port = ""
    var keyId = ""
    var tags = Set<TagColor>()
    var payload: [String: Any] {
        var result: [String: Any] = ["id": id, "label": label, "kind": kind, "value": value, "masked": masked, "tags": TagColor.allCases.filter { tags.contains($0) }.map(\.rawValue)]
        if kind == "ssh" {
            var ssh: [String: Any] = ["user": user, "address": address, "key_id": keyId]
            if !port.isEmpty { ssh["port"] = Int(port) ?? 0 }
            result["ssh"] = ssh
        }
        return result
    }
    init() {}
    init(_ field: VaultField) {
        tags = Set(field.tags)
        id = field.id; label = field.label; kind = field.kind; value = field.value ?? ""; masked = field.masked
        user = field.ssh?.user ?? ""; address = field.ssh?.address ?? ""
        port = field.ssh?.port.map(String.init) ?? ""; keyId = field.ssh?.key.id ?? ""
    }
}

enum CredentialAction: String {
    case copy, openURL, connectSSH
    var title: String {
        switch self { case .copy: return "Copy"; case .openURL: return "Open URL"; case .connectSSH: return "Connect in Terminal" }
    }
    var symbol: String {
        switch self { case .copy: return "doc.on.doc"; case .openURL: return "arrow.up.right.square"; case .connectSSH: return "terminal" }
    }
}
extension VaultField {
    var action: CredentialAction { kind == "url" ? .openURL : kind == "ssh" ? .connectSSH : .copy }
}
