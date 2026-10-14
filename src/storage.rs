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
    #[error(
        "both previous and Keepy data directories exist; resolve the conflict before launching"
    )]
    MigrationConflict,
    #[error("cannot migrate application data: {0}")]
    Migration(#[source] std::io::Error),
}

impl AppStorage {
    pub fn discover() -> Result<Self, StorageError> {
        let base = BaseDirs::new().ok_or(StorageError::NoHomeDirectory)?;
        let storage = Self::discover_in(base.data_local_dir())?;
        migrate_identity_artifacts(&base.home_dir().join("Library"))?;
        Ok(storage)
    }

    fn discover_in(parent: &Path) -> Result<Self, StorageError> {
        // The app is macOS-only: registry and vaults share Application Support.
        migrate_directories(parent)?;
        let root = parent.join("Keepy");
        Self::new(&root, &root)
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

fn migrate_directories(parent: &Path) -> Result<(), StorageError> {
    use std::os::unix::fs::OpenOptionsExt;
    fs::create_dir_all(parent).map_err(StorageError::CreateDirectory)?;
    // Keep this lock inode stable; removing it could let two migrators proceed.
    let guard = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(parent.join(".Keepy-migration.lock"))
        .map_err(StorageError::Migration)?;
    guard.try_lock().map_err(|_| StorageError::AlreadyRunning)?;
    let legacy = crate::legacy::directory_name();
    let pairs = [
        (parent.join(legacy), parent.join("Keepy")),
        (
            parent.join(format!("{legacy}-backups")),
            parent.join("Keepy-backups"),
        ),
    ];
    let mut locks = Vec::new();
    // Preflight every destination before changing any path.
    for (source, destination) in &pairs {
        if !path_exists(source)? {
            continue;
        }
        if !fs::symlink_metadata(source)
            .map_err(StorageError::Migration)?
            .is_dir()
        {
            return Err(StorageError::MigrationConflict);
        }
        if path_exists(destination)? {
            let meta = fs::symlink_metadata(destination).map_err(StorageError::Migration)?;
            if !meta.is_dir()
                || fs::read_dir(destination)
                    .map_err(StorageError::Migration)?
                    .next()
                    .is_some()
            {
                return Err(StorageError::MigrationConflict);
            }
        }
        if source == &pairs[0].0 {
            let storage = AppStorage {
                config_file: source.join("config.json"),
                vault_dir: source.join("vaults"),
            };
            locks.push(storage.lock_instance()?);
            let config = storage.load_config()?;
            for record in &config.vaults {
                storage.read_vault(record)?;
            }
        }
    }
    for (source, destination) in &pairs {
        if !path_exists(source)? {
            continue;
        }
        if path_exists(destination)? {
            fs::remove_dir(destination).map_err(StorageError::Migration)?;
        }
        // Same-parent rename is atomic and retains every file and its permissions.
        fs::rename(source, destination).map_err(StorageError::Migration)?;
        File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(StorageError::Migration)?;
    }
    Ok(())
}

fn path_exists(path: &Path) -> Result<bool, StorageError> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(StorageError::Migration(error)),
    }
}

fn migrate_identity_artifacts(library: &Path) -> Result<(), StorageError> {
    use std::os::unix::fs::OpenOptionsExt;
    let support = library.join("Application Support");
    let guard = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(support.join(".Keepy-migration.lock"))
        .map_err(StorageError::Migration)?;
    guard.try_lock().map_err(|_| StorageError::AlreadyRunning)?;
    let previous = format!(
        "dev.{}.desktop",
        crate::legacy::directory_name().replace('-', "")
    );
    for (folder, suffix) in [
        ("Preferences", ".plist"),
        ("Caches", ""),
        ("HTTPStorages", ""),
        ("HTTPStorages", ".binarycookies"),
        ("Saved Application State", ".savedState"),
    ] {
        let source = library.join(folder).join(format!("{previous}{suffix}"));
        if !path_exists(&source)? {
            continue;
        }
        let mut destination = library
            .join(folder)
            .join(format!("dev.keepy.desktop{suffix}"));
        if path_exists(&destination)? {
            // New preferences/caches take precedence. Preserve the earlier copy
            // under a branded backup name instead of overwriting or deleting it.
            let archives = support.join("Keepy-backups/system");
            create_private_dir(&archives)?;
            destination = archives.join(format!(
                "{}-dev.keepy.desktop-{}{suffix}",
                folder.replace(' ', "-"),
                Uuid::new_v4()
            ));
        }
        fs::rename(&source, &destination).map_err(StorageError::Migration)?;
    }
    Ok(())
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
    fn old_system_identity_paths_migrate_without_overwriting_new_preferences() {
        let directory = tempdir().unwrap();
        let library = directory.path();
        fs::create_dir(library.join("Application Support")).unwrap();
        fs::create_dir(library.join("Preferences")).unwrap();
        fs::create_dir(library.join("Caches")).unwrap();
        let old_id = format!(
            "dev.{}.desktop",
            crate::legacy::directory_name().replace('-', "")
        );
        let previous = library.join("Preferences").join(format!("{old_id}.plist"));
        fs::write(&previous, b"previous preferences").unwrap();
        let target = library.join("Preferences/dev.keepy.desktop.plist");
        fs::write(&target, b"current preferences").unwrap();
        let cache = library.join("Caches").join(&old_id);
        fs::create_dir(&cache).unwrap();
        fs::write(cache.join("fixture"), b"cache").unwrap();
        migrate_identity_artifacts(library).unwrap();
        assert!(!previous.exists() && !cache.exists());
        assert_eq!(fs::read(target).unwrap(), b"current preferences");
        assert_eq!(
            fs::read(library.join("Caches/dev.keepy.desktop/fixture")).unwrap(),
            b"cache"
        );
        let archived: Vec<_> =
            fs::read_dir(library.join("Application Support/Keepy-backups/system"))
                .unwrap()
                .collect();
        assert_eq!(archived.len(), 1);
        assert_eq!(
            fs::read(archived[0].as_ref().unwrap().path()).unwrap(),
            b"previous preferences"
        );
        migrate_identity_artifacts(library).unwrap();
    }

    fn legacy_fixture(parent: &Path) -> (AppStorage, VaultRecord, Vec<u8>) {
        let root = parent.join(crate::legacy::directory_name());
        let storage = AppStorage::new(&root, &root).unwrap();
        let bytes = include_bytes!("core/fixtures/legacy-vault.json").to_vec();
        let envelope = crate::core::VaultEnvelope::from_bytes(&bytes).unwrap();
        let record = VaultRecord {
            id: envelope.vault_id(),
            name: "Existing vault".into(),
            file_name: format!("{}.bok", envelope.vault_id()),
        };
        let mut config = AppConfig::default();
        config.settings.appearance = "dark".into();
        config.settings.auto_lock_seconds = 600;
        config.vaults.push(record.clone());
        storage.save_config(&config).unwrap();
        storage.write_vault(&record, &bytes).unwrap();
        (storage, record, bytes)
    }

    #[test]
    fn migration_preserves_bytes_settings_permissions_and_backup_tree() {
        use std::os::unix::fs::PermissionsExt;
        let directory = tempdir().unwrap();
        let parent = directory.path();
        let (old, record, bytes) = legacy_fixture(parent);
        let config_before = fs::read(&old.config_file).unwrap();
        let old_backups = parent.join(format!("{}-backups", crate::legacy::directory_name()));
        fs::create_dir_all(old_backups.join("nested")).unwrap();
        fs::write(old_backups.join("nested/snapshot.bok"), &bytes).unwrap();
        let migrated = AppStorage::discover_in(parent).unwrap();
        assert!(!old.config_file.parent().unwrap().exists());
        assert!(!old_backups.exists());
        assert_eq!(fs::read(&migrated.config_file).unwrap(), config_before);
        assert_eq!(migrated.read_vault(&record).unwrap(), bytes);
        assert_eq!(
            migrated.load_config().unwrap().settings.auto_lock_seconds,
            600
        );
        assert_eq!(
            fs::read(parent.join("Keepy-backups/nested/snapshot.bok")).unwrap(),
            bytes
        );
        assert_eq!(
            fs::metadata(migrated.vault_dir.join(&record.file_name))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        let envelope =
            crate::core::VaultEnvelope::from_bytes(&migrated.read_vault(&record).unwrap()).unwrap();
        assert!(envelope.unlock(b"synthetic-legacy-passphrase").is_ok());
        assert_eq!(
            AppStorage::discover_in(parent)
                .unwrap()
                .read_vault(&record)
                .unwrap(),
            bytes
        );
    }

    #[test]
    fn migration_refuses_running_previous_service_then_succeeds_after_exit() {
        let directory = tempdir().unwrap();
        let (old, record, bytes) = legacy_fixture(directory.path());
        let lock = old.lock_instance().unwrap();
        assert!(matches!(
            AppStorage::discover_in(directory.path()),
            Err(StorageError::AlreadyRunning)
        ));
        assert_eq!(old.read_vault(&record).unwrap(), bytes);
        assert!(!directory.path().join("Keepy").exists());
        drop(lock);
        assert!(AppStorage::discover_in(directory.path()).is_ok());
    }

    #[test]
    fn conflicting_backup_destination_prevents_any_data_move() {
        let directory = tempdir().unwrap();
        let (old, record, bytes) = legacy_fixture(directory.path());
        fs::create_dir(
            directory
                .path()
                .join(format!("{}-backups", crate::legacy::directory_name())),
        )
        .unwrap();
        fs::create_dir(directory.path().join("Keepy-backups")).unwrap();
        fs::write(
            directory.path().join("Keepy-backups/existing"),
            b"do not overwrite",
        )
        .unwrap();
        assert!(matches!(
            AppStorage::discover_in(directory.path()),
            Err(StorageError::MigrationConflict)
        ));
        assert_eq!(old.read_vault(&record).unwrap(), bytes);
        assert!(!directory.path().join("Keepy").exists());
    }

    #[test]
    fn migration_never_overwrites_existing_data_or_symlinks() {
        let directory = tempdir().unwrap();
        let (old, record, bytes) = legacy_fixture(directory.path());
        let target = directory.path().join("Keepy");
        fs::create_dir(&target).unwrap();
        fs::write(target.join("existing"), b"keep").unwrap();
        assert!(matches!(
            AppStorage::discover_in(directory.path()),
            Err(StorageError::MigrationConflict)
        ));
        assert_eq!(old.read_vault(&record).unwrap(), bytes);
        assert_eq!(fs::read(target.join("existing")).unwrap(), b"keep");
        fs::remove_file(target.join("existing")).unwrap();
        fs::remove_dir(&target).unwrap();
        std::os::unix::fs::symlink(directory.path().join("missing"), &target).unwrap();
        assert!(matches!(
            AppStorage::discover_in(directory.path()),
            Err(StorageError::MigrationConflict)
        ));
        assert_eq!(old.read_vault(&record).unwrap(), bytes);
    }

    #[test]
    fn migration_stops_before_moving_incomplete_registered_vaults() {
        let directory = tempdir().unwrap();
        let (old, record, _) = legacy_fixture(directory.path());
        fs::remove_file(old.vault_dir.join(&record.file_name)).unwrap();
        assert!(matches!(
            AppStorage::discover_in(directory.path()),
            Err(StorageError::Read(_))
        ));
        assert!(old.config_file.exists());
        assert!(!directory.path().join("Keepy").exists());
    }

    #[test]
    fn migration_resumes_when_data_was_moved_before_backups() {
        let directory = tempdir().unwrap();
        let (old, record, bytes) = legacy_fixture(directory.path());
        let backup = directory
            .path()
            .join(format!("{}-backups", crate::legacy::directory_name()));
        fs::create_dir(&backup).unwrap();
        fs::write(backup.join("vault.bok"), &bytes).unwrap();
        fs::rename(
            old.config_file.parent().unwrap(),
            directory.path().join("Keepy"),
        )
        .unwrap();
        let migrated = AppStorage::discover_in(directory.path()).unwrap();
        assert_eq!(migrated.read_vault(&record).unwrap(), bytes);
        assert!(!backup.exists());
        assert_eq!(
            fs::read(directory.path().join("Keepy-backups/vault.bok")).unwrap(),
            bytes
        );
    }

    #[test]
    fn fresh_install_uses_only_keepy_and_migration_accepts_empty_destination() {
        let directory = tempdir().unwrap();
        let fresh = AppStorage::discover_in(directory.path()).unwrap();
        assert_eq!(
            fresh.config_file.parent().unwrap(),
            directory.path().join("Keepy")
        );
        assert!(
            !directory
                .path()
                .join(crate::legacy::directory_name())
                .exists()
        );
        fs::remove_dir(fresh.vault_dir).unwrap();
        let (_, record, bytes) = legacy_fixture(directory.path());
        assert_eq!(
            AppStorage::discover_in(directory.path())
                .unwrap()
                .read_vault(&record)
                .unwrap(),
            bytes
        );
    }

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
