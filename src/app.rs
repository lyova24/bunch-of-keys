use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use serde::Serialize;
use ssh_key::PrivateKey;
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::{
    core::{
        BiometricCredential, FieldKind, SshConnection, UnlockedVault, VaultData, VaultEnvelope,
    },
    ssh_session::{EphemeralAgent, SshSessionError, TerminalLauncher, monitor_terminal},
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
    last_activity: Mutex<Instant>,
    active_ssh: Mutex<HashMap<(Uuid, Uuid), ActiveSshSession>>,
    biometric_request: Mutex<Option<BiometricRequest>>,
}

struct BiometricRequest {
    vault_id: Uuid,
    ticket: Uuid,
    started: Instant,
}

struct ActiveSshSession {
    id: Uuid,
    agent: EphemeralAgent,
}

#[derive(Debug, Clone, Serialize)]
pub struct SshSessionEnded {
    entry_id: Uuid,
    field_id: Uuid,
}

#[derive(Debug, Serialize)]
pub struct Bootstrap {
    pub vaults: Vec<VaultSummary>,
    pub settings: Settings,
    pub current: Option<VaultView>,
    pub active_ssh: Vec<SshSessionEnded>,
}

#[derive(Debug, Clone, Serialize)]
pub struct VaultSummary {
    pub id: Uuid,
    pub name: String,
}

#[derive(Debug, Error)]
pub enum AppError {
    #[error("application state is unavailable")]
    StateUnavailable,
    #[error("a vault must be unlocked first")]
    Locked,
    #[error("vault does not exist")]
    VaultNotFound,
    #[error("a vault with this name already exists")]
    DuplicateVaultName,
    #[error("vault name must contain between 1 and 80 characters without control characters")]
    InvalidVaultName,
    #[error("master password must contain at least 8 characters")]
    WeakPassword,
    #[error("new password and confirmation do not match")]
    PasswordConfirmationMismatch,
    #[error("choose a new password different from the current password")]
    UnchangedPassword,
    #[error("vault metadata does not match the encrypted file")]
    VaultIdMismatch,
    #[error("Touch ID request expired or was cancelled. Try again or use the master password.")]
    InvalidBiometricRequest,
    #[error(transparent)]
    Storage(#[from] StorageError),
    #[error(transparent)]
    Crypto(#[from] crate::core::CryptoError),
    #[error(transparent)]
    Model(#[from] crate::core::ModelError),
    #[error(transparent)]
    Import(#[from] crate::core::ImportError),
    #[error("URL fields must use http:// or https://")]
    InvalidUrl,
    #[error("SSH field is incomplete or unavailable")]
    InvalidSshField,
    #[error("SSH key passphrase is required")]
    SshPassphraseRequired,
    #[error("SSH key passphrase is incorrect")]
    InvalidSshPassphrase,
    #[error("this SSH connection is already active")]
    SshSessionActive,
    #[error(transparent)]
    SshSession(#[from] SshSessionError),
}

impl AppState {
    pub fn new(storage: AppStorage, config: AppConfig) -> Self {
        Self {
            storage,
            config: Mutex::new(config),
            session: Mutex::new(None),
            last_activity: Mutex::new(Instant::now()),
            active_ssh: Mutex::new(HashMap::new()),
            biometric_request: Mutex::new(None),
        }
    }

    pub fn touch(&self) {
        if let Ok(mut last) = self.last_activity.lock() {
            *last = Instant::now();
        }
    }

    pub fn spawn_idle_monitor(self: &Arc<Self>) {
        let state = Arc::downgrade(self);
        thread::spawn(move || {
            loop {
                thread::sleep(Duration::from_secs(1));
                let Some(state) = state.upgrade() else {
                    break;
                };
                state.expire_if_idle();
            }
        });
    }

    fn expire_if_idle(&self) -> bool {
        let timeout = self
            .config
            .lock()
            .map_or(300, |config| config.settings.auto_lock_seconds);
        let elapsed = self
            .last_activity
            .lock()
            .map_or(timeout, |last| last.elapsed().as_secs());
        elapsed >= timeout && self.lock()
    }

    pub fn lock(&self) -> bool {
        if let Ok(mut request) = self.biometric_request.lock() {
            *request = None;
        }
        self.stop_ssh_sessions();
        self.session
            .lock()
            .is_ok_and(|mut session| session.take().is_some())
    }

    fn stop_ssh_sessions(&self) {
        let sessions = self
            .active_ssh
            .lock()
            .map(|mut active| std::mem::take(&mut *active))
            .unwrap_or_default();
        for session in sessions.into_values() {
            session.agent.stop();
        }
    }

    pub fn bootstrap(&self) -> Result<Bootstrap, AppError> {
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
            active_ssh: self
                .active_ssh
                .lock()
                .map_err(|_| AppError::StateUnavailable)?
                .iter()
                .filter(|(_, session)| !session.agent.is_finished())
                .map(|((entry_id, field_id), _)| SshSessionEnded {
                    entry_id: *entry_id,
                    field_id: *field_id,
                })
                .collect(),
        })
    }

    pub fn create_vault(&self, name: &str, password: &[u8]) -> Result<VaultView, AppError> {
        self.lock();
        self.touch();
        let name = validate_vault_name(name)?;
        validate_password(password)?;

        let mut config = self.config.lock().map_err(|_| AppError::StateUnavailable)?;
        if config
            .vaults
            .iter()
            .any(|record| same_vault_name(&record.name, &name))
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

    pub fn unlock_vault(&self, vault_id: Uuid, password: &[u8]) -> Result<VaultView, AppError> {
        self.lock();
        self.touch();
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

    pub fn rename_vault(&self, vault_id: Uuid, name: &str) -> Result<VaultSummary, AppError> {
        let name = validate_vault_name(name)?;
        // Match bootstrap's config -> session lock order. No visible state is
        // changed until the registry has been committed successfully.
        let mut config = self.config.lock().map_err(|_| AppError::StateUnavailable)?;
        let mut session = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let current = session
            .as_mut()
            .filter(|s| s.record.id == vault_id)
            .ok_or(AppError::Locked)?;
        if config
            .vaults
            .iter()
            .any(|record| record.id != vault_id && same_vault_name(&record.name, &name))
        {
            return Err(AppError::DuplicateVaultName);
        }
        if current.record.name == name {
            return Ok(VaultSummary::from(&current.record));
        }
        let mut next = config.clone();
        let record = next
            .vaults
            .iter_mut()
            .find(|record| record.id == vault_id)
            .ok_or(AppError::VaultNotFound)?;
        record.name = name;
        let record = record.clone();
        self.storage.save_config(&next)?;
        *config = next;
        current.record = record;
        self.touch();
        Ok(VaultSummary::from(&current.record))
    }

    pub fn change_master_password(
        &self,
        vault_id: Uuid,
        current_password: &[u8],
        new_password: &[u8],
        confirmation: &[u8],
    ) -> Result<(), AppError> {
        validate_password(new_password)?;
        if new_password != confirmation {
            return Err(AppError::PasswordConfirmationMismatch);
        }
        if new_password == current_password {
            return Err(AppError::UnchangedPassword);
        }
        // Serialize with lock/biometric unlock; a stale form can never target
        // whichever vault happens to be open when the request is received.
        let mut pending = self
            .biometric_request
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let mut session = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let current = session
            .as_ref()
            .filter(|s| s.record.id == vault_id)
            .ok_or(AppError::Locked)?;
        let next = current
            .vault
            .prepare_password_change(current_password, new_password)?;
        self.storage
            .write_vault(&current.record, &next.to_bytes()?)?;
        // Only a successful atomic write invalidates the session and old
        // biometric binding. On failure the previous session stays usable.
        *session = None;
        *pending = None;
        drop(session);
        drop(pending);
        self.stop_ssh_sessions();
        Ok(())
    }

    fn biometric_envelope(&self, vault_id: Uuid) -> Result<(VaultRecord, VaultEnvelope), AppError> {
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
        if envelope.vault_id() != vault_id {
            return Err(AppError::VaultIdMismatch);
        }
        Ok((record, envelope))
    }

    pub fn biometric_binding(&self, vault_id: Uuid) -> Result<String, AppError> {
        Ok(self.biometric_envelope(vault_id)?.1.biometric_binding()?)
    }

    pub fn enroll_biometric(
        &self,
        vault_id: Uuid,
        password: &[u8],
    ) -> Result<BiometricCredential, AppError> {
        let session = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let current = session
            .as_ref()
            .filter(|s| s.record.id == vault_id)
            .ok_or(AppError::Locked)?;
        // Verify the current on-disk wrapping, not a stale in-memory envelope.
        let envelope = VaultEnvelope::from_bytes(&self.storage.read_vault(&current.record)?)?;
        if envelope.vault_id() != vault_id {
            return Err(AppError::VaultIdMismatch);
        }
        self.touch();
        Ok(envelope.biometric_credential(password)?)
    }

    pub fn begin_biometric_unlock(&self, vault_id: Uuid) -> Result<Uuid, AppError> {
        self.lock();
        self.biometric_envelope(vault_id)?;
        self.touch();
        let ticket = Uuid::new_v4();
        *self
            .biometric_request
            .lock()
            .map_err(|_| AppError::StateUnavailable)? = Some(BiometricRequest {
            vault_id,
            ticket,
            started: Instant::now(),
        });
        Ok(ticket)
    }

    pub fn unlock_biometric(
        &self,
        vault_id: Uuid,
        ticket: Uuid,
        credential: &BiometricCredential,
    ) -> Result<VaultView, AppError> {
        // The lock also serializes installation of the session against locking.
        let mut pending = self
            .biometric_request
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let request = pending
            .take()
            .filter(|r| {
                r.vault_id == vault_id
                    && r.ticket == ticket
                    && r.started.elapsed() < Duration::from_secs(60)
            })
            .ok_or(AppError::InvalidBiometricRequest)?;
        let (record, envelope) = self.biometric_envelope(request.vault_id)?;
        let vault = envelope.unlock_biometric(credential)?;
        let view = VaultView::from_data(vault_id, vault.data());
        *self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)? = Some(Session { record, vault });
        self.touch();
        Ok(view)
    }

    pub fn mutate<F>(&self, operation: F) -> Result<VaultView, AppError>
    where
        F: FnOnce(&mut VaultData) -> Result<(), AppError>,
    {
        self.mutate_current(None, operation)
    }

    pub fn set_tag_names(
        &self,
        vault_id: Uuid,
        names: std::collections::BTreeMap<crate::core::TagColor, String>,
    ) -> Result<VaultView, AppError> {
        self.mutate_current(Some(vault_id), |data| {
            data.set_tag_names(names)?;
            Ok(())
        })
    }

    pub fn set_tray_tags(
        &self,
        vault_id: Uuid,
        tags: Vec<crate::core::TagColor>,
    ) -> Result<VaultView, AppError> {
        self.mutate_current(Some(vault_id), |data| {
            data.set_tray_tags(tags)?;
            Ok(())
        })
    }

    fn mutate_current<F>(
        &self,
        expected_vault: Option<Uuid>,
        operation: F,
    ) -> Result<VaultView, AppError>
    where
        F: FnOnce(&mut VaultData) -> Result<(), AppError>,
    {
        let mut session_guard = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let session = session_guard
            .as_mut()
            .filter(|session| expected_vault.is_none_or(|id| id == session.record.id))
            .ok_or(AppError::Locked)?;
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

    pub fn field_value(&self, entry_id: Uuid, field_id: Uuid) -> Result<String, AppError> {
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

    pub fn open_url(&self, entry_id: Uuid, field_id: Uuid) -> Result<String, AppError> {
        let url = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?
            .as_ref()
            .ok_or(AppError::Locked)?
            .vault
            .data()
            .field(entry_id, field_id)
            .filter(|field| field.kind == FieldKind::Url)
            .map(|field| field.value.trim().to_owned())
            .ok_or(AppError::InvalidUrl)?;
        if !valid_external_url(&url) {
            return Err(AppError::InvalidUrl);
        }
        Ok(url)
    }

    pub fn connect_ssh(
        self: &Arc<Self>,
        entry_id: Uuid,
        field_id: Uuid,
        passphrase: Option<&str>,
    ) -> Result<(), AppError> {
        let (connection, private_key, key_name) = self.ssh_connection(entry_id, field_id)?;
        let mut active = self
            .active_ssh
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        active.retain(|_, session| !session.agent.is_finished());
        if active.contains_key(&(entry_id, field_id)) {
            return Err(AppError::SshSessionActive);
        }

        let private_key = unlock_ssh_private_key(private_key.as_str(), passphrase)?;

        let agent = EphemeralAgent::start(private_key, key_name)?;
        let terminal = TerminalLauncher::detect()?;
        let child = terminal.launch_ssh(
            agent.socket_path(),
            agent.identity_path(),
            &connection.user,
            &connection.address,
            connection.port,
        )?;
        let session_key = (entry_id, field_id);
        let session_id = Uuid::new_v4();
        let cancel = agent.cancellation_sender();
        let socket_path = agent.socket_path().to_owned();
        active.insert(
            session_key,
            ActiveSshSession {
                id: session_id,
                agent,
            },
        );
        drop(active);
        let state = Arc::downgrade(self);
        monitor_terminal(child, cancel, socket_path, move || {
            if let Some(state) = state.upgrade()
                && let Ok(mut active) = state.active_ssh.lock()
                && active
                    .get(&session_key)
                    .is_some_and(|session| session.id == session_id)
            {
                active.remove(&session_key);
            }
        });
        Ok(())
    }

    fn ssh_connection(
        &self,
        entry_id: Uuid,
        field_id: Uuid,
    ) -> Result<(SshConnection, Zeroizing<String>, String), AppError> {
        let session = self
            .session
            .lock()
            .map_err(|_| AppError::StateUnavailable)?;
        let data = session.as_ref().ok_or(AppError::Locked)?.vault.data();
        let field = data
            .field(entry_id, field_id)
            .ok_or(AppError::InvalidSshField)?;
        if field.kind != FieldKind::Ssh {
            return Err(AppError::InvalidSshField);
        }
        let connection = field.ssh.clone().ok_or(AppError::InvalidSshField)?;
        let key = data
            .ssh_key(connection.key_id)
            .ok_or(AppError::InvalidSshField)?;
        Ok((
            connection,
            Zeroizing::new(key.private_key.clone()),
            key.name.clone(),
        ))
    }

    pub fn save_settings(&self, settings: Settings) -> Result<(), AppError> {
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
    if name.is_empty() || name.chars().count() > 80 || name.chars().any(char::is_control) {
        return Err(AppError::InvalidVaultName);
    }
    Ok(name.to_owned())
}

fn same_vault_name(left: &str, right: &str) -> bool {
    left.to_lowercase() == right.to_lowercase()
}

fn validate_password(password: &[u8]) -> Result<(), AppError> {
    let password = std::str::from_utf8(password).map_err(|_| AppError::WeakPassword)?;
    if password.chars().count() < MIN_PASSWORD_CHARS {
        return Err(AppError::WeakPassword);
    }
    Ok(())
}

fn unlock_ssh_private_key(encoded: &str, passphrase: Option<&str>) -> Result<PrivateKey, AppError> {
    let parsed =
        PrivateKey::from_openssh(encoded.as_bytes()).map_err(|_| AppError::InvalidSshField)?;
    if !parsed.is_encrypted() {
        return Ok(parsed);
    }
    let passphrase = passphrase
        .filter(|value| !value.is_empty())
        .ok_or(AppError::SshPassphraseRequired)?;
    parsed
        .decrypt(passphrase.as_bytes())
        .map_err(|_| AppError::InvalidSshPassphrase)
}

fn valid_external_url(url: &str) -> bool {
    let Some(remainder) = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
    else {
        return false;
    };
    let authority = remainder.split(['/', '?', '#']).next().unwrap_or_default();
    !authority.is_empty() && !url.chars().any(char::is_whitespace)
}

#[cfg(test)]
mod tests {
    use ssh_key::{Algorithm, LineEnding, PrivateKey, rand_core::OsRng};
    use tempfile::tempdir;

    use super::*;
    use crate::core::FieldInput;

    #[test]
    fn inactivity_expires_the_session_and_activity_resets_the_deadline() {
        let directory = tempdir().unwrap();
        let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
        let state = AppState::new(storage, AppConfig::default());
        state.create_vault("Idle", b"test-password").unwrap();
        *state.last_activity.lock().unwrap() = Instant::now()
            .checked_sub(Duration::from_secs(301))
            .unwrap();
        state.touch();
        assert!(!state.expire_if_idle());
        *state.last_activity.lock().unwrap() = Instant::now()
            .checked_sub(Duration::from_secs(301))
            .unwrap();
        assert!(state.expire_if_idle());
        assert!(state.bootstrap().unwrap().current.is_none());
    }

    #[test]
    fn accepts_master_passwords_from_eight_characters() {
        assert!(validate_password(b"12345678").is_ok());
        assert!(validate_password(b"1234567").is_err());
    }

    #[test]
    fn biometric_tickets_expire_and_cannot_cross_vaults_or_service_restarts() {
        let directory = tempdir().unwrap();
        let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
        let state = AppState::new(storage.clone(), AppConfig::default());
        let first = state.create_vault("First", b"test-password").unwrap().id;
        let credential = state.enroll_biometric(first, b"test-password").unwrap();
        let second = state.create_vault("Second", b"other-password").unwrap().id;
        let ticket = state.begin_biometric_unlock(first).unwrap();
        state
            .biometric_request
            .lock()
            .unwrap()
            .as_mut()
            .unwrap()
            .started -= Duration::from_secs(61);
        assert!(state.unlock_biometric(first, ticket, &credential).is_err());
        let ticket = state.begin_biometric_unlock(second).unwrap();
        assert!(state.unlock_biometric(second, ticket, &credential).is_err());
        assert!(state.bootstrap().unwrap().current.is_none());
        let ticket = state.begin_biometric_unlock(first).unwrap();
        let restarted = AppState::new(storage.clone(), storage.load_config().unwrap());
        assert!(
            restarted
                .unlock_biometric(first, ticket, &credential)
                .is_err()
        );
        let fresh = restarted.begin_biometric_unlock(first).unwrap();
        assert_eq!(
            restarted
                .unlock_biometric(first, fresh, &credential)
                .unwrap()
                .id,
            first
        );
    }

    #[test]
    fn external_urls_are_limited_to_valid_http_destinations() {
        assert!(valid_external_url("https://example.com/path"));
        assert!(valid_external_url("http://localhost:8080"));
        assert!(!valid_external_url("javascript:alert(1)"));
        assert!(!valid_external_url("https:///missing-host"));
        assert!(!valid_external_url("https://example.com/bad path"));
    }

    #[test]
    fn encrypted_ssh_keys_require_the_correct_in_memory_passphrase() {
        let encrypted = PrivateKey::random(&mut OsRng, Algorithm::Ed25519)
            .unwrap()
            .encrypt(&mut OsRng, b"correct horse")
            .unwrap()
            .to_openssh(LineEnding::LF)
            .unwrap();

        assert!(matches!(
            unlock_ssh_private_key(encrypted.as_str(), None),
            Err(AppError::SshPassphraseRequired)
        ));
        assert!(matches!(
            unlock_ssh_private_key(encrypted.as_str(), Some("wrong")),
            Err(AppError::InvalidSshPassphrase)
        ));
        assert!(unlock_ssh_private_key(encrypted.as_str(), Some("correct horse")).is_ok());
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
                        tags: None,
                        id: None,
                        label: "Token".to_owned(),
                        value: "synthetic-test-value".to_owned(),
                        kind: crate::core::FieldKind::Secret,
                        masked: true,
                        ssh: None,
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

    #[test]
    fn locking_the_vault_stops_active_ephemeral_ssh_agents() {
        let directory = tempdir().unwrap();
        let storage = AppStorage::new(
            directory.path().join("config"),
            directory.path().join("data"),
        )
        .unwrap();
        let state = AppState::new(storage, AppConfig::default());
        state
            .create_vault("Work", b"a sufficiently long password")
            .unwrap();
        let key = PrivateKey::random(&mut OsRng, Algorithm::Ed25519).unwrap();
        let agent = EphemeralAgent::start_for_test(&directory.path().join("runtime"), key).unwrap();
        let socket = agent.socket_path().to_owned();
        state.active_ssh.lock().unwrap().insert(
            (Uuid::new_v4(), Uuid::new_v4()),
            ActiveSshSession {
                id: Uuid::new_v4(),
                agent,
            },
        );

        assert!(state.lock());

        assert!(!socket.exists());
        assert!(state.active_ssh.lock().unwrap().is_empty());
    }
}

#[cfg(test)]
#[path = "app/vault_management_tests.rs"]
mod vault_management_tests;
