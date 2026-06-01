import Foundation

/// Maps canonical profile fields into standardized, document-type-specific schemas for storage and APIs.
enum SchemaMappingEngine {
    struct StandardizedField: Codable, Hashable {
        let key: String
        let value: String
        let confidence: Double
        let requiresManualReview: Bool
    }

    struct StandardizedDocumentOutput: Codable, Hashable {
        let documentType: String
        let fields: [StandardizedField]
        let requiresManualReview: Bool
        let fieldsRequiringReview: [String]

        func jsonString(pretty: Bool = false) -> String? {
            let encoder = JSONEncoder()
            if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
            guard let data = try? encoder.encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    static func map(
        openDocumentType: String,
        suggestions: [OcrFieldSuggestion]
    ) -> StandardizedDocumentOutput {
        let normalizedType = openDocumentType
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let schemaKeys = schemaKeys(for: normalizedType)
        let values = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0) })

        let fields = schemaKeys.compactMap { schemaKey -> StandardizedField? in
            if schemaKey == "address" || schemaKey == "service_address" {
                return composeAddressField(from: values, documentType: normalizedType)
            }
            guard let profileKey = profileKey(forSchemaKey: schemaKey, documentType: normalizedType),
                  let suggestion = values[profileKey],
                  !suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return StandardizedField(
                    key: schemaKey,
                    value: "",
                    confidence: 0,
                    requiresManualReview: false
                )
            }
            return StandardizedField(
                key: schemaKey,
                value: suggestion.value,
                confidence: suggestion.confidenceScore,
                requiresManualReview: suggestion.requiresManualConfirmation
            )
        }

        let reviewKeys = fields.filter(\.requiresManualReview).map(\.key)
        return StandardizedDocumentOutput(
            documentType: normalizedType,
            fields: fields,
            requiresManualReview: !reviewKeys.isEmpty,
            fieldsRequiringReview: reviewKeys
        )
    }

    static func schemaKeys(for documentType: String) -> [String] {
        switch documentType {
        case "drivers_license", "driver_license", "driving_licence":
            return [
                "first_name", "last_name", "dob", "license_number",
                "issue_state", "issue_date", "expiration_date", "address",
            ]
        case "passport":
            return [
                "first_name", "last_name", "dob", "passport_number",
                "nationality", "issue_date", "expiration_date",
            ]
        case "insurance_card":
            return ["member_name", "member_id", "group_number", "carrier", "plan_type"]
        case "state_id", "identification_card":
            return ["first_name", "last_name", "dob", "id_number", "issue_state", "expiration_date", "address"]
        case "utility_bill":
            return ["account_holder", "service_address", "provider", "account_number", "billing_date"]
        case "medical_record":
            return ["patient_name", "dob", "member_id", "provider", "visit_date"]
        case "bank_statement":
            return ["account_holder", "bank_name", "account_last4", "statement_date"]
        case "social_security_card", "ssn_card":
            return ["full_name", "ssn"]
        case "tax_w2", "tax_1099", "tax_form":
            return ["employee_name", "employer_name", "tax_year", "ssn_last4", "wages"]
        default:
            return ["document_type", "full_name", "dob", "id_number", "address", "phone", "email"]
        }
    }

    private static func profileKey(forSchemaKey schemaKey: String, documentType: String) -> String? {
        switch (documentType, schemaKey) {
        case (_, "first_name"): return ProfileFieldKey.legalFirstName
        case (_, "last_name"): return ProfileFieldKey.legalLastName
        case (_, "full_name"), (_, "member_name"), (_, "account_holder"), (_, "employee_name"), (_, "patient_name"):
            return ProfileFieldKey.displayName
        case (_, "dob"): return ProfileFieldKey.dateOfBirth
        case ("drivers_license", "license_number"), ("state_id", "id_number"), (_, "id_number"):
            return documentType.contains("passport")
                ? ProfileFieldKey.passportNumber
                : ProfileFieldKey.driversLicenseNumber
        case ("passport", "passport_number"): return ProfileFieldKey.passportNumber
        case (_, "issue_state"): return ProfileFieldKey.driversLicenseState
        case ("drivers_license", "issue_date"): return ProfileFieldKey.driversLicenseIssueDate
        case ("drivers_license", "expiration_date"), ("passport", "expiration_date"), ("state_id", "expiration_date"):
            return documentType == "passport"
                ? ProfileFieldKey.passportExpiry
                : ProfileFieldKey.driversLicenseExpiry
        case ("passport", "nationality"): return ProfileFieldKey.passportCountry
        case (_, "address"), (_, "service_address"):
            return ProfileFieldKey.addressLine1
        case ("insurance_card", "member_id"): return ProfileFieldKey.insuranceMemberId
        case ("insurance_card", "carrier"): return ProfileFieldKey.insuranceCarrier
        case ("utility_bill", "provider"): return ProfileFieldKey.utilityProvider
        case ("bank_statement", "bank_name"): return ProfileFieldKey.bankName
        case ("bank_statement", "account_last4"): return ProfileFieldKey.bankAccountLast4
        case (_, "phone"): return ProfileFieldKey.phoneMobile
        case (_, "email"): return ProfileFieldKey.email
        case ("social_security_card", "ssn"), ("ssn_card", "ssn"): return ProfileFieldKey.ssn
        case ("tax_w2", "employer_name"), ("tax_1099", "employer_name"): return ProfileFieldKey.employerName
        case ("tax_w2", "tax_year"), ("tax_1099", "tax_year"): return ProfileFieldKey.taxYear
        default: return nil
        }
    }

    private static func composeAddressField(
        from values: [String: OcrFieldSuggestion],
        documentType: String
    ) -> StandardizedField {
        let line1 = values[ProfileFieldKey.addressLine1]?.value ?? ""
        let city = values[ProfileFieldKey.city]?.value ?? ""
        let state = values[ProfileFieldKey.state]?.value ?? ""
        let zip = values[ProfileFieldKey.postalCode]?.value ?? ""
        let parts = [line1, [city, state, zip].filter { !$0.isEmpty }.joined(separator: ", ")]
            .filter { !$0.isEmpty }
        let composed = parts.joined(separator: ", ")
        let scores = [
            values[ProfileFieldKey.addressLine1]?.confidenceScore,
            values[ProfileFieldKey.city]?.confidenceScore,
            values[ProfileFieldKey.state]?.confidenceScore,
            values[ProfileFieldKey.postalCode]?.confidenceScore,
        ].compactMap { $0 }
        let confidence = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        let requiresReview = [
            values[ProfileFieldKey.addressLine1],
            values[ProfileFieldKey.city],
            values[ProfileFieldKey.state],
            values[ProfileFieldKey.postalCode],
        ].compactMap { $0 }.contains { $0.requiresManualConfirmation }
        _ = documentType
        return StandardizedField(
            key: "address",
            value: composed,
            confidence: confidence,
            requiresManualReview: requiresReview
        )
    }
}
