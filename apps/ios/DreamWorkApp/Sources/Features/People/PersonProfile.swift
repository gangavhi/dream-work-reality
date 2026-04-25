import Foundation

struct PersonProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nickname: String

    var firstName: String?
    var lastName: String?
    var dateOfBirthMMDDYYYY: String?
    // Active driver license summary fields (kept for convenience / quick fill).
    var driverLicenseNumber: String?
    var driverLicenseIssueMMDDYYYY: String?
    var driverLicenseExpiryMMDDYYYY: String?
    var driverLicenseState: String?

    var email: String?
    var ssnLast4: String?
    var mobilePhone: String?

    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var state: String?
    var postalCode: String?

    var familyMembers: [FamilyMember] = []
    var emergencyContacts: [EmergencyContact] = []

    // Full DL history. Only one should be active at a time.
    var driverLicenses: [DriverLicense] = []

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

