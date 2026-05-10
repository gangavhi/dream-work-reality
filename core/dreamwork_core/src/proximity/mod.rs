//! Proximity sharing seams (ADR 0009): ephemeral ECDH + sealed payloads — transport stays platform-specific.

use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use x25519_dalek::{EphemeralSecret, PublicKey};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProximityIntroduction {
    pub session_label: String,
    pub initiator_public_x25519: [u8; 32],
}

#[derive(Debug)]
pub enum ProximityCryptoError {
    KeyAgreement(&'static str),
}

impl std::fmt::Display for ProximityCryptoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProximityCryptoError::KeyAgreement(s) => write!(f, "{s}"),
        }
    }
}

impl std::error::Error for ProximityCryptoError {}

pub fn x25519_shared_secret(local_secret: EphemeralSecret, peer_public: &PublicKey) -> [u8; 32] {
    *local_secret.diffie_hellman(peer_public).as_bytes()
}

pub struct ProximityHandshakeState {
    ephemeral: EphemeralSecret,
    /// Ephemeral public half advertised to the peer before consuming [`Self::into_shared_secret_with_peer`].
    pub public: PublicKey,
}

impl ProximityHandshakeState {
    pub fn generate() -> Self {
        let ephemeral = EphemeralSecret::random_from_rng(OsRng);
        let public = PublicKey::from(&ephemeral);
        Self { ephemeral, public }
    }

    pub fn introduction(&self, session_label: String) -> ProximityIntroduction {
        ProximityIntroduction {
            session_label,
            initiator_public_x25519: self.public.to_bytes(),
        }
    }

    pub fn into_shared_secret_with_peer(self, peer_public: &PublicKey) -> [u8; 32] {
        x25519_shared_secret(self.ephemeral, peer_public)
    }
}

/// Platform BLE / UWB / NFC transports implement this trait outside the core crate when wired.
pub trait ProximityTransport: Send + Sync {
    fn advertise_session(&self, intro: &ProximityIntroduction) -> Result<(), ProximityCryptoError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn x25519_symmetric_agreement() {
        let alice = ProximityHandshakeState::generate();
        let bob = ProximityHandshakeState::generate();
        let alice_pk = alice.public;
        let bob_pk = bob.public;
        let sa = alice.into_shared_secret_with_peer(&bob_pk);
        let sb = bob.into_shared_secret_with_peer(&alice_pk);
        assert_eq!(sa, sb);
    }
}
