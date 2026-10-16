use super::*;
use crate::core::{FieldInput, TagColor};
use std::fs;
use tempfile::tempdir;

const OLD: &[u8] = b"synthetic-old-password";
const NEW: &[u8] = b"synthetic-new-password";

#[test]
fn rename_is_trimmed_unique_unicode_aware_and_persistent_without_touching_vault_bytes() {
    let directory = tempdir().unwrap();
    let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
    let state = AppState::new(storage.clone(), AppConfig::default());
    let first = state.create_vault("Work", OLD).unwrap().id;
    let other = state.create_vault("Работа", OLD).unwrap().id;
    state.unlock_vault(first, OLD).unwrap();
    let record = storage.load_config().unwrap().vaults[0].clone();
    let before = storage.read_vault(&record).unwrap();
    for name in ["", "  \n ", "bad\0name", &"x".repeat(81)] {
        assert!(matches!(
            state.rename_vault(first, name),
            Err(AppError::InvalidVaultName)
        ));
    }
    assert!(matches!(
        state.rename_vault(first, "  работа  "),
        Err(AppError::DuplicateVaultName)
    ));
    assert!(state.rename_vault(other, "Wrong vault").is_err());
    let registry = fs::read(directory.path().join("config.json")).unwrap();
    assert_eq!(state.rename_vault(first, "  Work \n").unwrap().name, "Work");
    assert_eq!(
        fs::read(directory.path().join("config.json")).unwrap(),
        registry
    );
    assert_eq!(
        state.rename_vault(first, "  Renamed  ").unwrap().name,
        "Renamed"
    );
    let saved = storage.load_config().unwrap();
    assert_eq!(saved.vaults[0].id, record.id);
    assert_eq!(saved.vaults[0].file_name, record.file_name);
    assert_eq!(storage.read_vault(&record).unwrap(), before);
    assert_eq!(
        state.session.lock().unwrap().as_ref().unwrap().record.name,
        "Renamed"
    );
    state.lock();
    let restarted = AppState::new(storage.clone(), storage.load_config().unwrap());
    assert_eq!(restarted.bootstrap().unwrap().vaults[0].name, "Renamed");
    assert_eq!(restarted.unlock_vault(first, OLD).unwrap().id, first);
}

#[test]
fn failed_registry_write_keeps_both_names_and_original_envelope() {
    let directory = tempdir().unwrap();
    let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
    let state = AppState::new(storage.clone(), AppConfig::default());
    let id = state.create_vault("Before", OLD).unwrap().id;
    let record = storage.load_config().unwrap().vaults[0].clone();
    let bytes = storage.read_vault(&record).unwrap();
    let path = directory.path().join("config.json");
    let backup = directory.path().join("registry-before");
    fs::rename(&path, &backup).unwrap();
    fs::create_dir(&path).unwrap(); // Force an atomic-rename failure, even as root.
    assert_eq!(
        state.rename_vault(id, "Before").unwrap().name,
        "Before",
        "An unchanged name must not write"
    );
    assert!(state.rename_vault(id, "After").is_err());
    assert_eq!(state.bootstrap().unwrap().vaults[0].name, "Before");
    assert_eq!(
        state.session.lock().unwrap().as_ref().unwrap().record.name,
        "Before"
    );
    assert_eq!(storage.read_vault(&record).unwrap(), bytes);
    fs::remove_dir(&path).unwrap();
    fs::rename(backup, path).unwrap();
    assert_eq!(storage.load_config().unwrap().vaults[0].name, "Before");
    state.lock();
    assert!(state.rename_vault(id, "After").is_err());
    assert!(state.unlock_vault(id, OLD).is_ok());
}

fn populate_vault(state: &AppState) {
    use ssh_key::{Algorithm, LineEnding, PrivateKey, rand_core::OsRng};
    let private = PrivateKey::random(&mut OsRng, Algorithm::Ed25519)
        .unwrap()
        .to_openssh(LineEnding::LF)
        .unwrap();
    state
        .mutate(|data| {
            let key = data.add_ssh_key("Test SSH key", &private)?;
            let group = data.add_group_with_tags(None, "Tagged group", vec![TagColor::Blue])?;
            let nested = data.add_group(Some(group), "Nested")?;
            let field = Uuid::new_v4();
            let entry = data.add_entry_with_tags(
                Some(nested),
                "Credential",
                vec![
                    FieldInput {
                        id: Some(field),
                        label: "Secret".into(),
                        value: "synthetic-secret".into(),
                        kind: FieldKind::Secret,
                        masked: true,
                        ssh: None,
                    },
                    FieldInput {
                        id: None,
                        label: "SSH".into(),
                        value: String::new(),
                        kind: FieldKind::Ssh,
                        masked: false,
                        ssh: Some(SshConnection {
                            user: "test".into(),
                            address: "example.invalid".into(),
                            port: Some(2222),
                            key_id: key,
                        }),
                    },
                ],
                vec![TagColor::Red, TagColor::Green],
            )?;

            data.move_field(entry, field, 1)?;
            Ok(())
        })
        .unwrap();
}

#[test]
fn password_change_preserves_complete_payload_identity_and_old_backups_and_invalidates_touch_id() {
    let directory = tempdir().unwrap();
    let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
    let state = AppState::new(storage.clone(), AppConfig::default());
    let id = state.create_vault("Rich vault", OLD).unwrap().id;
    populate_vault(&state);
    let before = state
        .session
        .lock()
        .unwrap()
        .as_ref()
        .unwrap()
        .vault
        .data()
        .clone();
    let record = storage.load_config().unwrap().vaults[0].clone();
    let backup = storage.read_vault(&record).unwrap();
    let biometric = state.enroll_biometric(id, OLD).unwrap();
    for (old, new, confirmation) in [
        (b"incorrect-password".as_slice(), NEW, NEW),
        (OLD, b"short", b"short"),
        (OLD, NEW, b"mismatch"),
        (OLD, OLD, OLD),
    ] {
        assert!(
            state
                .change_master_password(id, old, new, confirmation)
                .is_err()
        );
        assert_eq!(storage.read_vault(&record).unwrap(), backup);
        assert_eq!(
            state.session.lock().unwrap().as_ref().unwrap().vault.data(),
            &before
        );
    }
    assert!(
        state
            .change_master_password(Uuid::new_v4(), OLD, NEW, NEW)
            .is_err()
    );
    state.change_master_password(id, OLD, NEW, NEW).unwrap();
    assert!(state.bootstrap().unwrap().current.is_none());
    let saved = storage.load_config().unwrap();
    assert_eq!(saved.vaults[0].id, id);
    assert_eq!(saved.vaults[0].file_name, record.file_name);
    let updated = storage.read_vault(&record).unwrap();
    assert!(
        VaultEnvelope::from_bytes(&updated)
            .unwrap()
            .unlock(OLD)
            .is_err()
    );
    assert!(
        VaultEnvelope::from_bytes(&updated)
            .unwrap()
            .unlock_biometric(&biometric)
            .is_err()
    );
    assert_eq!(
        VaultEnvelope::from_bytes(&backup)
            .unwrap()
            .unlock(OLD)
            .unwrap()
            .data(),
        &before
    );
    assert_eq!(
        VaultEnvelope::from_bytes(&updated)
            .unwrap()
            .unlock(NEW)
            .unwrap()
            .data(),
        &before
    );
    let restarted = AppState::new(storage, saved);
    assert!(restarted.unlock_vault(id, OLD).is_err());
    restarted.unlock_vault(id, NEW).unwrap();
    assert_eq!(
        restarted
            .session
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .vault
            .data(),
        &before
    );
}

#[test]
fn failed_password_write_preserves_original_password_session_and_biometric_binding() {
    let directory = tempdir().unwrap();
    let storage = AppStorage::new(directory.path(), directory.path()).unwrap();
    let state = AppState::new(storage.clone(), AppConfig::default());
    let id = state.create_vault("Before", OLD).unwrap().id;
    let record = storage.load_config().unwrap().vaults[0].clone();
    let bytes = storage.read_vault(&record).unwrap();
    let binding = state.biometric_binding(id).unwrap();
    let path = directory.path().join("vaults").join(&record.file_name);
    let backup = path.with_extension("original");
    fs::rename(&path, &backup).unwrap();
    fs::create_dir(&path).unwrap();
    assert!(state.change_master_password(id, OLD, NEW, NEW).is_err());
    assert_eq!(state.bootstrap().unwrap().current.unwrap().id, id);
    assert_eq!(
        state
            .session
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .vault
            .envelope()
            .biometric_binding()
            .unwrap(),
        binding
    );
    assert_eq!(fs::read(&backup).unwrap(), bytes);
    fs::remove_dir(&path).unwrap();
    fs::rename(backup, path).unwrap();
    state.lock();
    assert!(state.change_master_password(id, OLD, NEW, NEW).is_err());
    assert!(state.unlock_vault(id, OLD).is_ok());
    assert!(state.unlock_vault(id, NEW).is_err());
}
