import Foundation

@main struct Integration {
    static func main() async throws {
        NativeUpdates.run()
        try verifyTagFiltering()
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let client = CoreClient(executable: executable)
        func call(_ command: String, _ args: [String: Any] = [:]) async throws -> Data { try await client.request(command, args) }
        func mutation(_ command: String, _ args: [String: Any]) async throws -> Vault {
            try CoreClient.decoder.decode(Vault.self, from: await call(command, args))
        }
        let created = try await mutation("create_vault", ["name": "Native Test", "password": "synthetic-test-password"])
        let group = try await mutation("add_group", ["name": "Work", "index": 0, "tags": ["red"]])
        let parent = group.nodes.first!.id
        precondition(group.node(parent)!.tags == [.red])
        var vault = try await mutation("add_entry", ["parent_id": parent, "name": "Server", "tags": ["blue", "green"], "fields": [
            ["label": "Password", "kind": "secret", "value": "synthetic-secret", "masked": true],
            ["label": "Website", "kind": "url", "value": "https://example.com", "masked": false],
            ["label": "Note", "kind": "text", "value": "hello\nworld", "masked": false]
        ]])
        var entry = vault.node(parent)!.children!.first!
        let secret = entry.fields!.first!
        precondition(secret.value == nil)
        precondition(Set(entry.tags) == [.blue, .green])
        vault = try await mutation("rename_node", ["node_id": parent, "name": "Work renamed"])
        precondition(vault.node(parent)!.tags == [.red], "Legacy renaming must preserve tags")
        vault = try await mutation("rename_node", ["node_id": parent, "name": "Work", "tags": NSNull()])
        precondition(vault.node(parent)!.tags == [.red], "Null tags must preserve existing tags")
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
        precondition(Set(entry.tags) == [.blue, .green], "Legacy entry edits must preserve tags")
        vault = try await mutation("update_entry", ["entry_id": entry.id, "name": "Renamed", "fields": fields.map(\.payload), "tags": NSNull()])
        precondition(Set(vault.node(entry.id)!.tags) == [.blue, .green])
        vault = try await mutation("update_entry", ["entry_id": entry.id, "name": "Renamed", "fields": fields.map(\.payload), "tags": ["blue", "purple"]])
        precondition(Set(vault.node(entry.id)!.tags) == [.blue, .purple], "Saving an entry can replace its tags")
        vault = try await mutation("set_node_tags", ["node_id": entry.id, "tags": []])
        precondition(vault.node(entry.id)!.tags.isEmpty, "All tags can be removed")
        vault = try await mutation("set_node_tags", ["node_id": entry.id, "tags": ["purple", "blue"]])
        let savedTags: Set<TagColor> = [.blue, .purple]
        precondition(Set(vault.node(entry.id)!.tags) == savedTags)
        let beforeInvalidTags = vault
        let invalidTagArguments: [[String: Any]] = [
            ["node_id": entry.id, "tags": ["red", "red"]],
            ["node_id": entry.id, "tags": ["unknown"]]
        ]
        for args in invalidTagArguments {
            do { _ = try await call("set_node_tags", args); fatalError("Invalid tags accepted") } catch {}
            let current = try CoreClient.decoder.decode(Bootstrap.self, from: await call("bootstrap")).current
            precondition(current == beforeInvalidTags, "Invalid tags must not mutate the vault")
        }
        vault = try await mutation("move_node", ["node_id": entry.id, "index": 0])
        precondition(vault.nodes.first!.id == entry.id)
        precondition(vault.parent(of: entry.id) == nil)
        precondition(Set(vault.node(entry.id)!.tags) == savedTags, "Moving an entry must preserve its tags")
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
        precondition(Set(vault.node(entry.id)!.tags) == savedTags && vault.node(parent)!.tags == [.red])
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
        precondition(Set(saved.node(entry.id)!.tags) == savedTags && saved.node(parent)!.tags == [.red], "Encrypted tags must survive a full service restart")
        _ = try await reopened.request("lock_vault")
        await reopened.stop()
        try await NativeStore.run(executable: executable, vaultId: created.id, entryId: entry.id, fieldId: secret.id)
        try await NativeOutline.run(executable: executable)
        try await NativeWindowSurface.run()
        try await NativeTagFilter.run(executable: executable)
        print("Native pipe integration passed: vaults, masking, fields, moves, tags, import, SSH keys, settings and restart.")
    }

    static func verifyTagFiltering() throws {
        let legacy = try JSONDecoder().decode(VaultNode.self, from: Data("""
        {"id":"legacy","name":"Old vault","type":"group","children":[
          {"id":"legacy-entry","name":"Existing entry","type":"entry","fields":[]}
        ]}
        """.utf8))
        precondition(legacy.tags.isEmpty && legacy.children!.first!.tags.isEmpty, "Older views without tags must decode")
        let tree = try JSONDecoder().decode(VaultNode.self, from: Data("""
        {"id":"outer","name":"Collections","type":"group","tags":[],"children":[
          {"id":"work","name":"Work","type":"group","tags":["red"],"children":[
            {"id":"alpha","name":"Alpha","type":"entry","tags":[],"fields":[
              {"id":"public","label":"Account","kind":"text","masked":false,"value":"deploy"},
              {"id":"secret","label":"Password","kind":"secret","masked":true,"value":"hidden-secret"}
            ]},
            {"id":"nested","name":"Nested","type":"group","tags":[],"children":[
              {"id":"beta","name":"Beta","type":"entry","tags":["green"],"fields":[]}
            ]}
          ]},
          {"id":"personal","name":"Personal","type":"entry","tags":["blue"],"fields":[]},
          {"id":"untagged","name":"Unmarked","type":"entry","tags":[],"fields":[]}
        ]}
        """.utf8))
        precondition(tree.filtered("", tags: []) == tree)
        let red = tree.filtered("", tags: [.red])!
        precondition(red.children!.map(\.id) == ["work"], "Keep only matching branches and their ancestors")
        precondition(red.find("alpha") != nil && red.find("beta") != nil, "A tagged group includes all descendants")
        let blue = tree.filtered("", tags: [.blue])!
        precondition(blue.children!.map(\.id) == ["personal"], "Unmatched sibling branches must be hidden")
        let either = tree.filtered("", tags: [.red, .blue])!
        precondition(either.children!.map(\.id) == ["work", "personal"], "Selected colors use OR")
        let green = tree.filtered("", tags: [.green])!
        precondition(green.find("beta") != nil && green.find("alpha") == nil, "Deep tag matches retain only the required ancestor context")
        let searched = tree.filtered("bEtA", tags: [.red])!
        precondition(searched.find("work") != nil && searched.find("nested") != nil && searched.find("beta") != nil)
        precondition(searched.find("alpha") == nil, "Search must still filter descendants of a tagged group")
        precondition(tree.filtered("Beta", tags: [.blue]) == nil, "Search and selected colors use AND")
        let visible = tree.filtered("DEPLOY", tags: [.red])!
        precondition(visible.find("alpha") != nil && visible.find("beta") == nil, "Visible values remain searchable")
        precondition(tree.filtered("hidden-secret", tags: [.red]) == nil, "Tags must not make masked values searchable")
        precondition(tree.filtered("", tags: [.purple]) == nil, "No matching tags must produce an empty result")
        print("Native tag filtering passed: legacy decoding, color OR, search AND, ancestor context, group descendants and masked values.")
    }
}
