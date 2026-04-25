#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManualEntry {
    pub id: String,
    pub fields: Vec<ManualField>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManualField {
    pub key: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentArtifact {
    pub id: String,
    pub source: ArtifactSource,
    pub bytes_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ArtifactSource {
    Camera,
    FileImport,
    BrowserCapture,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IngestionArtifact {
    Manual(ManualEntry),
    Document(DocumentArtifact),
}
