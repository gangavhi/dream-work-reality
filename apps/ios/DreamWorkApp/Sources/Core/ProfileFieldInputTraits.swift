import SwiftUI
import UIKit

/// Keyboard and autofill hints for profile field inputs.
enum ProfileFieldInputTraits {
    static func textContentType(for key: String) -> UITextContentType? {
        switch key {
        case ProfileFieldKey.email:
            return .emailAddress
        case ProfileFieldKey.phoneMobile, ProfileFieldKey.phoneHome, ProfileFieldKey.emergencyContactPhone:
            return .telephoneNumber
        case ProfileFieldKey.addressLine1:
            return .streetAddressLine1
        case ProfileFieldKey.addressLine2:
            return .streetAddressLine2
        case ProfileFieldKey.city:
            return .addressCity
        case ProfileFieldKey.state:
            return .addressState
        case ProfileFieldKey.postalCode:
            return .postalCode
        case ProfileFieldKey.displayName,
             ProfileFieldKey.legalFirstName,
             ProfileFieldKey.legalMiddleName,
             ProfileFieldKey.legalLastName,
             ProfileFieldKey.emergencyContactName:
            return .name
        default:
            return nil
        }
    }

    static func keyboardType(for key: String) -> UIKeyboardType {
        switch key {
        case ProfileFieldKey.phoneMobile, ProfileFieldKey.phoneHome, ProfileFieldKey.emergencyContactPhone:
            return .phonePad
        case ProfileFieldKey.email:
            return .emailAddress
        case ProfileFieldKey.postalCode, ProfileFieldKey.ssn, ProfileFieldKey.bankAccountLast4:
            return .numberPad
        default:
            return .default
        }
    }

    static func textInputAutocapitalization(for key: String) -> TextInputAutocapitalization {
        switch key {
        case ProfileFieldKey.email:
            return .never
        case ProfileFieldKey.driversLicenseNumber,
             ProfileFieldKey.stateIdNumber,
             ProfileFieldKey.passportNumber,
             ProfileFieldKey.postalCode,
             ProfileFieldKey.ssn:
            return .characters
        default:
            return .words
        }
    }

    static func autocorrectionDisabled(for key: String) -> Bool {
        switch key {
        case ProfileFieldKey.email,
             ProfileFieldKey.driversLicenseNumber,
             ProfileFieldKey.stateIdNumber,
             ProfileFieldKey.passportNumber,
             ProfileFieldKey.postalCode,
             ProfileFieldKey.ssn,
             ProfileFieldKey.dateOfBirth,
             ProfileFieldKey.driversLicenseIssueDate,
             ProfileFieldKey.driversLicenseExpiry,
             ProfileFieldKey.passportExpiry:
            return true
        default:
            return false
        }
    }
}
