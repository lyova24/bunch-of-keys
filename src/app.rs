#![allow(clippy::needless_pass_by_value)] // Tauri commands deserialize owned IPC arguments.

use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    thread,
    time::Duration,
};

use serde::Serialize;
use tauri::{AppHandle, Emitter, LogicalSize, Manager, State};
use tauri_plugin_autostart::ManagerExt;
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::{
    core::{FieldInput, UnlockedVault, VaultData, VaultEnvelope, import_yaml},
    storage::{AppConfig, AppStorage, Settings, StorageError, VaultRecord},
    view::VaultView,
};

const MIN_PASSWORD_CHARS: usize = 8;

struct Session {
    record: VaultRecord,
    vault: UnlockedVault,
}

pub struct AppState {
    storage: AppStorage,
    config: Mutex<AppConfig>,
    session: Mutex<Option<Session>>,
    clipboard_generation: Arc<AtomicU64>,
}

#[derive(Debug, Serialize)]
pub struct Bootstrap {
    pub vaults: Vec<VaultSummary>,
    pub settings: Settings,
    pub current: Option<VaultView>,
}

#[derive(Debug, Clone, Serialize)]
pub struct VaultSummary {
    pub id: Uuid,
    pub name: String,
}

#[derive(Debug, Error)]
enum AppError {
    #[error("application state is unavailable")]
    StateUnavailable,
    #[error("a vault must be unlocked first")]
    Locked,
    #[error("vault does not exist")]
    VaultNotFound,
    #[error("a vault with this name already exists")]
    DuplicateVaultName,
    #[error("vault name must contain between 1 and 80 characters")]
    InvalidVaultName,
    #[error("master password must contain at least 8 characters")]
    WeakPassword,
    #[error("vault metadata does not match the encrypted file")]
    VaultIdMismatch,
    #[error(transparent)]
    Storage(#[from] StorageError),
    #[error(transparent)]
    Crypto(#[from] crate::core::CryptoError),
    #[error(transparent)]
    Model(#[from] crate::core::ModelError),
    #[error(transparent)]
    Import(#[from] crate::core::ImportError),
    #[error("clipboard is unavailable: {0}")]
    Clipboard(String),
    #[error("autostart could not be changed: {0}")]
    Autostart(String),
}

type CommandResult<T> = Result<T, String>;

impl AppState {
    pub fn new(storage: AppStorage, config: AppConfig) -> Self {
        Self {
            storage,
            config: Mutex::new(config),
            session: Mutex::new(None),
            clipboard_generation: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn lock(&self) -> bool {
        self.session
            .lock()
            .is_ok_and(|mut session| session.take().is_some())
    }

    fn bootstrap(&self) -> Result<Bootstrap, AppError> {
        let config = self.config.lock().map_err(|_| AppError::StateUnavailable)?;
        let current = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?
            .as_ref()
            .map(|session| VaultView::from_data(session.vault.vault_id(), session.vault.data()));
        Ok(Bootstrap {
            vaults: config.vaults.iter().map(VaultSummary::from).collect(),
            settings: config.settings.clone(),
            current,
        })
    }

    fn create_vault(&self, name: &str, password: &[u8]) -> Result<VaultView, AppError> {
        let name = validate_vault_name(name)?;
        validate_password(password)?;

        let mut config = self.config.lock().map_err(|_| AppError::StateUnavailable)?;
        if config
            .vaults
            .iter()
            .any(|record| record.name.eq_ignore_ascii_case(&name))
        {
            return Err(AppError::DuplicateVaultName);
        }

        let vault = VaultEnvelope::create(password, VaultData::default())?;
        let id = vault.vault_id();
        let record = VaultRecord {
            id,
            name,
            file_name: format!("{id}.bok"),
        };
        self.storage
            .write_vault(&record, &vault.envelope().to_bytes()?)?;
        config.vaults.push(record.clone());
        if let Err(error) = self.storage.save_config(&config) {
            config.vaults.retain(|candidate| candidate.id != id);
            self.storage.remove_vault(&record);
            return Err(error.into());
        }
        drop(config);

        let view = VaultView::from_data(id, vault.data());
        *self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)? = Some(Session { record, vault });
        Ok(view)
    }

    fn unlock_vault(&self, vault_id: Uuid, password: &[u8]) -> Result<VaultView, AppError> {
        let record = self
            .config
            .lock()
            .map_err(|_| AppError::StateUnavailable)?
            .vaults
            .iter()
            .find(|record| record.id == vault_id)
            .cloned()
            .ok_or(AppError::VaultNotFound)?;
        let envelope = VaultEnvelope::from_bytes(&self.storage.read_vault(&record)?)?;
        if envelope.vault_id() != record.id {
            return Err(AppError::VaultIdMismatch);
        }
        let vault = envelope.unlock(password)?;
        let view = VaultView::from_data(vault_id, vault.data());
        *self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)? = Some(Session { record, vault });
        Ok(view)
    }

    fn mutate<F>(&self, operation: F) -> Result<VaultView, AppError>
    where
        F: FnOnce(&mut VaultData) -> Result<(), AppError>,
    {
        let mut session_guard = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let session = session_guard.as_mut().ok_or(AppError::Locked)?;
        let mut next_data = session.vault.data().clone();
        operation(&mut next_data)?;
        let next_envelope = session.vault.prepare_update(&next_data)?;
        self.storage
            .write_vault(&session.record, &next_envelope.to_bytes()?)?;
        session.vault.commit(next_data, next_envelope);
        Ok(VaultView::from_data(
            session.vault.vault_id(),
            session.vault.data(),
        ))
    }

    fn field_value(&self, entry_id: Uuid, field_id: Uuid) -> Result<String, AppError> {
        self.session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?
            .as_ref()
            .ok_or(AppError::Locked)?
            .vault
            .data()
            .field(entry_id, field_id)
            .map(|field| field.value.clone())
            .ok_or(AppError::Model(crate::core::ModelError::NodeNotFound))
    }

    fn copy_field(&self, entry_id: Uuid, field_id: Uuid) -> Result<(), AppError> {
        let value = Zeroizing::new(self.field_value(entry_id, field_id)?);
        let mut clipboard =
            arboard::Clipboard::new().map_err(|error| AppError::Clipboard(error.to_string()))?;
        clipboard
            .set_text(value.as_str())
            .map_err(|error| AppError::Clipboard(error.to_string()))?;

        let generation = self.clipboard_generation.fetch_add(1, Ordering::SeqCst) + 1;
        let timeout = self
            .config
            .lock()
            .map_err(|_| AppError::StateUnavailable)?
            .settings
            .clipboard_clear_seconds;
        let generation_counter = Arc::clone(&self.clipboard_generation);
        thread::spawn(move || {
            thread::sleep(Duration::from_secs(timeout));
            if generation_counter.load(Ordering::SeqCst) == generation
                && let Ok(mut clipboard) = arboard::Clipboard::new()
                && let Ok(current) = clipboard.get_text()
                && current == value.as_str()
            {
                let _ = clipboard.set_text(String::new());
            }
        });
        Ok(())
    }

    fn save_settings(&self, settings: Settings) -> Result<(), AppError> {
        settings.validate()?;
        let mut config = self.config.lock().map_err(|_| AppError::StateUnavailable)?;
        let previous = config.settings.clone();
        config.settings = settings;
        if let Err(error) = self.storage.save_config(&config) {
            config.settings = previous;
            return Err(error.into());
        }
        Ok(())
    }
}

impl From<&VaultRecord> for VaultSummary {
    fn from(record: &VaultRecord) -> Self {
        Self {
            id: record.id,
            name: record.name.clone(),
        }
    }
}

fn validate_vault_name(name: &str) -> Result<String, AppError> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 80 {
        return Err(AppError::InvalidVaultName);
    }
    Ok(name.to_owned())
}

fn validate_password(password: &[u8]) -> Result<(), AppError> {
    let password = std::str::from_utf8(password).map_err(|_| AppError::WeakPassword)?;
    if password.chars().count() < MIN_PASSWORD_CHARS {
        return Err(AppError::WeakPassword);
    }
    Ok(())
}

fn command<T>(result: Result<T, AppError>) -> CommandResult<T> {
    result.map_err(|error| error.to_string())
}

#[tauri::command]
pub fn bootstrap(state: State<'_, AppState>) -> CommandResult<Bootstrap> {
    command(state.bootstrap())
}

#[tauri::command]
pub fn create_vault(
    name: String,
    password: String,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    let password = Zeroizing::new(password);
    command(state.create_vault(&name, password.as_bytes()))
}

#[tauri::command]
pub fn unlock_vault(
    vault_id: Uuid,
    password: String,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    let password = Zeroizing::new(password);
    command(state.unlock_vault(vault_id, password.as_bytes()))
}

#[tauri::command]
pub fn lock_vault(app: AppHandle, state: State<'_, AppState>) {
    state.lock();
    let _ = app.emit("vault-locked", ());
}

#[tauri::command]
pub fn minimize_window(window: tauri::WebviewWindow) -> CommandResult<()> {
    window.minimize().map_err(|error| error.to_string())
}

#[tauri::command]
pub fn hide_window(window: tauri::WebviewWindow) -> CommandResult<()> {
    window.hide().map_err(|error| error.to_string())
}

#[tauri::command]
pub fn resize_window(width: f64, height: f64, window: tauri::WebviewWindow) -> CommandResult<()> {
    if !width.is_finite()
        || !height.is_finite()
        || !(440.0..=2_000.0).contains(&width)
        || !(480.0..=1_400.0).contains(&height)
    {
        return Err("window dimensions are outside the supported range".to_owned());
    }
    window
        .set_size(LogicalSize::new(width, height))
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn add_group(
    parent_id: Option<Uuid>,
    name: String,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.add_group(parent_id, &name)?;
        Ok(())
    }))
}

#[tauri::command]
pub fn add_entry(
    parent_id: Option<Uuid>,
    name: String,
    fields: Vec<FieldInput>,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.add_entry(parent_id, &name, fields)?;
        Ok(())
    }))
}

#[tauri::command]
pub fn update_entry(
    entry_id: Uuid,
    name: String,
    fields: Vec<FieldInput>,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.replace_entry(entry_id, &name, fields)?;
        Ok(())
    }))
}

#[tauri::command]
pub fn rename_node(
    node_id: Uuid,
    name: String,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.rename_node(node_id, &name)?;
        Ok(())
    }))
}

#[tauri::command]
pub fn delete_node(node_id: Uuid, state: State<'_, AppState>) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.delete_node(node_id)?;
        Ok(())
    }))
}

#[tauri::command]
pub fn move_node(
    node_id: Uuid,
    parent_id: Option<Uuid>,
    index: usize,
    state: State<'_, AppState>,
) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.move_node(node_id, parent_id, index)?;
        Ok(())
    }))
}

#[tauri::command]
pub fn import_yaml_file(source: String, state: State<'_, AppState>) -> CommandResult<VaultView> {
    command(state.mutate(|data| {
        data.extend_root(import_yaml(&source)?);
        Ok(())
    }))
}

#[tauri::command]
pub fn reveal_field(
    entry_id: Uuid,
    field_id: Uuid,
    state: State<'_, AppState>,
) -> CommandResult<String> {
    command(state.field_value(entry_id, field_id))
}

#[tauri::command]
pub fn copy_field(entry_id: Uuid, field_id: Uuid, state: State<'_, AppState>) -> CommandResult<()> {
    command(state.copy_field(entry_id, field_id))
}

#[tauri::command]
pub fn update_settings(
    app: AppHandle,
    settings: Settings,
    state: State<'_, AppState>,
) -> CommandResult<()> {
    settings.validate().map_err(|error| error.to_string())?;
    let autostart = app.autolaunch();
    let result = if settings.autostart {
        autostart.enable()
    } else {
        autostart.disable()
    };
    result.map_err(|error| AppError::Autostart(error.to_string()).to_string())?;
    command(state.save_settings(settings))
}

pub fn lock_and_notify(app: &AppHandle) {
    if let Some(state) = app.try_state::<AppState>()
        && state.lock()
    {
        let _ = app.emit("vault-locked", ());
    }
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn accepts_master_passwords_from_eight_characters() {
        assert!(validate_password(b"12345678").is_ok());
        assert!(validate_password(b"1234567").is_err());
    }

    #[test]
    fn creates_and_reopens_multiple_independent_vaults() {
        let directory = tempdir().unwrap();
        let storage = AppStorage::new(
            directory.path().join("config"),
            directory.path().join("data"),
        )
        .unwrap();
        let state = AppState::new(storage.clone(), AppConfig::default());

        let first = state
            .create_vault("Work", b"a sufficiently long password")
            .unwrap();
        state
            .mutate(|data| {
                data.add_entry(
                    None,
                    "Example service",
                    vec![FieldInput {
                        id: None,
                        label: "Token".to_owned(),
                        value: "synthetic-test-value".to_owned(),
                        kind: crate::core::FieldKind::Secret,
                        masked: true,
                    }],
                )?;
                Ok(())
            })
            .unwrap();
        assert!(state.lock());

        let second = state
            .create_vault("Personal", b"another sufficiently long password")
            .unwrap();
        assert_ne!(first.id, second.id);
        assert_eq!(storage.load_config().unwrap().vaults.len(), 2);

        state.lock();
        let reopened = state
            .unlock_vault(first.id, b"a sufficiently long password")
            .unwrap();
        assert_eq!(reopened.nodes.len(), 1);
    }
}
