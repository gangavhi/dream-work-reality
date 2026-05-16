//! Stage 3 rules-only person resolution (deterministic scoring, no LLM).

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PersonResolution {
    MatchExisting,
    NewPerson,
    Ambiguous,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExistingPerson {
    pub person_id: String,
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolutionCandidate {
    pub person_id: String,
    pub score: f64,
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResolvePersonResult {
    pub resolution: PersonResolution,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub person_id: Option<String>,
    pub confidence: f64,
    pub candidates: Vec<ResolutionCandidate>,
}

const MATCH_THRESHOLD: f64 = 0.72;
const NEW_PERSON_THRESHOLD: f64 = 0.38;
const AMBIGUOUS_SCORE_GAP: f64 = 0.08;

/// One government-id field match is sufficient to link profiles.
const SCORE_EXACT_ID: f64 = 0.80;
const SCORE_NAME_FUZZY_MAX: f64 = 0.28;
const SCORE_DOB_EXACT: f64 = 0.40;
const SCORE_NAME_DOB_COMBO: f64 = 0.35;
const SCORE_ADDRESS: f64 = 0.10;
const SCORE_ZIP: f64 = 0.08;
const SCORE_DISPLAY_NAME: f64 = 0.07;
const SCORE_PROFILE_KEY: f64 = 0.05;

/// Score incoming fields against known persons and pick a resolution.
pub fn resolve_person(
    query_fields: &BTreeMap<String, String>,
    existing: &[ExistingPerson],
) -> ResolvePersonResult {
    if existing.is_empty() {
        return ResolvePersonResult {
            resolution: PersonResolution::NewPerson,
            person_id: None,
            confidence: 1.0,
            candidates: vec![],
        };
    }

    let query = normalize_fields(query_fields);
    let mut candidates: Vec<ResolutionCandidate> = existing
        .iter()
        .map(|person| {
            let norm = normalize_fields(&person.fields);
            let (score, reasons) = score_pair(&query, &norm);
            ResolutionCandidate {
                person_id: person.person_id.clone(),
                score,
                reasons,
            }
        })
        .collect();

    candidates.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.person_id.cmp(&b.person_id))
    });

    let top_score = candidates.first().map(|c| c.score).unwrap_or(0.0);
    let second_score = candidates.get(1).map(|c| c.score).unwrap_or(0.0);
    let gap = top_score - second_score;

    let exact_id_persons: std::collections::BTreeSet<&str> = candidates
        .iter()
        .filter(|c| {
            c.reasons.iter().any(|r| {
                matches!(
                    r.as_str(),
                    "drivers_license_number_exact"
                        | "passport_number_exact"
                        | "ssn_last4_exact"
                )
            })
        })
        .map(|c| c.person_id.as_str())
        .collect();

    let resolution = if exact_id_persons.len() > 1 {
        PersonResolution::Ambiguous
    } else if top_score >= MATCH_THRESHOLD && gap >= AMBIGUOUS_SCORE_GAP {
        PersonResolution::MatchExisting
    } else if top_score >= MATCH_THRESHOLD && gap < AMBIGUOUS_SCORE_GAP {
        PersonResolution::Ambiguous
    } else if top_score < NEW_PERSON_THRESHOLD {
        PersonResolution::NewPerson
    } else if top_score >= NEW_PERSON_THRESHOLD && gap < AMBIGUOUS_SCORE_GAP {
        PersonResolution::Ambiguous
    } else {
        PersonResolution::NewPerson
    };

    let person_id = match resolution {
        PersonResolution::MatchExisting => candidates.first().map(|c| c.person_id.clone()),
        PersonResolution::Ambiguous | PersonResolution::NewPerson => None,
    };

    let confidence = match resolution {
        PersonResolution::MatchExisting => top_score.min(1.0),
        PersonResolution::NewPerson => (1.0 - top_score).clamp(0.5, 1.0),
        PersonResolution::Ambiguous => {
            if top_score > 0.0 {
                gap.min(top_score).clamp(0.35, 0.85)
            } else {
                0.5
            }
        }
    };

    ResolvePersonResult {
        resolution,
        person_id,
        confidence,
        candidates,
    }
}

/// Flatten [`crate::ingestion::ManualEntry`] fields into a map for resolution.
pub fn manual_entry_to_fields(entry: &crate::ingestion::ManualEntry) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for f in &entry.fields {
        if f.key.trim().is_empty() || f.value.trim().is_empty() {
            continue;
        }
        out.insert(f.key.clone(), f.value.clone());
    }
    out
}

#[derive(Debug, Clone)]
struct NormalizedFields {
    drivers_license_number: Option<String>,
    passport_number: Option<String>,
    ssn_last4: Option<String>,
    name_key: Option<String>,
    date_of_birth: Option<String>,
    address_line1: Option<String>,
    postal_code: Option<String>,
    display_name: Option<String>,
    profile_key: Option<String>,
}

fn score_pair(query: &NormalizedFields, existing: &NormalizedFields) -> (f64, Vec<String>) {
    let mut score = 0.0_f64;
    let mut reasons = Vec::new();

    if exact_id_match(
        &query.drivers_license_number,
        &existing.drivers_license_number,
    ) {
        score += SCORE_EXACT_ID;
        reasons.push("drivers_license_number_exact".to_string());
    }
    if exact_id_match(&query.passport_number, &existing.passport_number) {
        score += SCORE_EXACT_ID;
        reasons.push("passport_number_exact".to_string());
    }
    if exact_id_match(&query.ssn_last4, &existing.ssn_last4) {
        score += SCORE_EXACT_ID;
        reasons.push("ssn_last4_exact".to_string());
    }

    if let (Some(qn), Some(en)) = (&query.name_key, &existing.name_key) {
        let sim = name_similarity(qn, en);
        if sim >= 0.92 {
            score += SCORE_NAME_FUZZY_MAX;
            reasons.push("name_exact".to_string());
        } else if sim >= 0.65 {
            score += SCORE_NAME_FUZZY_MAX * sim;
            reasons.push(format!("name_fuzzy:{sim:.2}"));
        }
    }

    if dob_equal(&query.date_of_birth, &existing.date_of_birth) {
        score += SCORE_DOB_EXACT;
        reasons.push("date_of_birth_exact".to_string());
    }

    if let (Some(qa), Some(ea)) = (&query.address_line1, &existing.address_line1) {
        if name_similarity(qa, ea) >= 0.90 {
            score += SCORE_ADDRESS;
            reasons.push("address_line1_match".to_string());
        }
    }

    if let (Some(qz), Some(ez)) = (&query.postal_code, &existing.postal_code) {
        if qz == ez {
            score += SCORE_ZIP;
            reasons.push("postal_code_exact".to_string());
        }
    }

    if let (Some(qd), Some(ed)) = (&query.display_name, &existing.display_name) {
        if name_similarity(qd, ed) >= 0.95 {
            score += SCORE_DISPLAY_NAME;
            reasons.push("display_name_match".to_string());
        }
    }

    if let (Some(qk), Some(ek)) = (&query.profile_key, &existing.profile_key) {
        if qk == ek {
            score += SCORE_PROFILE_KEY;
            reasons.push("profile_key_exact".to_string());
        }
    }

    let has_name = reasons
        .iter()
        .any(|r| r.starts_with("name_exact") || r.starts_with("name_fuzzy"));
    let has_dob = reasons.iter().any(|r| r == "date_of_birth_exact");
    if has_name && has_dob {
        score += SCORE_NAME_DOB_COMBO;
        reasons.push("name_and_dob_combo".to_string());
    }

    (score.min(1.0), reasons)
}

fn exact_id_match(left: &Option<String>, right: &Option<String>) -> bool {
    match (left, right) {
        (Some(a), Some(b)) if !a.is_empty() && !b.is_empty() => a == b,
        _ => false,
    }
}

fn normalize_fields(fields: &BTreeMap<String, String>) -> NormalizedFields {
    let get = |keys: &[&str]| -> Option<String> {
        keys.iter()
            .find_map(|k| fields.get(*k))
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    };

    let display_name = get(&["display_name"]);
    let legal_first = get(&["legal_first_name", "first_name"]);
    let legal_last = get(&["legal_last_name", "last_name"]);
    let legal_middle = get(&["legal_middle_name", "middle_name"]);
    let full_name = get(&["full_name", "name"]);

    let name_key = build_name_key(
        legal_first.as_deref(),
        legal_middle.as_deref(),
        legal_last.as_deref(),
        full_name.as_deref(),
        display_name.as_deref(),
    );

    let ssn_raw = get(&["ssn_last4", "ssn"]);
    let ssn_last4 = ssn_raw.as_deref().map(normalize_ssn_last4).filter(|s| s.len() == 4);

    NormalizedFields {
        drivers_license_number: get(&["drivers_license_number", "dl_number"]).map(normalize_id),
        passport_number: get(&["passport_number"]).map(normalize_id),
        ssn_last4,
        name_key,
        date_of_birth: get(&["date_of_birth", "dob", "dob_mmddyyyy"]).map(normalize_dob),
        address_line1: get(&["address_line1", "address1", "address"]).map(normalize_address),
        postal_code: get(&["postal_code", "zip", "zip_code"]).map(normalize_zip),
        display_name: display_name.map(|s| normalize_name(&s)),
        profile_key: get(&["profile_key"]).map(|s| normalize_name(&s)),
    }
}

fn build_name_key(
    first: Option<&str>,
    middle: Option<&str>,
    last: Option<&str>,
    full: Option<&str>,
    display: Option<&str>,
) -> Option<String> {
    let mut parts: Vec<String> = Vec::new();
    if let Some(f) = first {
        parts.push(normalize_name(f));
    }
    if let Some(m) = middle {
        let n = normalize_name(m);
        if !n.is_empty() {
            parts.push(n);
        }
    }
    if let Some(l) = last {
        parts.push(normalize_name(l));
    }
    if parts.len() >= 2 {
        return Some(parts.join(" "));
    }
    if let Some(full) = full {
        let n = normalize_name(full);
        if !n.is_empty() {
            return Some(n);
        }
    }
    display.map(|s| normalize_name(s)).filter(|s| !s.is_empty())
}

fn normalize_id(value: String) -> String {
    value
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase())
        .collect()
}

fn normalize_ssn_last4(value: &str) -> String {
    let digits: String = value.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() >= 4 {
        digits[digits.len() - 4..].to_string()
    } else {
        digits
    }
}

fn normalize_dob(value: String) -> String {
    let digits: String = value.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() >= 8 {
        digits[..8].to_string()
    } else if digits.len() == 6 {
        let yy: u32 = digits[4..6].parse().unwrap_or(0);
        let century = if yy >= 30 { "19" } else { "20" };
        format!("{century}{digits}")
    } else {
        digits
    }
}

fn dob_equal(left: &Option<String>, right: &Option<String>) -> bool {
    let (Some(a), Some(b)) = (left, right) else {
        return false;
    };
    if a.is_empty() || b.is_empty() {
        return false;
    }
    if a == b {
        return true;
    }
    let forms_a = dob_canonical_forms(a);
    let forms_b = dob_canonical_forms(b);
    forms_a.iter().any(|fa| forms_b.iter().any(|fb| fa == fb))
}

/// Emit both `YYYYMMDD` and `MMDDYYYY` eight-digit keys when parseable.
fn dob_canonical_forms(digits8: &str) -> Vec<String> {
    if digits8.len() < 8 {
        return vec![digits8.to_string()];
    }
    let d = &digits8[..8];
    let mut out = vec![d.to_string()];
    let yyyy = d[0..4].parse::<u32>().unwrap_or(0);
    let mm = d[4..6].parse::<u32>().unwrap_or(0);
    let dd = d[6..8].parse::<u32>().unwrap_or(0);
    if (1900..2100).contains(&yyyy) && (1..=12).contains(&mm) && (1..=31).contains(&dd) {
        out.push(format!("{mm:02}{dd:02}{yyyy:04}"));
    }
    let mm_lead = d[0..2].parse::<u32>().unwrap_or(0);
    let dd_mid = d[2..4].parse::<u32>().unwrap_or(0);
    let yyyy_tail = d[4..8].parse::<u32>().unwrap_or(0);
    if (1..=12).contains(&mm_lead) && (1..=31).contains(&dd_mid) && (1900..2100).contains(&yyyy_tail)
    {
        out.push(format!("{yyyy_tail:04}{mm_lead:02}{dd_mid:02}"));
    }
    out.sort();
    out.dedup();
    out
}

fn normalize_zip(value: String) -> String {
    let digits: String = value.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() >= 5 {
        digits[..5].to_string()
    } else {
        digits
    }
}

fn normalize_address(value: String) -> String {
    normalize_name(&value)
}

fn normalize_name(value: &str) -> String {
    value
        .to_ascii_lowercase()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || c.is_ascii_whitespace())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn name_similarity(a: &str, b: &str) -> f64 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    if a == b {
        return 1.0;
    }
    let dist = levenshtein(a.as_bytes(), b.as_bytes());
    let max_len = a.len().max(b.len()) as f64;
    1.0 - (dist as f64 / max_len)
}

fn levenshtein(a: &[u8], b: &[u8]) -> usize {
    let n = a.len();
    let m = b.len();
    if n == 0 {
        return m;
    }
    if m == 0 {
        return n;
    }
    let mut prev: Vec<usize> = (0..=m).collect();
    let mut curr = vec![0; m + 1];
    for (i, &ca) in a.iter().enumerate() {
        curr[0] = i + 1;
        for (j, &cb) in b.iter().enumerate() {
            let cost = if ca == cb { 0 } else { 1 };
            curr[j + 1] = (prev[j + 1] + 1)
                .min(curr[j] + 1)
                .min(prev[j] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    prev[m]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn person(id: &str, fields: &[(&str, &str)]) -> ExistingPerson {
        ExistingPerson {
            person_id: id.to_string(),
            fields: fields
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        }
    }

    fn fields(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn exact_drivers_license_matches_existing() {
        let existing = vec![person(
            "person-a",
            &[
                ("display_name", "Alex Rivera"),
                ("drivers_license_number", "D1234567"),
            ],
        )];
        let query = fields(&[("drivers_license_number", "D-1234567")]);
        let result = resolve_person(&query, &existing);
        assert_eq!(result.resolution, PersonResolution::MatchExisting);
        assert_eq!(result.person_id.as_deref(), Some("person-a"));
        assert!(result.confidence >= MATCH_THRESHOLD);
        assert!(result.candidates[0]
            .reasons
            .contains(&"drivers_license_number_exact".to_string()));
    }

    #[test]
    fn fuzzy_name_and_dob_match() {
        let existing = vec![person(
            "person-b",
            &[
                ("legal_first_name", "Jordan"),
                ("legal_last_name", "Lee"),
                ("date_of_birth", "1990-04-15"),
            ],
        )];
        let query = fields(&[
            ("legal_first_name", "Jordon"),
            ("legal_last_name", "Lee"),
            ("date_of_birth", "04/15/1990"),
        ]);
        let result = resolve_person(&query, &existing);
        assert_eq!(result.resolution, PersonResolution::MatchExisting);
        assert_eq!(result.person_id.as_deref(), Some("person-b"));
    }

    #[test]
    fn weak_signals_suggest_new_person() {
        let existing = vec![person(
            "person-c",
            &[
                ("display_name", "Sam Taylor"),
                ("postal_code", "90210"),
            ],
        )];
        let query = fields(&[("display_name", "Riley Morgan"), ("postal_code", "10001")]);
        let result = resolve_person(&query, &existing);
        assert_eq!(result.resolution, PersonResolution::NewPerson);
        assert!(result.person_id.is_none());
    }

    #[test]
    fn ambiguous_when_two_close_candidates() {
        let existing = vec![
            person(
                "person-d1",
                &[
                    ("legal_first_name", "Taylor"),
                    ("legal_last_name", "Morgan"),
                    ("date_of_birth", "1985-01-02"),
                    ("postal_code", "94107"),
                ],
            ),
            person(
                "person-d2",
                &[
                    ("legal_first_name", "Tyler"),
                    ("legal_last_name", "Morgan"),
                    ("date_of_birth", "1985-01-02"),
                    ("postal_code", "94107"),
                ],
            ),
        ];
        let query = fields(&[
            ("legal_first_name", "Taylor"),
            ("legal_last_name", "Morgan"),
            ("date_of_birth", "1985-01-02"),
            ("postal_code", "94107"),
        ]);
        let result = resolve_person(&query, &existing);
        assert_eq!(result.resolution, PersonResolution::Ambiguous);
        assert!(result.person_id.is_none());
        let gap = result.candidates[0].score - result.candidates[1].score;
        assert!(gap < AMBIGUOUS_SCORE_GAP);
    }

    #[test]
    fn passport_exact_match() {
        let existing = vec![person("person-e", &[("passport_number", "X12345678")])];
        let query = fields(&[("passport_number", "x12345678")]);
        let result = resolve_person(&query, &existing);
        assert_eq!(result.resolution, PersonResolution::MatchExisting);
        assert_eq!(result.person_id.as_deref(), Some("person-e"));
    }

    #[test]
    fn ssn_last4_derived_from_full_ssn() {
        let existing = vec![person("person-f", &[("ssn_last4", "4321")])];
        let query = fields(&[("ssn", "123-45-4321")]);
        let result = resolve_person(&query, &existing);
        assert_eq!(result.resolution, PersonResolution::MatchExisting);
        assert_eq!(result.person_id.as_deref(), Some("person-f"));
    }

    #[test]
    fn empty_repository_is_new_person() {
        let query = fields(&[("display_name", "Anyone")]);
        let result = resolve_person(&query, &[]);
        assert_eq!(result.resolution, PersonResolution::NewPerson);
        assert_eq!(result.confidence, 1.0);
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn profile_key_low_weight_match() {
        let existing = vec![person(
            "person-g",
            &[
                ("display_name", "Unrelated"),
                ("profile_key", "casey-lee"),
            ],
        )];
        let query = fields(&[("profile_key", "casey-lee")]);
        let result = resolve_person(&query, &existing);
        assert!(result.candidates[0]
            .reasons
            .contains(&"profile_key_exact".to_string()));
    }
}
