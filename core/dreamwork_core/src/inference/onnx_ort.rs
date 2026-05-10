//! ONNX Runtime execution provider wiring (ADR 0017). Uses the **`ort`** crate with downloaded binaries.

use std::sync::Mutex;

use super::{InferenceError, OnnxArtifactId, OnnxInferenceSession};
use ort::session::{Session, SessionOutputs};
use ort::value::Tensor;

pub struct OrtIdentityOnnxSession {
    pub id: OnnxArtifactId,
    session: Mutex<Session>,
}

impl OrtIdentityOnnxSession {
    pub fn from_identity_fixture() -> Result<Self, InferenceError> {
        const BYTES: &[u8] = include_bytes!("../../fixtures/identity.onnx");
        let session = Session::builder()
            .map_err(|e| InferenceError::Session(e.to_string()))?
            .commit_from_memory(BYTES)
            .map_err(|e| InferenceError::Session(e.to_string()))?;
        Ok(Self {
            id: OnnxArtifactId("ort.identity.fixture.v1".to_string()),
            session: Mutex::new(session),
        })
    }
}

impl OnnxInferenceSession for OrtIdentityOnnxSession {
    fn artifact_id(&self) -> &OnnxArtifactId {
        &self.id
    }

    fn run_dummy_forward(&self) -> Result<(), InferenceError> {
        let mut session = self
            .session
            .lock()
            .map_err(|e| InferenceError::Session(e.to_string()))?;
        let tensor = Tensor::from_array(([1usize], vec![42.0_f32].into_boxed_slice()))
            .map_err(|e| InferenceError::Session(e.to_string()))?;
        let _: SessionOutputs = session
            .run(ort::inputs!["x" => tensor])
            .map_err(|e| InferenceError::Session(e.to_string()))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ort_runs_identity_fixture() {
        let session = OrtIdentityOnnxSession::from_identity_fixture().unwrap();
        session.run_dummy_forward().unwrap();
    }
}
