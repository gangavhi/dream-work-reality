//! Canonical household profile keys (aligned with iOS `ProfileFieldKey`).

/// Full set of keys stored in `manual_field` for known profile slots.
pub fn canonical_profile_keys() -> &'static [&'static str] {
    &[
        "display_name",
        "relationship",
        "legal_first_name",
        "legal_middle_name",
        "legal_last_name",
        "date_of_birth",
        "email",
        "phone_mobile",
        "phone_home",
        "address_line1",
        "address_line2",
        "city",
        "state",
        "postal_code",
        "country",
        "ssn",
        "filing_status",
        "drivers_license_number",
        "drivers_license_state",
        "drivers_license_issue_date",
        "drivers_license_expiry",
        "passport_number",
        "passport_country",
        "passport_expiry",
        "insurance_carrier",
        "insurance_member_id",
        "emergency_contact_name",
        "emergency_contact_phone",
    ]
}

pub fn is_canonical_profile_key(key: &str) -> bool {
    let k = key.trim();
    canonical_profile_keys().iter().any(|c| *c == k)
}

/// Maps legacy / OCR-style keys to canonical profile keys where unambiguous.
pub fn normalize_field_key(key: &str) -> String {
    let k = key.trim().to_lowercase().replace('-', "_");
    let mapped = match k.as_str() {
        "first_name" | "first" => "legal_first_name",
        "last_name" | "last" => "legal_last_name",
        "middle_name" | "middle" => "legal_middle_name",
        "full_name" => "display_name",
        "date_of_birth_mmddyyyy" | "dob" | "birth_date" => "date_of_birth",
        "address_line_1" | "addr" | "street" => "address_line1",
        "address_line_2" => "address_line2",
        "zip" | "zip_code" => "postal_code",
        "document_number" | "dl" | "license_number" | "dl_number" => "drivers_license_number",
        "license_state" | "dl_state" => "drivers_license_state",
        "issue_mmddyyyy" | "issue_date" | "issued" => "drivers_license_issue_date",
        "expiry_mmddyyyy" | "expiry" | "expiration" => "drivers_license_expiry",
        "mobile" | "cell" => "phone_mobile",
        "phone" | "home_phone" => "phone_home",
        "member_id" | "insurance_id" => "insurance_member_id",
        "carrier" => "insurance_carrier",
        "ssn_last4" => "ssn",
        other => other,
    };
    mapped.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_maps_legacy_keys() {
        assert_eq!(normalize_field_key("first_name"), "legal_first_name");
        assert_eq!(normalize_field_key("address_line_1"), "address_line1");
    }

    #[test]
    fn canonical_keys_include_drivers_license() {
        assert!(is_canonical_profile_key("drivers_license_number"));
        assert!(!is_canonical_profile_key("barcode_payload"));
    }
}
