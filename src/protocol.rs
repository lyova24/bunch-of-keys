use crate::{
    app::AppState,
    core::{BiometricCredential, FieldInput, TagColor, import_yaml},
    storage::Settings,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    io::{self, BufRead, Write},
    sync::Arc,
};
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};
const MAX_REQUEST_BYTES: usize = 72 * 1024 * 1024;
#[derive(Deserialize)]
struct Request {
    id: u64,
    #[serde(flatten)]
    command: Command,
}
#[derive(Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
enum Command {
    Bootstrap,
    Touch,
    LockVault,
    CreateVault {
        name: String,
        password: String,
    },
    UnlockVault {
        vault_id: Uuid,
        password: String,
    },
    BiometricBinding {
        vault_id: Uuid,
    },
    EnrollBiometric {
        vault_id: Uuid,
        password: String,
    },
    BeginBiometricUnlock {
        vault_id: Uuid,
    },
    UnlockBiometric {
        vault_id: Uuid,
        ticket: Uuid,
        credential: BiometricCredential,
    },
    AddGroup {
        parent_id: Option<Uuid>,
        name: String,
        index: Option<usize>,
        #[serde(default)]
        tags: Vec<TagColor>,
    },
    AddEntry {
        parent_id: Option<Uuid>,
        name: String,
        fields: Vec<FieldInput>,
        index: Option<usize>,
        #[serde(default)]
        tags: Vec<TagColor>,
    },
    UpdateEntry {
        entry_id: Uuid,
        name: String,
        fields: Vec<FieldInput>,
        tags: Option<Vec<TagColor>>,
    },
    RenameNode {
        node_id: Uuid,
        name: String,
        tags: Option<Vec<TagColor>>,
    },
    SetNodeTags {
        node_id: Uuid,
        tags: Vec<TagColor>,
    },
    DeleteNode {
        node_id: Uuid,
    },
    MoveNode {
        node_id: Uuid,
        parent_id: Option<Uuid>,
        index: usize,
    },
    MoveField {
        entry_id: Uuid,
        field_id: Uuid,
        index: usize,
    },
    ImportYamlFile {
        source: String,
    },
    RevealField {
        entry_id: Uuid,
        field_id: Uuid,
    },
    CopyField {
        entry_id: Uuid,
        field_id: Uuid,
    },
    OpenUrl {
        entry_id: Uuid,
        field_id: Uuid,
    },
    ConnectSsh {
        entry_id: Uuid,
        field_id: Uuid,
        passphrase: Option<String>,
    },
    AddSshKey {
        name: String,
        private_key: String,
    },
    UpdateSshKey {
        key_id: Uuid,
        name: String,
        private_key: Option<String>,
    },
    DeleteSshKey {
        key_id: Uuid,
    },
    UpdateSettings {
        settings: Settings,
    },
}
fn execute(state: &Arc<AppState>, command: Command) -> Result<Value, String> {
    let result = match command {
        Command::Bootstrap => serde_json::to_value(state.bootstrap().map_err(|e| e.to_string())?),
        Command::Touch => {
            state.touch();
            Ok(Value::Null)
        }
        Command::LockVault => {
            state.lock();
            Ok(Value::Null)
        }
        Command::CreateVault { name, password } => {
            let password = Zeroizing::new(password);
            serde_json::to_value(
                state
                    .create_vault(&name, password.as_bytes())
                    .map_err(|e| e.to_string())?,
            )
        }
        Command::UnlockVault { vault_id, password } => {
            let password = Zeroizing::new(password);
            serde_json::to_value(
                state
                    .unlock_vault(vault_id, password.as_bytes())
                    .map_err(|e| e.to_string())?,
            )
        }
        Command::RevealField { entry_id, field_id } | Command::CopyField { entry_id, field_id } => {
            serde_json::to_value(
                state
                    .field_value(entry_id, field_id)
                    .map_err(|e| e.to_string())?,
            )
        }
        Command::BiometricBinding { vault_id } => serde_json::to_value(
            state
                .biometric_binding(vault_id)
                .map_err(|e| e.to_string())?,
        ),
        Command::EnrollBiometric { vault_id, password } => {
            let password = Zeroizing::new(password);
            serde_json::to_value(
                state
                    .enroll_biometric(vault_id, password.as_bytes())
                    .map_err(|e| e.to_string())?,
            )
        }
        Command::BeginBiometricUnlock { vault_id } => serde_json::to_value(
            state
                .begin_biometric_unlock(vault_id)
                .map_err(|e| e.to_string())?,
        ),
        Command::UnlockBiometric {
            vault_id,
            ticket,
            credential,
        } => serde_json::to_value(
            state
                .unlock_biometric(vault_id, ticket, &credential)
                .map_err(|e| e.to_string())?,
        ),
        Command::OpenUrl { entry_id, field_id } => serde_json::to_value(
            state
                .open_url(entry_id, field_id)
                .map_err(|e| e.to_string())?,
        ),
        Command::ConnectSsh {
            entry_id,
            field_id,
            passphrase,
        } => {
            let passphrase = passphrase.map(Zeroizing::new);
            state
                .connect_ssh(
                    entry_id,
                    field_id,
                    passphrase.as_deref().map(String::as_str),
                )
                .map_err(|e| e.to_string())?;
            Ok(Value::Null)
        }
        Command::UpdateSettings { settings } => {
            state.save_settings(settings).map_err(|e| e.to_string())?;
            Ok(Value::Null)
        }
        command => return execute_mutation(state, command),
    };
    result.map_err(|e| e.to_string())
}
fn execute_mutation(state: &Arc<AppState>, command: Command) -> Result<Value, String> {
    let view = state
        .mutate(|data| {
            match command {
                Command::AddGroup {
                    parent_id,
                    name,
                    index,
                    tags,
                } => {
                    let id = if tags.is_empty() {
                        data.add_group(parent_id, &name)?
                    } else {
                        data.add_group_with_tags(parent_id, &name, tags)?
                    };
                    if let Some(index) = index {
                        data.move_node(id, parent_id, index)?;
                    }
                }
                Command::AddEntry {
                    parent_id,
                    name,
                    fields,
                    index,
                    tags,
                } => {
                    let id = if tags.is_empty() {
                        data.add_entry(parent_id, &name, fields)?
                    } else {
                        data.add_entry_with_tags(parent_id, &name, fields, tags)?
                    };
                    if let Some(index) = index {
                        data.move_node(id, parent_id, index)?;
                    }
                }
                Command::UpdateEntry {
                    entry_id,
                    name,
                    fields,
                    tags,
                } => {
                    if tags.is_some() {
                        data.replace_entry_with_tags(entry_id, &name, fields, tags)?;
                    } else {
                        data.replace_entry(entry_id, &name, fields)?;
                    }
                }
                Command::RenameNode {
                    node_id,
                    name,
                    tags,
                } => {
                    if tags.is_some() {
                        data.rename_node_with_tags(node_id, &name, tags)?;
                    } else {
                        data.rename_node(node_id, &name)?;
                    }
                }
                Command::SetNodeTags { node_id, tags } => data.set_node_tags(node_id, tags)?,
                Command::DeleteNode { node_id } => data.delete_node(node_id)?,
                Command::MoveNode {
                    node_id,
                    parent_id,
                    index,
                } => data.move_node(node_id, parent_id, index)?,
                Command::MoveField {
                    entry_id,
                    field_id,
                    index,
                } => data.move_field(entry_id, field_id, index)?,
                Command::ImportYamlFile { source } => {
                    let source = Zeroizing::new(source);
                    data.extend_root(import_yaml(&source)?);
                }
                Command::AddSshKey { name, private_key } => {
                    let key = Zeroizing::new(private_key);
                    data.add_ssh_key(&name, &key)?;
                }
                Command::UpdateSshKey {
                    key_id,
                    name,
                    private_key,
                } => {
                    let key = private_key.map(Zeroizing::new);
                    data.update_ssh_key(key_id, &name, key.as_deref().map(String::as_str))?;
                }
                Command::DeleteSshKey { key_id } => data.delete_ssh_key(key_id)?,
                _ => unreachable!("commands handled above"),
            }
            Ok(())
        })
        .map_err(|e| e.to_string())?;
    serde_json::to_value(view).map_err(|e| e.to_string())
}

pub fn serve(input: impl BufRead, output: impl Write, state: &Arc<AppState>) -> io::Result<()> {
    serve_responses(input, output, |command| execute(state, command))
}

pub fn serve_failure(input: impl BufRead, output: impl Write, message: &str) -> io::Result<()> {
    serve_responses(input, output, |_| Err(message.to_owned()))
}

fn serve_responses(
    mut input: impl BufRead,
    mut output: impl Write,
    mut execute_command: impl FnMut(Command) -> Result<Value, String>,
) -> io::Result<()> {
    loop {
        let mut bytes = Zeroizing::new(Vec::new());
        while !bytes.ends_with(b"\n") {
            let available = input.fill_buf()?;
            if available.is_empty() {
                break;
            }
            let count = available
                .iter()
                .position(|byte| *byte == b'\n')
                .map_or(available.len(), |index| index + 1);
            if bytes.len() + count > MAX_REQUEST_BYTES {
                return Err(io::ErrorKind::InvalidData.into());
            }
            bytes.extend_from_slice(&available[..count]);
            input.consume(count);
        }
        if bytes.is_empty() {
            return Ok(());
        }
        let response = SensitiveResponse(match serde_json::from_slice::<Request>(&bytes) {
            Ok(request) => match execute_command(request.command) {
                Ok(value) => json!({"id": request.id, "result": value}),
                Err(error) => json!({"id": request.id, "error": error}),
            },
            Err(_) => json!({"id": 0, "error": "invalid request"}),
        });
        let mut encoded = Zeroizing::new(serde_json::to_vec(&response.0)?);
        output.write_all(&encoded)?;
        output.write_all(b"\n")?;
        output.flush()?;
        encoded.zeroize();
    }
}

// Includes dedicated enrollment responses and explicitly revealed field values.
// Clear the JSON-owned strings even if writing the pipe fails.
struct SensitiveResponse(Value);
impl Drop for SensitiveResponse {
    fn drop(&mut self) {
        fn clear(value: &mut Value) {
            match value {
                Value::String(text) => text.zeroize(),
                Value::Array(items) => items.iter_mut().for_each(clear),
                Value::Object(items) => items.values_mut().for_each(clear),
                _ => {}
            }
        }
        clear(&mut self.0);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{AppConfig, AppStorage};

    #[test]
    fn startup_failure_reaches_native_client_without_executing_actions() {
        let input =
            b"{\"id\":1,\"command\":\"bootstrap\"}\n{\"id\":2,\"command\":\"lock_vault\"}\n";
        let message =
            "The vault service could not initialize Keepy storage: conflicting data folders";
        let mut output = Vec::new();
        serve_failure(&input[..], &mut output, message).unwrap();
        let responses: Vec<Value> = String::from_utf8(output)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(responses.len(), 2);
        for (index, response) in responses.iter().enumerate() {
            assert_eq!(response["id"], index + 1);
            assert_eq!(response["error"], message);
            assert!(response.get("result").is_none());
        }
    }

    fn run_command(state: &Arc<AppState>, command: Value) -> Result<Value, String> {
        execute(state, serde_json::from_value(command).unwrap())
    }

    #[test]
    fn biometric_pipe_enrollment_unlock_and_cancellation_are_vault_bound() {
        let fixture = tagged_fixture();
        let state = &fixture.state;
        let id = &fixture.vault_id;
        assert!(
            run_command(
                state,
                json!({"command":"enroll_biometric", "vault_id":id,"password":"wrong"})
            )
            .is_err()
        );
        let credential = run_command(
            state,
            json!({"command":"enroll_biometric", "vault_id":id,"password":"password123"}),
        )
        .unwrap();
        let before = run_command(state, json!({"command":"bootstrap"})).unwrap();
        assert!(
            !serde_json::to_string(&before)
                .unwrap()
                .contains("wrapping_key")
        );
        assert!(before["current"]["nodes"][0]["children"][0]["fields"][0]["value"].is_null());
        let binding =
            run_command(state, json!({"command":"biometric_binding", "vault_id":id})).unwrap();
        assert_eq!(binding, credential["binding"]);
        run_command(state, json!({"command":"lock_vault"})).unwrap();
        assert!(
            run_command(
                state,
                json!({"command":"enroll_biometric", "vault_id":id,"password":"password123"})
            )
            .is_err()
        );

        let ticket = run_command(
            state,
            json!({"command":"begin_biometric_unlock", "vault_id":id}),
        )
        .unwrap();
        let unlock = json!({"command":"unlock_biometric","vault_id":id,"ticket":ticket,"credential":credential});
        let restored = run_command(state, unlock.clone()).unwrap();
        assert_eq!(restored, before["current"]);
        assert!(
            run_command(state, unlock).is_err(),
            "A completed ticket cannot be reused"
        );
        let ticket = run_command(
            state,
            json!({"command":"begin_biometric_unlock", "vault_id":id}),
        )
        .unwrap();
        run_command(state, json!({"command":"lock_vault"})).unwrap();
        assert!(run_command(state, json!({"command":"unlock_biometric","vault_id":id,"ticket":ticket,"credential":credential})).is_err());
        assert!(run_command(state, json!({"command":"bootstrap"})).unwrap()["current"].is_null());

        let ticket = run_command(
            state,
            json!({"command":"begin_biometric_unlock", "vault_id":id}),
        )
        .unwrap();
        run_command(
            state,
            json!({"command":"create_vault","name":"Other","password":"other-password"}),
        )
        .unwrap();
        assert!(run_command(state, json!({"command":"unlock_biometric","vault_id":id,"ticket":ticket,"credential":credential})).is_err());
        assert!(
            run_command(
                state,
                json!({"command":"enroll_biometric", "vault_id":id,"password":"password123"})
            )
            .is_err()
        );
    }

    struct TaggedFixture {
        _directory: tempfile::TempDir,
        state: Arc<AppState>,
        vault_id: Value,
        group_id: Value,
        entry_id: Value,
        field_id: Value,
    }

    fn tagged_fixture() -> TaggedFixture {
        let directory = tempfile::tempdir().unwrap();
        let state = Arc::new(AppState::new(
            AppStorage::new(directory.path(), directory.path()).unwrap(),
            AppConfig::default(),
        ));
        let created = run_command(
            &state,
            json!({"command": "create_vault", "name": "Test", "password": "password123"}),
        )
        .unwrap();
        let vault_id = created["id"].clone();
        let group = run_command(&state, json!({"command": "add_group", "name": "Legacy"})).unwrap();
        let group_id = group["nodes"][0]["id"].clone();
        assert_eq!(group["nodes"][0]["tags"], json!([]));
        let tags = run_command(
            &state,
            json!({"command": "set_node_tags", "node_id": group_id, "tags": ["blue", "green"]}),
        )
        .unwrap();
        assert_eq!(tags["nodes"][0]["tags"], json!(["blue", "green"]));
        let entry = run_command(
            &state,
            json!({
                "command": "add_entry", "parent_id": group_id, "name": "Server", "tags": ["red"],
                "fields": [{"label": "Password", "value": "synthetic-secret", "kind": "secret", "masked": true}]
            }),
        )
        .unwrap();
        let entry_id = entry["nodes"][0]["children"][0]["id"].clone();
        let field_id = entry["nodes"][0]["children"][0]["fields"][0]["id"].clone();
        TaggedFixture {
            _directory: directory,
            state,
            vault_id,
            group_id,
            entry_id,
            field_id,
        }
    }

    #[test]
    fn tag_protocol_preserves_legacy_edits_rejects_duplicates_and_persists_updates() {
        let TaggedFixture {
            _directory,
            state,
            vault_id,
            group_id,
            entry_id,
            field_id,
        } = tagged_fixture();
        let renamed = run_command(
            &state,
            json!({"command": "rename_node", "node_id": group_id, "name": "Renamed"}),
        )
        .unwrap();
        assert_eq!(renamed["nodes"][0]["tags"], json!(["blue", "green"]));
        let updated = run_command(
            &state,
            json!({
                "command": "update_entry", "entry_id": entry_id, "name": "Updated",
                "fields": [{"id": field_id, "label": "Password", "value": "synthetic-secret", "kind": "secret", "masked": true}]
            }),
        )
        .unwrap();
        assert_eq!(updated["nodes"][0]["children"][0]["tags"], json!(["red"]));
        let before = serde_json::to_value(state.bootstrap().unwrap().current.unwrap()).unwrap();
        let duplicate = run_command(
            &state,
            json!({
                "command": "update_entry", "entry_id": entry_id, "name": "Invalid", "fields": [],
                "tags": ["yellow", "yellow"]
            }),
        );
        assert_eq!(
            duplicate.unwrap_err(),
            "tag colors must be unique on a node"
        );
        assert_eq!(
            serde_json::to_value(state.bootstrap().unwrap().current.unwrap()).unwrap(),
            before
        );
        assert_eq!(
            run_command(
                &state,
                json!({"command": "reveal_field", "entry_id": entry_id, "field_id": field_id})
            )
            .unwrap(),
            "synthetic-secret"
        );
        let mut output = Vec::new();
        let unknown = format!(
            "{}\n",
            json!({"id": 1, "command": "set_node_tags", "node_id": entry_id, "tags": ["pink"]})
        );
        serve(unknown.as_bytes(), &mut output, &state).unwrap();
        assert_eq!(
            serde_json::from_slice::<Value>(&output).unwrap()["error"],
            "invalid request"
        );
        assert_eq!(
            serde_json::to_value(state.bootstrap().unwrap().current.unwrap()).unwrap(),
            before
        );
        let updated_tags = run_command(
            &state,
            json!({"command": "rename_node", "node_id": group_id, "name": "Renamed", "tags": ["gray"]}),
        )
        .unwrap();
        assert_eq!(updated_tags["nodes"][0]["tags"], json!(["gray"]));
        let cleared = run_command(
            &state,
            json!({
                "command": "update_entry", "entry_id": entry_id, "name": "Updated", "tags": [],
                "fields": [{"id": field_id, "label": "Password", "value": "synthetic-secret", "kind": "secret", "masked": true}]
            }),
        )
        .unwrap();
        assert_eq!(cleared["nodes"][0]["children"][0]["tags"], json!([]));
        run_command(&state, json!({"command": "lock_vault"})).unwrap();
        assert_eq!(
            run_command(
                &state,
                json!({"command": "set_node_tags", "node_id": group_id, "tags": []})
            )
            .unwrap_err(),
            "a vault must be unlocked first"
        );
        let reopened = run_command(
            &state,
            json!({"command": "unlock_vault", "vault_id": vault_id, "password": "password123"}),
        )
        .unwrap();
        assert_eq!(reopened, cleared);
        assert_eq!(
            run_command(
                &state,
                json!({"command": "reveal_field", "entry_id": entry_id, "field_id": field_id})
            )
            .unwrap(),
            "synthetic-secret"
        );
    }

    #[test]
    fn pipe_protocol_rejects_actions_after_lock() {
        let directory = tempfile::tempdir().unwrap();
        let state = Arc::new(AppState::new(
            AppStorage::new(directory.path(), directory.path()).unwrap(),
            AppConfig::default(),
        ));
        let request = b"{\"id\":1,\"command\":\"create_vault\",\"name\":\"Test\",\"password\":\"password123\"}\n{\"id\":2,\"command\":\"lock_vault\"}\n{\"id\":3,\"command\":\"add_group\",\"name\":\"Blocked\"}\n";
        let mut output = Vec::new();
        serve(&request[..], &mut output, &state).unwrap();
        let responses: Vec<Value> = String::from_utf8(output)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert!(responses[0]["result"]["id"].is_string());
        assert_eq!(responses[2]["error"], "a vault must be unlocked first");
        assert!(state.bootstrap().unwrap().current.is_none());
    }
}
