import Foundation

struct PersonProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nickname: String

    var firstName: String?
    var lastName: String?
    var dateOfBirthMMDDYYYY: String?
    var driverLicenseNumber: String?

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

