import Foundation

@main struct Integration {
    static func main() async throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let client = CoreClient(executable: executable)
        func call(_ command: String, _ args: [String: Any] = [:]) async throws -> Data { try await client.request(command, args) }
        func mutation(_ command: String, _ args: [String: Any]) async throws -> Vault {
            try CoreClient.decoder.decode(Vault.self, from: await call(command, args))
        }
        let created = try await mutation("create_vault", ["name": "Native Test", "password": "synthetic-test-password"])
        let group = try await mutation("add_group", ["name": "Work", "index": 0])
        let parent = group.nodes.first!.id
        var vault = try await mutation("add_entry", ["parent_id": parent, "name": "Server", "fields": [
            ["label": "Password", "kind": "secret", "value": "synthetic-secret", "masked": true],
            ["label": "Website", "kind": "url", "value": "https://example.com", "masked": false],
            ["label": "Note", "kind": "text", "value": "hello\nworld", "masked": false]
        ]])
        var entry = vault.node(parent)!.children!.first!
        let secret = entry.fields!.first!
        precondition(secret.value == nil)
        precondition(vault.nodes.first!.filtered("synthetic-secret") == nil, "Masked values must not be searched")
        let plain = try JSONDecoder().decode(String.self, from: await call("reveal_field", ["entry_id": entry.id, "field_id": secret.id]))
        precondition(plain == "synthetic-secret")
        let copied = try JSONDecoder().decode(String.self, from: await call("copy_field", ["entry_id": entry.id, "field_id": secret.id]))
        precondition(copied == plain)
        let url = try JSONDecoder().decode(String.self, from: await call("open_url", ["entry_id": entry.id, "field_id": entry.fields![1].id]))
        precondition(url == "https://example.com")
        vault = try await mutation("move_field", ["entry_id": entry.id, "field_id": secret.id, "index": 2])
        precondition(vault.node(entry.id)!.fields!.last!.id == secret.id)
        precondition(vault.node(entry.id)!.fields!.last!.value == nil)
        vault = try await mutation("move_field", ["entry_id": entry.id, "field_id": secret.id, "index": 0])
        entry = vault.node(entry.id)!
        var fields = entry.fields!.map(FieldDraft.init)
        fields[0].value = plain
        fields.swapAt(0, 2)
        vault = try await mutation("update_entry", ["entry_id": entry.id, "name": "Renamed", "fields": fields.map(\.payload)])
        entry = vault.node(entry.id)!
        precondition(entry.fields!.map(\.id) == fields.map(\.id))
        vault = try await mutation("move_node", ["node_id": entry.id, "index": 0])
        precondition(vault.nodes.first!.id == entry.id)
        precondition(vault.parent(of: entry.id) == nil)
        do { _ = try await call("move_node", ["node_id": parent, "parent_id": parent, "index": 0]); fatalError("Cycle accepted") } catch {}
        vault = try await mutation("import_yaml_file", ["source": "Imported:\n  username: example\n  password: synthetic-import\n"])
        precondition(vault.nodes.count > 2)
        let draft = try await mutation("add_entry", ["parent_id": parent, "index": 0, "name": "Moved draft", "fields": []])
        precondition(draft.node(parent)!.children!.first!.name == "Moved draft")
        _ = try await call("lock_vault")
        do { _ = try await call("reveal_field", ["entry_id": entry.id, "field_id": secret.id]); fatalError("Read after lock") } catch {}
        do { _ = try await call("unlock_vault", ["vault_id": created.id, "password": "incorrect"]); fatalError("Wrong password accepted") } catch {}
        vault = try await mutation("unlock_vault", ["vault_id": created.id, "password": "synthetic-test-password"])
        precondition(vault.node(entry.id)?.name == "Renamed")
        let keyURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let privateKey = try String(contentsOf: keyURL, encoding: .utf8)
        vault = try await mutation("add_ssh_key", ["name": "Synthetic", "private_key": privateKey])
        let key = vault.sshKeys.first!
        vault = try await mutation("add_entry", ["name": "SSH", "fields": [["label": "Connect", "value": "", "kind": "ssh", "masked": false, "ssh": ["user": "deploy", "address": "localhost", "port": 2222, "key_id": key.id]]]])
        precondition(vault.nodes.last!.fields!.first!.ssh!.key.id == key.id)
        let metadata = try await call("bootstrap")
        precondition(!String(decoding: metadata, as: UTF8.self).contains("PRIVATE KEY"))
        vault = try await mutation("update_ssh_key", ["key_id": key.id, "name": "Renamed Key"])
        precondition(vault.nodes.last!.fields!.first!.ssh!.key.name == "Renamed Key")
        do { _ = try await call("delete_ssh_key", ["key_id": key.id]); fatalError("Referenced key deleted") } catch {}
        vault = try await mutation("delete_node", ["node_id": vault.nodes.last!.id])
        vault = try await mutation("delete_ssh_key", ["key_id": key.id])
        precondition(vault.sshKeys.isEmpty)
        _ = try await call("update_settings", ["settings": ["autostart": false, "auto_lock_seconds": 60, "clipboard_clear_seconds": 5, "appearance": "dark", "liquid_glass": false]])
        let state = try CoreClient.decoder.decode(Bootstrap.self, from: await call("bootstrap"))
        precondition(state.settings.appearance == "dark" && !state.settings.liquidGlass)
        _ = try await call("lock_vault")
        await client.stop()
        let reopened = CoreClient(executable: executable)
        let state2 = try CoreClient.decoder.decode(Bootstrap.self, from: await reopened.request("bootstrap"))
        precondition(state2.current == nil && state2.vaults.first!.id == created.id && state2.settings.appearance == "dark")
        let saved = try CoreClient.decoder.decode(Vault.self, from: await reopened.request("unlock_vault", ["vault_id": created.id, "password": "synthetic-test-password"]))
        precondition(saved.node(entry.id)?.fields?.map(\.id) == fields.map(\.id))
        _ = try await reopened.request("lock_vault")
        await reopened.stop()
        try await NativeStore.run(executable: executable, vaultId: created.id, entryId: entry.id, fieldId: secret.id)
        try await NativeOutline.run(executable: executable)
        try await NativeWindowSurface.run()
        print("Native pipe integration passed: vaults, masking, fields, moves, import, SSH keys, settings and restart.")
    }
}
