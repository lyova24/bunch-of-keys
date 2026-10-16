use std::fmt;

use argon2::{Algorithm, Argon2, Params, Version};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use chacha20poly1305::{
    KeyInit, XChaCha20Poly1305, XNonce,
    aead::{Aead, Payload},
};
use rand::{RngCore, rngs::OsRng};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};

use super::VaultData;

const MAGIC: &str = "BOKV";
const FORMAT_VERSION: u16 = 1;
const KEY_LEN: usize = 32;
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 24;
const MAX_ENVELOPE_BYTES: usize = 64 * 1024 * 1024;

pub const DEFAULT_KDF_PARAMETERS: KdfParameters = KdfParameters {
    memory_kib: 65_536,
    iterations: 3,
    parallelism: 1,
};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub struct KdfParameters {
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
}

impl KdfParameters {
    fn validate(self) -> Result<(), CryptoError> {
        if !(8_192..=1_048_576).contains(&self.memory_kib)
            || !(1..=10).contains(&self.iterations)
            || !(1..=16).contains(&self.parallelism)
        {
            return Err(CryptoError::InvalidKdfParameters);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultEnvelope {
    magic: String,
    format_version: u16,
    vault_id: Uuid,
    kdf: KdfEnvelope,
    wrapped_key: EncryptedBlob,
    payload: EncryptedBlob,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct KdfEnvelope {
    algorithm: String,
    parameters: KdfParameters,
    salt: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct EncryptedBlob {
    nonce: String,
    ciphertext: String,
}

pub struct UnlockedVault {
    envelope: VaultEnvelope,
    key: Zeroizing<[u8; KEY_LEN]>,
    data: VaultData,
}

/// Only returned by explicit password-verified enrollment, never a vault view.
/// The password-derived wrapping key cannot unlock a rewrapped vault.
#[derive(Serialize, Deserialize)]
pub struct BiometricCredential {
    version: u16,
    vault_id: Uuid,
    binding: String,
    wrapping_key: String,
}

impl Drop for BiometricCredential {
    fn drop(&mut self) {
        self.wrapping_key.zeroize();
    }
}

impl fmt::Debug for UnlockedVault {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("UnlockedVault")
            .field("vault_id", &self.envelope.vault_id)
            .field("key", &"<redacted>")
            .field("data", &"<redacted>")
            .finish()
    }
}

#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("vault envelope is too large")]
    EnvelopeTooLarge,
    #[error("vault envelope is not valid JSON")]
    InvalidEnvelope(#[source] serde_json::Error),
    #[error("vault format is not supported")]
    UnsupportedFormat,
    #[error("vault KDF parameters are outside the supported range")]
    InvalidKdfParameters,
    #[error("vault cryptographic data is malformed")]
    InvalidEncoding,
    #[error("the password is incorrect or the vault is damaged")]
    InvalidPasswordOrDamagedVault,
    #[error("the encrypted vault payload is damaged")]
    DamagedPayload,
    #[error(
        "Touch ID enrollment is no longer valid. Unlock with the master password and set up Touch ID again."
    )]
    InvalidBiometricCredential,
    #[error("vault data cannot be serialized")]
    Serialize(#[source] serde_json::Error),
    #[error("vault data cannot be decoded")]
    Deserialize(#[source] serde_json::Error),
    #[error("the operating system random-number generator failed")]
    RandomSource,
    #[error("Argon2 could not derive a key")]
    KeyDerivation,
}

impl VaultEnvelope {
    pub fn create(password: &[u8], data: VaultData) -> Result<UnlockedVault, CryptoError> {
        Self::create_with_parameters(password, data, DEFAULT_KDF_PARAMETERS)
    }

    pub fn create_with_parameters(
        password: &[u8],
        data: VaultData,
        parameters: KdfParameters,
    ) -> Result<UnlockedVault, CryptoError> {
        parameters.validate()?;
        data.validate().map_err(|_| CryptoError::InvalidEncoding)?;

        let vault_id = Uuid::new_v4();
        let salt = random_bytes::<SALT_LEN>()?;
        let wrapping_key = derive_key(password, &salt, parameters)?;
        let vault_key = Zeroizing::new(random_bytes::<KEY_LEN>()?);

        let wrapped_key = encrypt_blob(
            &wrapping_key,
            &vault_key[..],
            associated_data(vault_id, "wrapped-key").as_bytes(),
        )?;
        let payload = encrypt_vault_data(vault_id, &vault_key, &data)?;

        Ok(UnlockedVault {
            envelope: Self {
                magic: MAGIC.to_owned(),
                format_version: FORMAT_VERSION,
                vault_id,
                kdf: KdfEnvelope {
                    algorithm: "argon2id".to_owned(),
                    parameters,
                    salt: BASE64.encode(salt),
                },
                wrapped_key,
                payload,
            },
            key: vault_key,
            data,
        })
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, CryptoError> {
        if bytes.len() > MAX_ENVELOPE_BYTES {
            return Err(CryptoError::EnvelopeTooLarge);
        }
        let envelope: Self = serde_json::from_slice(bytes).map_err(CryptoError::InvalidEnvelope)?;
        envelope.validate_header()?;
        Ok(envelope)
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>, CryptoError> {
        serde_json::to_vec_pretty(self).map_err(CryptoError::Serialize)
    }

    pub fn vault_id(&self) -> Uuid {
        self.vault_id
    }

    pub fn unlock(self, password: &[u8]) -> Result<UnlockedVault, CryptoError> {
        self.validate_header()?;
        let salt = decode_array::<SALT_LEN>(&self.kdf.salt)?;
        let wrapping_key = derive_key(password, &salt, self.kdf.parameters)?;
        self.unlock_with_wrapping_key(&wrapping_key)
    }

    /// Public envelope metadata; changes when the password wrapping changes,
    /// but not on ordinary edits or vault renames. No new on-disk format.
    pub fn biometric_binding(&self) -> Result<String, CryptoError> {
        let bytes = serde_json::to_vec(&(
            self.format_version,
            self.vault_id,
            &self.kdf,
            &self.wrapped_key,
        ))
        .map_err(CryptoError::Serialize)?;
        Ok(BASE64.encode(bytes))
    }

    pub fn biometric_credential(
        &self,
        password: &[u8],
    ) -> Result<BiometricCredential, CryptoError> {
        self.validate_header()?;
        let salt = decode_array::<SALT_LEN>(&self.kdf.salt)?;
        let wrapping_key = derive_key(password, &salt, self.kdf.parameters)?;
        // Check both the wrapped key and authenticated payload before export.
        let _verified = self.clone().unlock_with_wrapping_key(&wrapping_key)?;
        Ok(BiometricCredential {
            version: 1,
            vault_id: self.vault_id,
            binding: self.biometric_binding()?,
            wrapping_key: BASE64.encode(&wrapping_key[..]),
        })
    }

    pub fn unlock_biometric(
        self,
        credential: &BiometricCredential,
    ) -> Result<UnlockedVault, CryptoError> {
        self.validate_header()?;
        if credential.version != 1
            || credential.vault_id != self.vault_id
            || credential.binding != self.biometric_binding()?
            || credential.wrapping_key.len() != 44
        {
            return Err(CryptoError::InvalidBiometricCredential);
        }
        let bytes = Zeroizing::new(
            BASE64
                .decode(&credential.wrapping_key)
                .map_err(|_| CryptoError::InvalidBiometricCredential)?,
        );
        let mut key = Zeroizing::new([0_u8; KEY_LEN]);
        if bytes.len() != KEY_LEN {
            return Err(CryptoError::InvalidBiometricCredential);
        }
        key.copy_from_slice(&bytes);
        self.unlock_with_wrapping_key(&key)
            .map_err(|_| CryptoError::InvalidBiometricCredential)
    }

    fn unlock_with_wrapping_key(
        self,
        wrapping_key: &[u8; KEY_LEN],
    ) -> Result<UnlockedVault, CryptoError> {
        let decrypted_key = Zeroizing::new(
            decrypt_blob(
                wrapping_key,
                &self.wrapped_key,
                associated_data(self.vault_id, "wrapped-key").as_bytes(),
            )
            .map_err(|_| CryptoError::InvalidPasswordOrDamagedVault)?,
        );
        if decrypted_key.len() != KEY_LEN {
            return Err(CryptoError::InvalidPasswordOrDamagedVault);
        }
        let mut key = Zeroizing::new([0_u8; KEY_LEN]);
        key.copy_from_slice(&decrypted_key);

        let plaintext = Zeroizing::new(
            decrypt_blob(
                &key,
                &self.payload,
                associated_data(self.vault_id, "payload").as_bytes(),
            )
            .map_err(|_| CryptoError::DamagedPayload)?,
        );
        let mut data: VaultData =
            serde_json::from_slice(&plaintext).map_err(CryptoError::Deserialize)?;
        data.migrate().map_err(|_| CryptoError::DamagedPayload)?;

        Ok(UnlockedVault {
            envelope: self,
            key,
            data,
        })
    }

    fn validate_header(&self) -> Result<(), CryptoError> {
        if self.magic != MAGIC
            || self.format_version != FORMAT_VERSION
            || self.kdf.algorithm != "argon2id"
        {
            return Err(CryptoError::UnsupportedFormat);
        }
        self.kdf.parameters.validate()
    }
}

impl UnlockedVault {
    pub fn vault_id(&self) -> Uuid {
        self.envelope.vault_id
    }

    pub fn data(&self) -> &VaultData {
        &self.data
    }

    pub fn prepare_update(&self, data: &VaultData) -> Result<VaultEnvelope, CryptoError> {
        data.validate().map_err(|_| CryptoError::InvalidEncoding)?;
        let mut envelope = self.envelope.clone();
        envelope.payload = encrypt_vault_data(self.vault_id(), &self.key, data)?;
        Ok(envelope)
    }

    pub fn commit(&mut self, data: VaultData, envelope: VaultEnvelope) {
        self.data = data;
        self.envelope = envelope;
    }

    pub fn envelope(&self) -> &VaultEnvelope {
        &self.envelope
    }

    /// Prepare a replacement wrapping without mutating the live session. The
    /// authenticated payload and vault key remain unchanged; the caller must
    /// persist this envelope atomically before locking the session.
    pub fn prepare_password_change(
        &self,
        current_password: &[u8],
        new_password: &[u8],
    ) -> Result<VaultEnvelope, CryptoError> {
        let _verified = self.envelope.clone().unlock(current_password)?;
        let salt = random_bytes::<SALT_LEN>()?;
        let wrapping_key = derive_key(new_password, &salt, DEFAULT_KDF_PARAMETERS)?;
        let mut envelope = self.envelope.clone();
        envelope.kdf = KdfEnvelope {
            algorithm: "argon2id".to_owned(),
            parameters: DEFAULT_KDF_PARAMETERS,
            salt: BASE64.encode(salt),
        };
        envelope.wrapped_key = encrypt_blob(
            &wrapping_key,
            &self.key[..],
            associated_data(self.vault_id(), "wrapped-key").as_bytes(),
        )?;
        Ok(envelope)
    }
}

fn derive_key(
    password: &[u8],
    salt: &[u8; SALT_LEN],
    parameters: KdfParameters,
) -> Result<Zeroizing<[u8; KEY_LEN]>, CryptoError> {
    let params = Params::new(
        parameters.memory_kib,
        parameters.iterations,
        parameters.parallelism,
        Some(KEY_LEN),
    )
    .map_err(|_| CryptoError::InvalidKdfParameters)?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut output = Zeroizing::new([0_u8; KEY_LEN]);
    argon2
        .hash_password_into(password, salt, &mut output[..])
        .map_err(|_| CryptoError::KeyDerivation)?;
    Ok(output)
}

fn encrypt_vault_data(
    vault_id: Uuid,
    key: &[u8; KEY_LEN],
    data: &VaultData,
) -> Result<EncryptedBlob, CryptoError> {
    let plaintext = Zeroizing::new(serde_json::to_vec(data).map_err(CryptoError::Serialize)?);
    encrypt_blob(
        key,
        &plaintext,
        associated_data(vault_id, "payload").as_bytes(),
    )
}

fn encrypt_blob(
    key: &[u8; KEY_LEN],
    plaintext: &[u8],
    aad: &[u8],
) -> Result<EncryptedBlob, CryptoError> {
    let nonce = random_bytes::<NONCE_LEN>()?;
    let cipher = XChaCha20Poly1305::new(key.into());
    let ciphertext = cipher
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CryptoError::InvalidEncoding)?;
    Ok(EncryptedBlob {
        nonce: BASE64.encode(nonce),
        ciphertext: BASE64.encode(ciphertext),
    })
}

fn decrypt_blob(
    key: &[u8; KEY_LEN],
    blob: &EncryptedBlob,
    aad: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    let nonce = decode_array::<NONCE_LEN>(&blob.nonce)?;
    let ciphertext = BASE64
        .decode(&blob.ciphertext)
        .map_err(|_| CryptoError::InvalidEncoding)?;
    let cipher = XChaCha20Poly1305::new(key.into());
    cipher
        .decrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: &ciphertext,
                aad,
            },
        )
        .map_err(|_| CryptoError::InvalidEncoding)
}

fn decode_array<const N: usize>(encoded: &str) -> Result<[u8; N], CryptoError> {
    let bytes = BASE64
        .decode(encoded)
        .map_err(|_| CryptoError::InvalidEncoding)?;
    bytes.try_into().map_err(|_| CryptoError::InvalidEncoding)
}

fn associated_data(vault_id: Uuid, section: &str) -> String {
    // This format domain is authenticated metadata, independent of branding.
    format!(
        "{}:{FORMAT_VERSION}:{vault_id}:{section}",
        crate::legacy::directory_name()
    )
}

fn random_bytes<const N: usize>() -> Result<[u8; N], CryptoError> {
    let mut bytes = [0_u8; N];
    OsRng
        .try_fill_bytes(&mut bytes)
        .map_err(|_| CryptoError::RandomSource)?;
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::{FieldInput, FieldKind, TagColor};

    const TEST_KDF: KdfParameters = KdfParameters {
        memory_kib: 8_192,
        iterations: 1,
        parallelism: 1,
    };

    fn sample_data() -> VaultData {
        let mut data = VaultData::default();
        data.add_entry(
            None,
            "Example",
            vec![FieldInput {
                tags: None,
                id: None,
                label: "Password".to_owned(),
                value: "not-a-real-password".to_owned(),
                kind: FieldKind::Secret,
                masked: true,
                ssh: None,
            }],
        )
        .unwrap();
        data
    }

    #[test]
    fn password_change_uses_fresh_wrapping_and_keeps_payload_and_vault_key() {
        let original =
            VaultEnvelope::create_with_parameters(b"original-password", sample_data(), TEST_KDF)
                .unwrap();
        let next = original
            .prepare_password_change(b"original-password", b"replacement-password")
            .unwrap();
        assert_eq!(next.vault_id, original.vault_id());
        assert_ne!(next.kdf.salt, original.envelope.kdf.salt);
        assert_ne!(next.wrapped_key.nonce, original.envelope.wrapped_key.nonce);
        assert_eq!(next.payload.nonce, original.envelope.payload.nonce);
        assert_eq!(
            next.payload.ciphertext,
            original.envelope.payload.ciphertext
        );
        let reopened = next.unlock(b"replacement-password").unwrap();
        // Keep raw key material out of assertion diagnostics.
        let same_key = original.key[..] == reopened.key[..];
        assert!(same_key);
        assert_eq!(original.data(), reopened.data());
        assert!(
            original
                .prepare_password_change(b"wrong-password", b"replacement-password")
                .is_err()
        );
        assert!(
            original
                .envelope
                .clone()
                .unlock(b"original-password")
                .is_ok()
        );
    }

    #[test]
    fn previous_shipped_vault_still_unlocks_after_identity_rename() {
        // Generated by the previous shipping core, not by these crypto functions.
        let bytes = include_bytes!("fixtures/legacy-vault.json");
        let vault = VaultEnvelope::from_bytes(bytes)
            .unwrap()
            .unlock(b"synthetic-legacy-passphrase")
            .unwrap();
        let crate::core::Node::Entry(entry) = &vault.data().nodes[0] else {
            panic!("fixture entry missing")
        };
        assert_eq!(entry.fields[0].value, "synthetic-legacy-secret");
        assert!(entry.fields[0].masked);
        assert_eq!(entry.tags, vec![TagColor::Blue]);
        let updated = vault.prepare_update(vault.data()).unwrap();
        assert_eq!(
            updated
                .unlock(b"synthetic-legacy-passphrase")
                .unwrap()
                .data(),
            vault.data()
        );
    }

    #[test]
    fn round_trips_an_encrypted_vault() {
        let expected = sample_data();
        let unlocked = VaultEnvelope::create_with_parameters(
            b"a long test passphrase",
            expected.clone(),
            TEST_KDF,
        )
        .unwrap();
        let bytes = unlocked.envelope().to_bytes().unwrap();
        assert!(!String::from_utf8_lossy(&bytes).contains("not-a-real-password"));

        let envelope = VaultEnvelope::from_bytes(&bytes).unwrap();
        let restored = envelope.unlock(b"a long test passphrase").unwrap();

        assert_eq!(restored.data(), &expected);
    }

    #[test]
    fn persists_tag_updates_without_exposing_or_changing_credentials() {
        let mut data = sample_data();
        let entry_id = data.nodes[0].id();
        let group_id = data
            .add_group_with_tags(None, "Tagged group", vec![TagColor::Blue, TagColor::Gray])
            .unwrap();
        data.set_node_tags(entry_id, vec![TagColor::Red, TagColor::Orange])
            .unwrap();
        data.move_node(entry_id, Some(group_id), 0).unwrap();
        let mut unlocked =
            VaultEnvelope::create_with_parameters(b"a long test passphrase", data, TEST_KDF)
                .unwrap();
        let mut updated = unlocked.data().clone();
        updated
            .set_node_tags(entry_id, vec![TagColor::Purple, TagColor::Green])
            .unwrap();
        let envelope = unlocked.prepare_update(&updated).unwrap();
        unlocked.commit(updated.clone(), envelope);
        let bytes = unlocked.envelope().to_bytes().unwrap();
        let envelope_json = String::from_utf8_lossy(&bytes);
        assert!(!envelope_json.contains("Tagged group"));
        assert!(!envelope_json.contains("purple"));
        assert!(!envelope_json.contains("not-a-real-password"));
        let restored = VaultEnvelope::from_bytes(&bytes)
            .unwrap()
            .unlock(b"a long test passphrase")
            .unwrap();

        assert_eq!(restored.data(), &updated);
        assert_eq!(restored.data().schema_version, 2);
    }

    #[test]
    fn unlocks_legacy_encrypted_payloads_without_tag_fields() {
        let data = sample_data();
        let expected = data.clone();
        let unlocked =
            VaultEnvelope::create_with_parameters(b"a long test passphrase", data, TEST_KDF)
                .unwrap();
        let mut legacy = serde_json::to_value(&expected).unwrap();
        legacy["nodes"][0].as_object_mut().unwrap().remove("tags");
        let plaintext = Zeroizing::new(serde_json::to_vec(&legacy).unwrap());
        let mut envelope = unlocked.envelope().clone();
        envelope.payload = encrypt_blob(
            &unlocked.key,
            &plaintext,
            associated_data(unlocked.vault_id(), "payload").as_bytes(),
        )
        .unwrap();
        let restored = envelope.unlock(b"a long test passphrase").unwrap();

        assert_eq!(restored.data(), &expected);
        assert_eq!(restored.data().nodes[0].tags(), []);
    }

    #[test]
    fn rejects_duplicate_tags_inside_an_authenticated_encrypted_payload() {
        let unlocked = VaultEnvelope::create_with_parameters(
            b"a long test passphrase",
            sample_data(),
            TEST_KDF,
        )
        .unwrap();
        let mut invalid = serde_json::to_value(unlocked.data()).unwrap();
        invalid["nodes"][0]["tags"] = serde_json::json!(["red", "red"]);
        let plaintext = Zeroizing::new(serde_json::to_vec(&invalid).unwrap());
        let mut envelope = unlocked.envelope().clone();
        envelope.payload = encrypt_blob(
            &unlocked.key,
            &plaintext,
            associated_data(unlocked.vault_id(), "payload").as_bytes(),
        )
        .unwrap();

        assert!(matches!(
            envelope.unlock(b"a long test passphrase"),
            Err(CryptoError::DamagedPayload)
        ));
    }

    #[test]
    fn rejects_an_incorrect_password() {
        let unlocked = VaultEnvelope::create_with_parameters(
            b"correct horse battery staple",
            sample_data(),
            TEST_KDF,
        )
        .unwrap();
        let envelope = VaultEnvelope::from_bytes(&unlocked.envelope().to_bytes().unwrap()).unwrap();

        assert!(matches!(
            envelope.unlock(b"incorrect password"),
            Err(CryptoError::InvalidPasswordOrDamagedVault)
        ));
    }

    #[test]
    fn rejects_modified_payload_ciphertext() {
        let unlocked = VaultEnvelope::create_with_parameters(
            b"correct horse battery staple",
            sample_data(),
            TEST_KDF,
        )
        .unwrap();
        let mut envelope = unlocked.envelope().clone();
        let mut ciphertext = BASE64.decode(&envelope.payload.ciphertext).unwrap();
        ciphertext[0] ^= 1;
        envelope.payload.ciphertext = BASE64.encode(ciphertext);

        assert!(matches!(
            envelope.unlock(b"correct horse battery staple"),
            Err(CryptoError::DamagedPayload)
        ));
    }

    #[test]
    fn biometric_material_is_password_verified_and_survives_payload_edits() {
        let unlocked =
            VaultEnvelope::create_with_parameters(b"synthetic-password", sample_data(), TEST_KDF)
                .unwrap();
        let envelope = unlocked.envelope();
        assert!(envelope.biometric_credential(b"incorrect").is_err());
        let credential = envelope
            .biometric_credential(b"synthetic-password")
            .unwrap();
        assert!(
            !serde_json::to_string(&credential)
                .unwrap()
                .contains("synthetic-password")
        );
        let mut edited = unlocked.data().clone();
        edited.add_group(None, "New group").unwrap();
        let updated = unlocked.prepare_update(&edited).unwrap();
        assert_eq!(
            updated.biometric_binding().unwrap(),
            envelope.biometric_binding().unwrap()
        );
        assert_eq!(
            updated.unlock_biometric(&credential).unwrap().data(),
            &edited
        );

        let other =
            VaultEnvelope::create_with_parameters(b"synthetic-password", sample_data(), TEST_KDF)
                .unwrap();
        assert!(
            other
                .envelope()
                .clone()
                .unlock_biometric(&credential)
                .is_err()
        );
        let mut invalid = credential;
        invalid.wrapping_key = BASE64.encode([0; KEY_LEN]);
        assert!(envelope.clone().unlock_biometric(&invalid).is_err());
        invalid.wrapping_key = "invalid".to_owned();
        assert!(envelope.clone().unlock_biometric(&invalid).is_err());
        invalid.version = 2;
        assert!(envelope.clone().unlock_biometric(&invalid).is_err());
    }

    #[test]
    fn password_rewrapping_invalidates_biometric_material_without_changing_data() {
        let unlocked =
            VaultEnvelope::create_with_parameters(b"old-password", sample_data(), TEST_KDF)
                .unwrap();
        let old = unlocked
            .envelope()
            .biometric_credential(b"old-password")
            .unwrap();
        let mut changed = unlocked.envelope().clone();
        let salt = random_bytes::<SALT_LEN>().unwrap();
        let key = derive_key(b"new-password", &salt, TEST_KDF).unwrap();
        changed.kdf.salt = BASE64.encode(salt);
        changed.wrapped_key = encrypt_blob(
            &key,
            &unlocked.key[..],
            associated_data(unlocked.vault_id(), "wrapped-key").as_bytes(),
        )
        .unwrap();
        assert!(changed.clone().unlock_biometric(&old).is_err());
        assert!(changed.clone().unlock(b"old-password").is_err());
        assert_eq!(
            changed.clone().unlock(b"new-password").unwrap().data(),
            unlocked.data()
        );
        let current = changed.biometric_credential(b"new-password").unwrap();
        assert_eq!(
            changed.unlock_biometric(&current).unwrap().data(),
            unlocked.data()
        );
    }
}
