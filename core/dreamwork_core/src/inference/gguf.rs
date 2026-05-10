//! Minimal GGUF container inspection (magic + header counts). Full tensor mmap loads stay in llama.cpp-class backends (ADR 0017).

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GgufHeader {
    pub version: u32,
    pub tensor_count: u64,
    pub metadata_kv_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GgufLoadError {
    TooShort,
    BadMagic,
    UnsupportedVersion(u32),
}

impl std::fmt::Display for GgufLoadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GgufLoadError::TooShort => write!(f, "gguf: buffer too short"),
            GgufLoadError::BadMagic => write!(f, "gguf: bad magic"),
            GgufLoadError::UnsupportedVersion(v) => write!(f, "gguf: unsupported version {v}"),
        }
    }
}

impl std::error::Error for GgufLoadError {}

pub fn parse_gguf_header_prefix(bytes: &[u8]) -> Result<GgufHeader, GgufLoadError> {
    if bytes.len() < 24 {
        return Err(GgufLoadError::TooShort);
    }
    if &bytes[0..4] != b"GGUF" {
        return Err(GgufLoadError::BadMagic);
    }
    let version = u32::from_le_bytes(bytes[4..8].try_into().unwrap());
    if !(2..=4).contains(&version) {
        return Err(GgufLoadError::UnsupportedVersion(version));
    }
    let tensor_count = u64::from_le_bytes(bytes[8..16].try_into().unwrap());
    let metadata_kv_count = u64::from_le_bytes(bytes[16..24].try_into().unwrap());
    Ok(GgufHeader {
        version,
        tensor_count,
        metadata_kv_count,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_short_slice() {
        assert!(matches!(
            parse_gguf_header_prefix(&[1, 2, 3]),
            Err(GgufLoadError::TooShort)
        ));
    }

    #[test]
    fn parses_minimal_valid_prefix() {
        let mut b = vec![0u8; 24];
        b[0..4].copy_from_slice(b"GGUF");
        b[4..8].copy_from_slice(&3u32.to_le_bytes());
        b[8..16].copy_from_slice(&7u64.to_le_bytes());
        b[16..24].copy_from_slice(&11u64.to_le_bytes());
        let h = parse_gguf_header_prefix(&b).unwrap();
        assert_eq!(h.version, 3);
        assert_eq!(h.tensor_count, 7);
        assert_eq!(h.metadata_kv_count, 11);
    }
}
