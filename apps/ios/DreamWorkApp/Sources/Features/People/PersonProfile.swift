import Foundation

struct PersonProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nickname: String

    var firstName: String?
    var lastName: String?
    var dateOfBirthMMDDYYYY: String?
    var height: String?
    var eyeColor: String?
    // Active driver license summary fields (kept for convenience / quick fill).
    var driverLicenseNumber: String?
    var driverLicenseIssueMMDDYYYY: String?
    var driverLicenseExpiryMMDDYYYY: String?
    var driverLicenseState: String?

    var email: String?
    var ssnLast4: String?
    var mobilePhone: String?
    var insuranceProvider: String?
    var policyNumber: String?

    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var state: String?
    var postalCode: String?

    var familyMembers: [FamilyMember] = []
    var emergencyContacts: [EmergencyContact] = []

    // Full DL history. Only one should be active at a time.
    var driverLicenses: [DriverLicense] = []

    // Other documents (e.g. passports). Most-recent first.
    var documents: [ScannedDocument] = []

    // Arbitrary key/value fields extracted by GenAI. This lets us persist new fields
    // without changing the schema for every new document type.
    var genAIFields: [String: String] = [:]

    var updatedAt: Date = Date()

    var displayTitle: String {
        let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty { return nick }
        let fn = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Unnamed Person" : full
    }
}

struct DriverLicense: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var number: String?
    var state: String?
    var issueMMDDYYYY: String?
    var expiryMMDDYYYY: String?
    var isActive: Bool = true
    var capturedAt: Date = Date()
}

struct ScannedDocument: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    // e.g. "driver_license", "passport"
    var type: String
    var number: String?
    var issueMMDDYYYY: String?
    var expiryMMDDYYYY: String?
    var rawText: String?
    var capturedAt: Date = Date()
}

struct FamilyMember: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var relationship: String?
    var dateOfBirthMMDDYYYY: String?
    var phone: String?
}

struct EmergencyContact: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var relationship: String?
    var phone: String?
}

