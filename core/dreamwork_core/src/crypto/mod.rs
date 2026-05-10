//! Key derivation + AEAD helpers for vault material (ADR 0014). No network.

use chacha20poly1305::aead::{Aead, AeadCore, KeyInit, OsRng};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use hkdf::Hkdf;
use sha2::Sha256;

#[derive(Debug)]
pub enum CryptoError {
    KeyDerivation(&'static str),
    Aead(String),
}

impl std::fmt::Display for CryptoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CryptoError::KeyDerivation(s) => write!(f, "{s}"),
            CryptoError::Aead(s) => write!(f, "{s}"),
        }
    }
}

impl std::error::Error for CryptoError {}

/// Derive a 32-byte key using HKDF-SHA256 (label distinguishes contexts).
pub fn hkdf_sha256_32(ikm: &[u8], salt: &[u8], info: &[u8]) -> Result<[u8; 32], CryptoError> {
    let hk = Hkdf::<Sha256>::new(Some(salt), ikm);
    let mut okm = [0u8; 32];
    hk.expand(info, &mut okm)
        .map_err(|_| CryptoError::KeyDerivation("hkdf expand"))?;
    Ok(okm)
}

/// Seal plaintext with random 12-byte nonce; returns nonce || ciphertext.
pub fn seal_vault_blob(plaintext: &[u8], key32: &[u8; 32]) -> Result<Vec<u8>, CryptoError> {
    let key = Key::from_slice(key32);
    let cipher = ChaCha20Poly1305::new(key);
    let nonce = ChaCha20Poly1305::generate_nonce(&mut OsRng);
    let mut out = nonce.to_vec();
    let ct = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|e| CryptoError::Aead(e.to_string()))?;
    out.extend_from_slice(&ct);
    Ok(out)
}

pub fn open_vault_blob(blob: &[u8], key32: &[u8; 32]) -> Result<Vec<u8>, CryptoError> {
    if blob.len() < 12 {
        return Err(CryptoError::KeyDerivation("blob too short"));
    }
    let (n, ct) = blob.split_at(12);
    let nonce = Nonce::from_slice(n);
    let key = Key::from_slice(key32);
    let cipher = ChaCha20Poly1305::new(key);
    cipher
        .decrypt(nonce, ct)
        .map_err(|e| CryptoError::Aead(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hkdf_is_deterministic() {
        let a = hkdf_sha256_32(b"secret", b"salt", b"ctx").unwrap();
        let b = hkdf_sha256_32(b"secret", b"salt", b"ctx").unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn seal_round_trip() {
        let key = hkdf_sha256_32(b"m", b"s", b"k").unwrap();
        let blob = seal_vault_blob(b"hello", &key).unwrap();
        assert_eq!(open_vault_blob(&blob, &key).unwrap(), b"hello");
    }
}
