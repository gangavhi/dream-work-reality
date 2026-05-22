//! On-device document field extraction from layout-ordered OCR text (zero egress).
//! Uses heuristics + spatial label|value pairs; GGUF path validated when present (llama.cpp-class backend TBD).

use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::inference::{parse_gguf_header_prefix, GenerativeArtifactId, GenerativeLlmSession, InferenceError};
use crate::profile_keys::normalize_field_key;

pub const ENGINE_ID: &str = "heuristic.on_device.v1";
pub const DEFAULT_ARTIFACT_ID: &str = "llm.schema.lite.v1";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldEntry {
    pub value: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MapDocumentFieldsRequest {
    pub layout_text: String,
    #[serde(default)]
    pub profile_schema_keys: Vec<String>,
    #[serde(default)]
    pub model_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MapDocumentFieldsResponse {
    pub document_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub issuer_region: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    pub fields: BTreeMap<String, FieldEntry>,
    pub engine: String,
    pub model_artifact_id: String,
    pub gguf_present: bool,
    pub gguf_valid: bool,
}

pub fn map_document_fields_from_json(json: &str) -> Result<MapDocumentFieldsResponse, String> {
    let req: MapDocumentFieldsRequest =
        serde_json::from_str(json).map_err(|e| format!("invalid JSON: {e}"))?;
    Ok(map_document_fields(&req))
}

pub fn map_document_fields(req: &MapDocumentFieldsRequest) -> MapDocumentFieldsResponse {
    let (gguf_present, gguf_valid) = inspect_optional_gguf(req.model_path.as_deref());
    let artifact_id = if gguf_valid {
        DEFAULT_ARTIFACT_ID.to_string()
    } else {
        ENGINE_ID.to_string()
    };

    let mut fields = extract_fields(&req.layout_text);
    apply_label_value_pairs(&req.layout_text, &mut fields);
    apply_mrz_hints(&req.layout_text, &mut fields);

    let document_type = infer_document_type(&req.layout_text, &fields);
    let issuer_region = fields
        .get("drivers_license_state")
        .or_else(|| fields.get("state"))
        .map(|e| e.value.clone());
    let country = fields.get("country").map(|e| e.value.clone());

    MapDocumentFieldsResponse {
        document_type,
        issuer_region,
        country,
        fields,
        engine: ENGINE_ID.to_string(),
        model_artifact_id: artifact_id,
        gguf_present,
        gguf_valid,
    }
}

fn inspect_optional_gguf(path: Option<&str>) -> (bool, bool) {
    let Some(path) = path.filter(|p| !p.trim().is_empty()) else {
        return (false, false);
    };
    let path = Path::new(path);
    if !path.is_file() {
        return (true, false);
    }
    let Ok(bytes) = std::fs::read(path) else {
        return (true, false);
    };
    let prefix = if bytes.len() > 4096 {
        &bytes[..4096]
    } else {
        &bytes
    };
    (true, parse_gguf_header_prefix(prefix).is_ok())
}

fn extract_fields(text: &str) -> BTreeMap<String, FieldEntry> {
    let mut out = BTreeMap::new();

    if let Some(ssn) = find_ssn(text) {
        insert(&mut out, "ssn", ssn, Some("Social Security Number".into()));
    }
    if let Some(aadhaar) = find_aadhaar(text) {
        insert(
            &mut out,
            "aadhaar_number",
            aadhaar,
            Some("Aadhaar number".into()),
        );
    }
    if let Some(pan) = find_pan(text) {
        insert(&mut out, "pan_number", pan, Some("PAN".into()));
    }
    if let Some(email) = find_email(text) {
        insert(&mut out, "email", email, Some("Email".into()));
    }
    if let Some(phone) = find_phone(text) {
        insert(&mut out, "phone_mobile", phone, Some("Mobile phone".into()));
    }
    for (key, label, value) in find_dates(text) {
        insert(&mut out, &key, value, Some(label));
    }
    if let Some(dl) = find_drivers_license_number(text) {
        insert(
            &mut out,
            "drivers_license_number",
            dl,
            Some("Driver license number".into()),
        );
    }
    if let Some(passport) = find_passport_number(text) {
        insert(
            &mut out,
            "passport_number",
            passport,
            Some("Passport number".into()),
        );
    }
    if let Some(state) = find_us_state(text) {
        insert(
            &mut out,
            "drivers_license_state",
            state.clone(),
            Some("State".into()),
        );
        if !out.contains_key("state") {
            insert(&mut out, "state", state, Some("State".into()));
        }
    }
    extract_name_lines(text, &mut out);
    extract_address(text, &mut out);

    out
}

fn apply_label_value_pairs(text: &str, fields: &mut BTreeMap<String, FieldEntry>) {
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some((label, value)) = trimmed.split_once('|') {
            let label = label.trim();
            let value = value.trim();
            if label.is_empty() || value.is_empty() {
                continue;
            }
            if let Some(key) = label_to_key(label) {
                insert(fields, key, value.to_string(), Some(title_case_label(label)));
            }
        }
    }
}

fn apply_mrz_hints(text: &str, fields: &mut BTreeMap<String, FieldEntry>) {
    let mut in_mrz = false;
    for line in text.lines() {
        let t = line.trim();
        if t.contains("Machine-readable zone") || t.contains("MRZ") {
            in_mrz = true;
            continue;
        }
        if in_mrz && t.starts_with("##") {
            break;
        }
        if in_mrz && t.len() >= 30 && t.chars().filter(|c| *c == '<').count() >= 2 {
            parse_mrz_line(t, fields);
        }
    }
}

fn parse_mrz_line(line: &str, fields: &mut BTreeMap<String, FieldEntry>) {
    let parts: Vec<&str> = line.split('<').filter(|s| !s.is_empty()).collect();
    if parts.len() >= 2 {
        let last = parts[0].trim();
        let first = parts.get(1).map(|s| s.trim()).unwrap_or("");
        if !last.is_empty() && last.chars().all(|c| c.is_ascii_alphabetic()) {
            insert(
                fields,
                "legal_last_name",
                last.to_string(),
                Some("Last name".into()),
            );
        }
        if !first.is_empty() && first.chars().all(|c| c.is_ascii_alphabetic()) {
            insert(
                fields,
                "legal_first_name",
                first.to_string(),
                Some("First name".into()),
            );
        }
    }
}

fn label_to_key(label: &str) -> Option<&'static str> {
    let l = label.trim().trim_end_matches(':').to_lowercase();
    let l = l.as_str();
    if l.contains("first") && l.contains("name") {
        return Some("legal_first_name");
    }
    if l.contains("middle") && l.contains("name") {
        return Some("legal_middle_name");
    }
    if l.contains("last") && l.contains("name") {
        return Some("legal_last_name");
    }
    if l.contains("full") && l.contains("name") || l == "name" || l.contains("display name") {
        return Some("display_name");
    }
    if l.contains("dob") || l.contains("date of birth") || l.contains("birth date") {
        return Some("date_of_birth");
    }
    if l.contains("expir") || l.contains("valid until") {
        return Some("drivers_license_expiry");
    }
    if l.contains("issue") && l.contains("date") {
        return Some("drivers_license_issue_date");
    }
    if l.contains("license") && (l.contains("no") || l.contains("number") || l.contains("#")) {
        return Some("drivers_license_number");
    }
    if l.contains("passport") && l.contains("no") {
        return Some("passport_number");
    }
    if l.contains("ssn") || l.contains("social security") {
        return Some("ssn");
    }
    if l.contains("email") || l.contains("e-mail") {
        return Some("email");
    }
    if l.contains("phone") || l.contains("mobile") || l.contains("cell") {
        return Some("phone_mobile");
    }
    if l.contains("address") && !l.contains("email") {
        return Some("address_line1");
    }
    if l == "city" || l.starts_with("city ") {
        return Some("city");
    }
    if l == "state" || l.contains("province") {
        return Some("state");
    }
    if l.contains("zip") || l.contains("postal") {
        return Some("postal_code");
    }
    if l.contains("sex") || l.contains("gender") {
        return Some("gender");
    }
    None
}

fn infer_document_type(text: &str, fields: &BTreeMap<String, FieldEntry>) -> String {
    let upper = text.to_uppercase();
    if fields.contains_key("aadhaar_number") || upper.contains("AADHAAR") || upper.contains("UIDAI") {
        return "aadhaar_card".into();
    }
    if fields.contains_key("pan_number")
        || upper.contains("PERMANENT ACCOUNT NUMBER")
        || upper.contains("INCOME TAX")
            && upper.contains("PAN")
    {
        return "pan_card".into();
    }
    if upper.contains("DRIVER") && upper.contains("LICENSE") || upper.contains("DL ") {
        return "drivers_license".into();
    }
    if upper.contains("PASSPORT") || fields.contains_key("passport_number") {
        return "passport".into();
    }
    if upper.contains("VEHICLE REGISTRATION") || upper.contains("TITLE NUMBER") {
        return "vehicle_registration".into();
    }
    if upper.contains("INSURANCE") || upper.contains("MEMBER ID") {
        return "insurance_card".into();
    }
    if upper.contains("SOCIAL SECURITY") || fields.contains_key("ssn") {
        return "social_security_card".into();
    }
    if upper.contains("W-2") || upper.contains("W2 ") || upper.contains("FORM W-2") {
        return "tax_w2".into();
    }
    if upper.contains("1099") || upper.contains("FORM 1099") {
        return "tax_1099".into();
    }
    if upper.contains("BANK STATEMENT") || upper.contains("ACCOUNT SUMMARY") {
        return "bank_statement".into();
    }
    if upper.contains("PAY STUB") || upper.contains("EARNINGS STATEMENT") {
        return "employment_document".into();
    }
    if upper.contains("MEDICAL RECORD")
        || upper.contains("PATIENT")
            && (upper.contains("DIAGNOSIS") || upper.contains("CHART"))
    {
        return "medical_record".into();
    }
    if upper.contains("UTILITY") || upper.contains("ELECTRIC") || upper.contains("WATER BILL") {
        return "utility_bill".into();
    }
    "other".into()
}

fn extract_name_lines(text: &str, fields: &mut BTreeMap<String, FieldEntry>) {
    for line in text.lines() {
        let t = line.trim();
        if t.starts_with('[') && t.contains(']') {
            if let Some(rest) = t.split(']').nth(1) {
                let name = rest.trim();
                if looks_like_person_name(name) && !fields.contains_key("display_name") {
                    insert(fields, "display_name", name.to_string(), Some("Full name".into()));
                    let parts: Vec<&str> = name.split_whitespace().collect();
                    if parts.len() >= 2 {
                        insert(
                            fields,
                            "legal_first_name",
                            parts[0].to_string(),
                            Some("First name".into()),
                        );
                        insert(
                            fields,
                            "legal_last_name",
                            parts[parts.len() - 1].to_string(),
                            Some("Last name".into()),
                        );
                    }
                }
            }
        }
    }
}

fn extract_address(text: &str, fields: &mut BTreeMap<String, FieldEntry>) {
    for line in text.lines() {
        let t = line.trim();
        if let Some(caps) = regex_city_state_zip(t) {
            if !fields.contains_key("city") {
                insert(fields, "city", caps.0, Some("City".into()));
            }
            if !fields.contains_key("state") {
                insert(fields, "state", caps.1.clone(), Some("State".into()));
            }
            if !fields.contains_key("postal_code") {
                insert(fields, "postal_code", caps.2, Some("ZIP code".into()));
            }
        }
        if looks_like_street(t) && !fields.contains_key("address_line1") {
            insert(fields, "address_line1", t.to_string(), Some("Address".into()));
        }
    }
}

fn insert(fields: &mut BTreeMap<String, FieldEntry>, key: &str, value: String, label: Option<String>) {
    let key = normalize_field_key(key);
    let value = value.trim().to_string();
    if value.is_empty() {
        return;
    }
    fields.insert(
        key,
        FieldEntry {
            value,
            label,
        },
    );
}

fn title_case_label(label: &str) -> String {
    label
        .trim()
        .trim_end_matches(':')
        .split_whitespace()
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                None => String::new(),
                Some(c) => c.to_uppercase().collect::<String>() + chars.as_str().to_lowercase().as_str(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn looks_like_person_name(s: &str) -> bool {
    let words: Vec<&str> = s.split_whitespace().collect();
    (2..=4).contains(&words.len())
        && words.iter().all(|w| {
            w.chars().filter(|c| c.is_alphabetic()).count() >= 2
                && w.chars().all(|c| c.is_alphabetic() || c == '-' || c == '\'')
        })
}

fn looks_like_street(s: &str) -> bool {
    let lower = s.to_lowercase();
    (lower.contains(" st")
        || lower.contains(" street")
        || lower.contains(" ave")
        || lower.contains(" rd")
        || lower.contains(" dr")
        || lower.contains(" lane")
        || lower.contains(" blvd"))
        && s.chars().any(|c| c.is_ascii_digit())
}

fn regex_city_state_zip(line: &str) -> Option<(String, String, String)> {
    // City, ST 12345 or City, ST 12345-6789
    let parts: Vec<&str> = line.split(',').collect();
    if parts.len() != 2 {
        return None;
    }
    let city = parts[0].trim();
    let rest: Vec<&str> = parts[1].trim().split_whitespace().collect();
    if city.is_empty() || rest.len() < 2 {
        return None;
    }
    let state = rest[0].trim().to_uppercase();
    if state.len() != 2 || !state.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    let zip = rest[1].trim().to_string();
    if zip.len() < 5 {
        return None;
    }
    Some((city.to_string(), state, zip))
}

fn find_ssn(text: &str) -> Option<String> {
    let lower = text.to_lowercase();
    let has_context = lower.contains("ssn")
        || lower.contains("social security")
        || lower.contains("social-security");

    if !has_context {
        return None;
    }
    for token in text.split_whitespace() {
        if token.len() == 11
            && token.chars().nth(3) == Some('-')
            && token.chars().nth(6) == Some('-')
            && token.chars().filter(|c| c.is_ascii_digit()).count() == 9
        {
            return Some(token.to_string());
        }
        let digits: String = token.chars().filter(|c| c.is_ascii_digit()).collect();
        if digits.len() == 9 {
            return Some(format!(
                "{}-{}-{}",
                &digits[0..3],
                &digits[3..5],
                &digits[5..9]
            ));
        }
    }
    None
}

/// Indian Aadhaar: 12 digits, often grouped XXXX XXXX XXXX.
fn find_aadhaar(text: &str) -> Option<String> {
    let lower = text.to_lowercase();
    if !lower.contains("aadhaar") && !lower.contains("uidai") {
        return None;
    }
    let digits: String = text.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() >= 12 {
        let slice = &digits[digits.len() - 12..];
        return Some(format!("{} {} {}", &slice[0..4], &slice[4..8], &slice[8..12]));
    }
    None
}

/// Indian PAN: AAAAA9999A (5 letters, 4 digits, 1 letter).
fn find_pan(text: &str) -> Option<String> {
    let upper = text.to_uppercase();
    if !upper.contains("PAN") && !upper.contains("PERMANENT ACCOUNT") {
        return None;
    }
    for token in text.split_whitespace() {
        let alnum: String = token
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .collect();
        if alnum.len() == 10
            && alnum[..5].chars().all(|c| c.is_ascii_alphabetic())
            && alnum[5..9].chars().all(|c| c.is_ascii_digit())
            && alnum.as_bytes()[9].is_ascii_alphabetic()
        {
            return Some(alnum.to_uppercase());
        }
    }
    None
}

fn find_email(text: &str) -> Option<String> {
    for token in text.split_whitespace() {
        if token.contains('@') && token.contains('.') {
            let e = token.trim_matches(|c: char| !c.is_ascii_graphic());
            if e.contains('@') {
                return Some(e.to_string());
            }
        }
    }
    None
}

fn find_phone(text: &str) -> Option<String> {
    for token in text.split_whitespace() {
        let digits: String = token.chars().filter(|c| c.is_ascii_digit()).collect();
        if digits.len() == 10 {
            return Some(format!(
                "({}) {}-{}",
                &digits[0..3],
                &digits[3..6],
                &digits[6..10]
            ));
        }
    }
    None
}

fn find_dates(text: &str) -> Vec<(String, String, String)> {
    let mut out = Vec::new();
    for token in text.split_whitespace() {
        if token.len() == 10
            && token.chars().nth(2) == Some('/')
            && token.chars().nth(5) == Some('/')
        {
            let lower = text.to_lowercase();
            let label = if lower.contains("expir") {
                ("drivers_license_expiry", "Expiration date")
            } else if lower.contains("issue") {
                ("drivers_license_issue_date", "Issue date")
            } else {
                ("date_of_birth", "Date of birth")
            };
            out.push((label.0.to_string(), label.1.to_string(), token.to_string()));
            break;
        }
    }
    out
}

fn find_drivers_license_number(text: &str) -> Option<String> {
    for token in text.split_whitespace() {
        let alnum: String = token
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .collect();
        if (7..=15).contains(&alnum.len()) && alnum.chars().any(|c| c.is_ascii_digit()) {
            let upper = text.to_uppercase();
            if upper.contains("DRIVER") || upper.contains("LICENSE") || upper.contains("DL") {
                return Some(alnum);
            }
        }
    }
    None
}

fn find_passport_number(text: &str) -> Option<String> {
    if !text.to_uppercase().contains("PASSPORT") {
        return None;
    }
    for token in text.split_whitespace() {
        if token.len() >= 6
            && token.len() <= 12
            && token.chars().all(|c| c.is_ascii_alphanumeric())
            && token.chars().any(|c| c.is_ascii_digit())
        {
            return Some(token.to_string());
        }
    }
    None
}

fn find_us_state(text: &str) -> Option<String> {
    const STATES: &[&str] = &[
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
        "VA", "WA", "WV", "WI", "WY", "DC",
    ];
    for token in text.split_whitespace() {
        let t = token.trim_matches(|c: char| !c.is_ascii_alphabetic()).to_uppercase();
        if t.len() == 2 && STATES.contains(&t.as_str()) {
            return Some(t);
        }
    }
    None
}

/// Bridge for future llama.cpp-class session — today delegates to heuristics.
pub struct OnDeviceGenerativeSession {
    pub artifact_id: GenerativeArtifactId,
    pub model_path: Option<String>,
}

impl GenerativeLlmSession for OnDeviceGenerativeSession {
    fn artifact_id(&self) -> &GenerativeArtifactId {
        &self.artifact_id
    }

    fn generate_schema_plan_json(&self, user_prompt: &str) -> Result<String, InferenceError> {
        let req = MapDocumentFieldsRequest {
            layout_text: user_prompt.to_string(),
            profile_schema_keys: crate::profile_keys::canonical_profile_keys()
                .iter()
                .map(|s| (*s).to_string())
                .collect(),
            model_path: self.model_path.clone(),
        };
        let resp = map_document_fields(&req);
        serde_json::to_string(&resp).map_err(|e| InferenceError::Session(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_label_value_pairs() {
        let text = r#"## Spatial label | value pairs (heuristic)
DOB | 03/15/1985
License No | D12345678
First name | Jane
Last name | Smith
"#;
        let req = MapDocumentFieldsRequest {
            layout_text: text.into(),
            profile_schema_keys: vec![],
            model_path: None,
        };
        let resp = map_document_fields(&req);
        assert_eq!(resp.fields.get("date_of_birth").unwrap().value, "03/15/1985");
        assert_eq!(
            resp.fields.get("drivers_license_number").unwrap().value,
            "D12345678"
        );
        assert_eq!(resp.fields.get("legal_first_name").unwrap().value, "Jane");
        assert!(!resp.gguf_present);
    }

    #[test]
    fn infers_drivers_license_type() {
        let text = "[1] TEXAS\n[2] DRIVER LICENSE\n[3] D12345678";
        let req = MapDocumentFieldsRequest {
            layout_text: text.into(),
            profile_schema_keys: vec![],
            model_path: None,
        };
        let resp = map_document_fields(&req);
        assert_eq!(resp.document_type, "drivers_license");
    }

    #[test]
    fn json_round_trip() {
        let json = r#"{"layout_text":"Email | test@example.com","profile_schema_keys":[]}"#;
        let resp = map_document_fields_from_json(json).unwrap();
        assert_eq!(resp.fields.get("email").unwrap().value, "test@example.com");
    }

    #[test]
    fn infers_aadhaar_and_extracts_number() {
        let text = "Government of India\nAADHAAR\n1234 5678 9012\nName | Test User";
        let req = MapDocumentFieldsRequest {
            layout_text: text.into(),
            profile_schema_keys: vec![],
            model_path: None,
        };
        let resp = map_document_fields(&req);
        assert_eq!(resp.document_type, "aadhaar_card");
        assert_eq!(
            resp.fields.get("aadhaar_number").unwrap().value,
            "1234 5678 9012"
        );
    }

    #[test]
    fn ssn_requires_context() {
        let no_ctx = MapDocumentFieldsRequest {
            layout_text: "Account 123-45-6789 summary".into(),
            profile_schema_keys: vec![],
            model_path: None,
        };
        assert!(!map_document_fields(&no_ctx).fields.contains_key("ssn"));

        let with_ctx = MapDocumentFieldsRequest {
            layout_text: "Social Security Number\n123-45-6789".into(),
            profile_schema_keys: vec![],
            model_path: None,
        };
        assert_eq!(
            map_document_fields(&with_ctx).fields.get("ssn").unwrap().value,
            "123-45-6789"
        );
    }
}
