use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
};

use directories::BaseDirs;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

const CONFIG_VERSION: u16 = 1;
const MAX_CONFIG_BYTES: u64 = 1024 * 1024;
const MAX_VAULT_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub autostart: bool,
    #[serde(default = "default_appearance")]
    pub appearance: String,
    #[serde(default = "default_liquid_glass")]
    pub liquid_glass: bool,
    #[serde(default = "default_auto_lock_seconds")]
    pub auto_lock_seconds: u64,
    #[serde(default = "default_clipboard_clear_seconds")]
    pub clipboard_clear_seconds: u64,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            autostart: false,
            appearance: default_appearance(),
            liquid_glass: default_liquid_glass(),
            auto_lock_seconds: default_auto_lock_seconds(),
            clipboard_clear_seconds: default_clipboard_clear_seconds(),
        }
    }
}

impl Settings {
    pub fn validate(&self) -> Result<(), StorageError> {
        if !["system", "light", "dark"].contains(&self.appearance.as_str())
            || !(60..=86_400).contains(&self.auto_lock_seconds)
            || !(5..=3_600).contains(&self.clipboard_clear_seconds)
        {
            return Err(StorageError::InvalidSettings);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultRecord {
    pub id: Uuid,
    pub name: String,
    pub file_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub version: u16,
    #[serde(default)]
    pub settings: Settings,
    #[serde(default)]
    pub vaults: Vec<VaultRecord>,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            version: CONFIG_VERSION,
            settings: Settings::default(),
            vaults: Vec::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct AppStorage {
    config_file: PathBuf,
    vault_dir: PathBuf,
}

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("another Keepy service is already using this data directory")]
    AlreadyRunning,
    #[error("the platform does not provide a user data directory")]
    NoHomeDirectory,
    #[error("cannot create an application directory: {0}")]
    CreateDirectory(#[source] std::io::Error),
    #[error("cannot read application data: {0}")]
    Read(#[source] std::io::Error),
    #[error("application data is too large")]
    TooLarge,
    #[error("application configuration is invalid: {0}")]
    InvalidConfig(#[source] serde_json::Error),
    #[error("application configuration has an unsupported version")]
    UnsupportedConfig,
    #[error("application settings are invalid")]
    InvalidSettings,
    #[error("vault metadata is invalid")]
    InvalidVaultMetadata,
    #[error("cannot encode application data: {0}")]
    Encode(#[source] serde_json::Error),
    #[error("cannot write application data: {0}")]
    Write(#[source] std::io::Error),
}

impl AppStorage {
    pub fn discover() -> Result<Self, StorageError> {
        let base = BaseDirs::new().ok_or(StorageError::NoHomeDirectory)?;
        Self::new(
            base.config_dir().join("bunch-of-keys"),
            base.data_local_dir().join("bunch-of-keys"),
        )
    }

    pub fn new(
        config_dir: impl Into<PathBuf>,
        data_dir: impl Into<PathBuf>,
    ) -> Result<Self, StorageError> {
        let config_dir = config_dir.into();
        let data_dir = data_dir.into();
        let vault_dir = data_dir.join("vaults");
        create_private_dir(&config_dir)?;
        create_private_dir(&data_dir)?;
        create_private_dir(&vault_dir)?;
        Ok(Self {
            config_file: config_dir.join("config.json"),
            vault_dir,
        })
    }

    pub fn lock_instance(&self) -> Result<File, StorageError> {
        use std::os::unix::fs::OpenOptionsExt;
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(self.config_file.with_file_name(".instance.lock"))
            .map_err(StorageError::Write)?;
        file.try_lock().map_err(|_| StorageError::AlreadyRunning)?;
        Ok(file)
    }

    pub fn load_config(&self) -> Result<AppConfig, StorageError> {
        if !self.config_file.exists() {
            return Ok(AppConfig::default());
        }
        let bytes = read_limited(&self.config_file, MAX_CONFIG_BYTES)?;
        let config: AppConfig =
            serde_json::from_slice(&bytes).map_err(StorageError::InvalidConfig)?;
        validate_config(&config)?;
        Ok(config)
    }

    pub fn save_config(&self, config: &AppConfig) -> Result<(), StorageError> {
        validate_config(config)?;
        let bytes = serde_json::to_vec_pretty(config).map_err(StorageError::Encode)?;
        write_atomic(&self.config_file, &bytes)
    }

    pub fn read_vault(&self, record: &VaultRecord) -> Result<Vec<u8>, StorageError> {
        validate_record(record)?;
        read_limited(&self.vault_dir.join(&record.file_name), MAX_VAULT_BYTES)
    }

    pub fn write_vault(&self, record: &VaultRecord, bytes: &[u8]) -> Result<(), StorageError> {
        validate_record(record)?;
        if bytes.len() as u64 > MAX_VAULT_BYTES {
            return Err(StorageError::TooLarge);
        }
        write_atomic(&self.vault_dir.join(&record.file_name), bytes)
    }

    pub fn remove_vault(&self, record: &VaultRecord) {
        if validate_record(record).is_ok() {
            let _ = fs::remove_file(self.vault_dir.join(&record.file_name));
        }
    }
}

fn default_appearance() -> String {
    "system".to_owned()
}
fn default_liquid_glass() -> bool {
    true
}

fn default_auto_lock_seconds() -> u64 {
    300
}

fn default_clipboard_clear_seconds() -> u64 {
    30
}

fn validate_config(config: &AppConfig) -> Result<(), StorageError> {
    if config.version != CONFIG_VERSION {
        return Err(StorageError::UnsupportedConfig);
    }
    config.settings.validate()?;
    for record in &config.vaults {
        validate_record(record)?;
    }
    Ok(())
}

fn validate_record(record: &VaultRecord) -> Result<(), StorageError> {
    let name = record.name.trim();
    if name.is_empty()
        || name.chars().count() > 80
        || record.file_name != format!("{}.bok", record.id)
    {
        return Err(StorageError::InvalidVaultMetadata);
    }
    Ok(())
}

fn create_private_dir(path: &Path) -> Result<(), StorageError> {
    fs::create_dir_all(path).map_err(StorageError::CreateDirectory)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .map_err(StorageError::CreateDirectory)?;
    }
    Ok(())
}

fn read_limited(path: &Path, max_bytes: u64) -> Result<Vec<u8>, StorageError> {
    let mut file = File::open(path).map_err(StorageError::Read)?;
    let metadata = file.metadata().map_err(StorageError::Read)?;
    if metadata.len() > max_bytes {
        return Err(StorageError::TooLarge);
    }
    let capacity = usize::try_from(metadata.len()).map_err(|_| StorageError::TooLarge)?;
    let mut bytes = Vec::with_capacity(capacity);
    file.read_to_end(&mut bytes).map_err(StorageError::Read)?;
    Ok(bytes)
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), StorageError> {
    let parent = path.parent().ok_or(StorageError::InvalidVaultMetadata)?;
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or(StorageError::InvalidVaultMetadata)?;
    let temporary = parent.join(format!(".{file_name}.{}.tmp", Uuid::new_v4()));

    let result = (|| {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&temporary).map_err(StorageError::Write)?;
        file.write_all(bytes).map_err(StorageError::Write)?;
        file.sync_all().map_err(StorageError::Write)?;
        fs::rename(&temporary, path).map_err(StorageError::Write)?;
        File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(StorageError::Write)?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn legacy_settings_keep_defaults_for_native_preferences() {
        let settings: Settings = serde_json::from_str(
            r#"{"autostart":true,"auto_lock_seconds":300,"clipboard_clear_seconds":30}"#,
        )
        .unwrap();
        assert_eq!(settings.appearance, "system");
        assert!(settings.liquid_glass);
        assert!(settings.autostart);
    }

    #[test]
    fn instance_lock_prevents_two_writers_and_releases_on_exit() {
        let directory = tempdir().unwrap();
        let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
        let lock = storage.lock_instance().unwrap();
        assert!(matches!(
            storage.lock_instance(),
            Err(StorageError::AlreadyRunning)
        ));
        drop(lock);
        assert!(storage.lock_instance().is_ok());
    }

    #[test]
    fn round_trips_configuration_and_vault_bytes() {
        let directory = tempdir().unwrap();
        let storage = AppStorage::new(
            directory.path().join("config"),
            directory.path().join("data"),
        )
        .unwrap();
        let id = Uuid::new_v4();
        let record = VaultRecord {
            id,
            name: "Personal".to_owned(),
            file_name: format!("{id}.bok"),
        };
        let config = AppConfig {
            version: CONFIG_VERSION,
            settings: Settings::default(),
            vaults: vec![record.clone()],
        };

        storage.save_config(&config).unwrap();
        storage.write_vault(&record, b"encrypted").unwrap();

        assert_eq!(storage.load_config().unwrap().vaults[0].id, id);
        assert_eq!(storage.read_vault(&record).unwrap(), b"encrypted");
    }
}
