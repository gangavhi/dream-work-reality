import Foundation

/// Stable product schema used by document understanding and autofill.
/// Scan-specific fields may still be reviewed, but final autofill uses this shape.
struct CanonicalIdentityProfile: Codable, Hashable {
    struct Person: Codable, Hashable {
        var firstName: String = ""
        var middleName: String = ""
        var lastName: String = ""
        var dob: String = ""
        var gender: String = ""
        var nationality: String = ""
    }

    struct Contact: Codable, Hashable {
        var phone: String = ""
        var email: String = ""
    }

    struct Address: Codable, Hashable {
        var street: String = ""
        var city: String = ""
        var state: String = ""
        var zip: String = ""
        var country: String = ""
    }

    struct Identity: Codable, Hashable {
        var passportNumber: String = ""
        var driverLicenseNumber: String = ""
        var ssnLast4: String = ""
    }

    var person = Person()
    var contact = Contact()
    var address = Address()
    var identity = Identity()

    static let empty = CanonicalIdentityProfile()

    static func from(suggestions: [OcrFieldSuggestion]) -> CanonicalIdentityProfile {
        let values = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        var profile = CanonicalIdentityProfile()

        profile.person.firstName = values[ProfileFieldKey.legalFirstName, default: ""]
        profile.person.middleName = values[ProfileFieldKey.legalMiddleName, default: ""]
        profile.person.lastName = values[ProfileFieldKey.legalLastName, default: ""]
        profile.person.dob = values[ProfileFieldKey.dateOfBirth, default: ""]
        profile.person.gender = values[ProfileFieldKey.gender, default: ""]
        profile.person.nationality = values[ProfileFieldKey.passportCountry]
            ?? values[ProfileFieldKey.country]
            ?? values["nationality"]
            ?? ""

        profile.contact.phone = values[ProfileFieldKey.phoneMobile]
            ?? values[ProfileFieldKey.phoneHome]
            ?? ""
        profile.contact.email = values[ProfileFieldKey.email, default: ""]

        profile.address.street = values[ProfileFieldKey.addressLine1, default: ""]
        profile.address.city = values[ProfileFieldKey.city, default: ""]
        profile.address.state = values[ProfileFieldKey.state, default: ""]
        profile.address.zip = values[ProfileFieldKey.postalCode, default: ""]
        profile.address.country = values[ProfileFieldKey.country, default: ""]

        profile.identity.passportNumber = values[ProfileFieldKey.passportNumber, default: ""]
        profile.identity.driverLicenseNumber = values[ProfileFieldKey.driversLicenseNumber, default: ""]
        profile.identity.ssnLast4 = last4(values[ProfileFieldKey.ssn, default: ""])

        return profile
    }

    private static func last4(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 4 else { return "" }
        return String(digits.suffix(4))
    }
}
