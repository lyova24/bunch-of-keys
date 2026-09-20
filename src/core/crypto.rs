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
use zeroize::Zeroizing;

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
        let decrypted_key = Zeroizing::new(
            decrypt_blob(
                &wrapping_key,
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
    format!("bunch-of-keys:{FORMAT_VERSION}:{vault_id}:{section}")
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
    use crate::core::{FieldInput, FieldKind};

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
}
