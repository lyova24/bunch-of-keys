import Foundation

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
    var isGroup: Bool { type == "group" }
    func find(_ id: String) -> VaultNode? {
        if self.id == id { return self }
        return children?.lazy.compactMap { $0.find(id) }.first
    }
    func filtered(_ query: String) -> VaultNode? {
        if query.isEmpty { return self }
        let matches = name.localizedCaseInsensitiveContains(query) || (fields ?? []).contains {
            $0.label.localizedCaseInsensitiveContains(query) ||
            (!$0.masked && ($0.value?.localizedCaseInsensitiveContains(query) ?? false)) ||
            ($0.ssh?.address.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.ssh?.user.localizedCaseInsensitiveContains(query) ?? false)
        }
        if matches { return self }
        let children = (children ?? []).compactMap { $0.filtered(query) }
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
    var payload: [String: Any] {
        var result: [String: Any] = ["id": id, "label": label, "kind": kind, "value": value, "masked": masked]
        if kind == "ssh" {
            var ssh: [String: Any] = ["user": user, "address": address, "key_id": keyId]
            if !port.isEmpty { ssh["port"] = Int(port) ?? 0 }
            result["ssh"] = ssh
        }
        return result
    }
    init() {}
    init(_ field: VaultField) {
        id = field.id; label = field.label; kind = field.kind; value = field.value ?? ""; masked = field.masked
        user = field.ssh?.user ?? ""; address = field.ssh?.address ?? ""
        port = field.ssh?.port.map(String.init) ?? ""; keyId = field.ssh?.key.id ?? ""
    }
}
