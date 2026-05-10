//! On-device inference seams (ADR 0017): ONNX for traditional ML, GGUF-backed LLM session for schema JSON.
//!
//! Concrete accelerators (Core ML, NNAPI, Metal, Vulkan) stay in platform shims; this crate defines **portable traits**.

mod gguf;

#[cfg(feature = "onnx")]
mod onnx_ort;

pub use gguf::{parse_gguf_header_prefix, GgufHeader, GgufLoadError};

#[cfg(feature = "onnx")]
pub use onnx_ort::OrtIdentityOnnxSession;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InferenceError {
    Unsupported(String),
    Session(String),
}

impl std::fmt::Display for InferenceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            InferenceError::Unsupported(s) => write!(f, "unsupported inference op: {s}"),
            InferenceError::Session(s) => write!(f, "session error: {s}"),
        }
    }
}

impl std::error::Error for InferenceError {}

/// Logical artifact IDs — see `docs/device-matrix.md`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OnnxArtifactId(pub String);

pub trait OnnxInferenceSession: Send + Sync {
    fn artifact_id(&self) -> &OnnxArtifactId;

    /// Minimal placeholder until tensor shapes are frozen.
    fn run_dummy_forward(&self) -> Result<(), InferenceError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GenerativeArtifactId(pub String);

pub trait GenerativeLlmSession: Send + Sync {
    fn artifact_id(&self) -> &GenerativeArtifactId;

    /// Produce constrained JSON text for mapping plans (ADR 0005); stub returns static JSON.
    fn generate_schema_plan_json(&self, user_prompt: &str) -> Result<String, InferenceError>;
}

#[derive(Debug)]
pub struct StubOnnxSession {
    pub id: OnnxArtifactId,
}

impl OnnxInferenceSession for StubOnnxSession {
    fn artifact_id(&self) -> &OnnxArtifactId {
        &self.id
    }

    fn run_dummy_forward(&self) -> Result<(), InferenceError> {
        Ok(())
    }
}

#[derive(Debug)]
pub struct StubGenerativeSession {
    pub id: GenerativeArtifactId,
}

impl GenerativeLlmSession for StubGenerativeSession {
    fn artifact_id(&self) -> &GenerativeArtifactId {
        &self.id
    }

    fn generate_schema_plan_json(&self, user_prompt: &str) -> Result<String, InferenceError> {
        let escaped = user_prompt.replace('\\', "\\\\").replace('"', "\\\"");
        Ok(format!(
            r#"{{"artifact":"{}","echo":"{}"}}"#,
            self.id.0, escaped
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stub_generative_returns_parseable_json() {
        let session = StubGenerativeSession {
            id: GenerativeArtifactId("llm.schema.lite.v1".to_string()),
        };
        let json = session.generate_schema_plan_json(r#"say "hi""#).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["artifact"].as_str().unwrap(), "llm.schema.lite.v1");
    }

    #[test]
    fn stub_onnx_runs() {
        let session = StubOnnxSession {
            id: OnnxArtifactId("ort.embed.v1".to_string()),
        };
        session.run_dummy_forward().unwrap();
    }
}
