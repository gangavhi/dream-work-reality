import Foundation

enum FormCategory: String, CaseIterable, Identifiable {
    case tax = "Tax"
    case medical = "Medical"
    case school = "School"
    case immigration = "Immigration"
    case appointment = "Appointments"
    case generic = "Generic"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .tax: return "dollarsign.circle"
        case .medical: return "cross.case"
        case .school: return "graduationcap"
        case .immigration: return "globe.americas"
        case .appointment: return "calendar"
        case .generic: return "doc.text"
        }
    }

    var subtitle: String {
        switch self {
        case .tax: return "W-4, 1040 helpers, withholding"
        case .medical: return "Intake, insurance, pediatric"
        case .school: return "Enrollment, emergency contacts"
        case .immigration: return "Visa and travel documents"
        case .appointment: return "Clinic, DMV, generic booking"
        case .generic: return "Copy any stored profile field"
        }
    }
}

struct FormFieldRequirement: Identifiable, Hashable {
    let profileKey: String
    let label: String
    let hint: String?

    var id: String { profileKey }
}

struct FormTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let category: FormCategory
    let summary: String
    let fields: [FormFieldRequirement]
}

enum FormTemplateLibrary {
    static let all: [FormTemplate] = [
        irsW4,
        pediatricIntake,
        schoolEmergency,
        genericProfile,
    ]

    static func templates(in category: FormCategory) -> [FormTemplate] {
        all.filter { $0.category == category }
    }

    static let irsW4 = FormTemplate(
        id: "irs-w4",
        name: "IRS Form W-4",
        category: .tax,
        summary: "Employee withholding certificate — common employer payroll form.",
        fields: [
            FormFieldRequirement(profileKey: ProfileFieldKey.legalFirstName, label: "First name", hint: "Step 1(a)"),
            FormFieldRequirement(profileKey: ProfileFieldKey.legalMiddleName, label: "Middle initial", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.legalLastName, label: "Last name", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.displayName, label: "Full name (if different)", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.ssn, label: "Social Security number", hint: "Step 1(b)"),
            FormFieldRequirement(profileKey: ProfileFieldKey.addressLine1, label: "Home address", hint: "Step 1(c)"),
            FormFieldRequirement(profileKey: ProfileFieldKey.city, label: "City", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.state, label: "State", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.postalCode, label: "ZIP code", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.filingStatus, label: "Filing status", hint: "Step 1(c) checkbox group"),
        ]
    )

    static let pediatricIntake = FormTemplate(
        id: "pediatric-intake",
        name: "Pediatric intake",
        category: .medical,
        summary: "Child patient demographics plus parent/guardian contact.",
        fields: [
            FormFieldRequirement(profileKey: ProfileFieldKey.displayName, label: "Child name", hint: "Patient"),
            FormFieldRequirement(profileKey: ProfileFieldKey.dateOfBirth, label: "Child date of birth", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.insuranceCarrier, label: "Insurance carrier", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.insuranceMemberId, label: "Member / policy ID", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.emergencyContactName, label: "Parent / guardian name", hint: "Use spouse or self profile when filling"),
            FormFieldRequirement(profileKey: ProfileFieldKey.emergencyContactPhone, label: "Parent / guardian phone", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.email, label: "Contact email", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.addressLine1, label: "Home address", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.city, label: "City", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.state, label: "State", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.postalCode, label: "ZIP", hint: nil),
        ]
    )

    static let schoolEmergency = FormTemplate(
        id: "school-emergency",
        name: "School emergency card",
        category: .school,
        summary: "Student info and emergency contacts for school forms.",
        fields: [
            FormFieldRequirement(profileKey: ProfileFieldKey.displayName, label: "Student name", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.dateOfBirth, label: "Student DOB", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.addressLine1, label: "Home address", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.phoneHome, label: "Home phone", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.emergencyContactName, label: "Emergency contact", hint: nil),
            FormFieldRequirement(profileKey: ProfileFieldKey.emergencyContactPhone, label: "Emergency phone", hint: nil),
        ]
    )

    static let genericProfile = FormTemplate(
        id: "generic-profile",
        name: "All profile fields",
        category: .generic,
        summary: "Copy any stored value for ad-hoc web or app forms.",
        fields: ProfileSchema.allFields.map {
            FormFieldRequirement(profileKey: $0.key, label: $0.label, hint: nil)
        }
    )
}
