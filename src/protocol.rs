use crate::{
    app::AppState,
    core::{FieldInput, import_yaml},
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
    AddGroup {
        parent_id: Option<Uuid>,
        name: String,
        index: Option<usize>,
    },
    AddEntry {
        parent_id: Option<Uuid>,
        name: String,
        fields: Vec<FieldInput>,
        index: Option<usize>,
    },
    UpdateEntry {
        entry_id: Uuid,
        name: String,
        fields: Vec<FieldInput>,
    },
    RenameNode {
        node_id: Uuid,
        name: String,
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
                } => {
                    let id = data.add_group(parent_id, &name)?;
                    if let Some(index) = index {
                        data.move_node(id, parent_id, index)?;
                    }
                }
                Command::AddEntry {
                    parent_id,
                    name,
                    fields,
                    index,
                } => {
                    let id = data.add_entry(parent_id, &name, fields)?;
                    if let Some(index) = index {
                        data.move_node(id, parent_id, index)?;
                    }
                }
                Command::UpdateEntry {
                    entry_id,
                    name,
                    fields,
                } => {
                    data.replace_entry(entry_id, &name, fields)?;
                }
                Command::RenameNode { node_id, name } => {
                    data.rename_node(node_id, &name)?;
                }
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

pub fn serve(
    mut input: impl BufRead,
    mut output: impl Write,
    state: &Arc<AppState>,
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
        let response = match serde_json::from_slice::<Request>(&bytes) {
            Ok(request) => match execute(state, request.command) {
                Ok(value) => json!({"id": request.id, "result": value}),
                Err(error) => json!({"id": request.id, "error": error}),
            },
            Err(_) => json!({"id": 0, "error": "invalid request"}),
        };
        let mut encoded = serde_json::to_vec(&response)?;
        output.write_all(&encoded)?;
        output.write_all(b"\n")?;
        output.flush()?;
        encoded.zeroize();
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{AppConfig, AppStorage};
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
