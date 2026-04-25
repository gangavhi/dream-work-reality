import SwiftUI

struct EditPersonProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PersonProfile
    let onSave: (PersonProfile) -> Void

    @State private var isPresentingScanner = false
    @State private var banner: String?

    @State private var nickname: String
    @State private var firstName: String
    @State private var lastName: String
    @State private var dob: String
    @State private var dlNumber: String
    @State private var email: String
    @State private var mobile: String
    @State private var ssnLast4: String
    @State private var address1: String
    @State private var address2: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String
    @State private var familyMembers: [FamilyMember]
    @State private var emergencyContacts: [EmergencyContact]

    @State private var newFamilyName: String = ""
    @State private var newFamilyRelationship: String = ""
    @State private var newFamilyDob: String = ""
    @State private var newFamilyPhone: String = ""

    @State private var newEmergencyName: String = ""
    @State private var newEmergencyRelationship: String = ""
    @State private var newEmergencyPhone: String = ""

    init(initial: PersonProfile, onSave: @escaping (PersonProfile) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _nickname = State(initialValue: initial.nickname)
        _firstName = State(initialValue: initial.firstName ?? "")
        _lastName = State(initialValue: initial.lastName ?? "")
        _dob = State(initialValue: initial.dateOfBirthMMDDYYYY ?? "")
        _dlNumber = State(initialValue: initial.driverLicenseNumber ?? "")
        _email = State(initialValue: initial.email ?? "")
        _mobile = State(initialValue: initial.mobilePhone ?? "")
        _ssnLast4 = State(initialValue: initial.ssnLast4 ?? "")
        _address1 = State(initialValue: initial.addressLine1 ?? "")
        _address2 = State(initialValue: initial.addressLine2 ?? "")
        _city = State(initialValue: initial.city ?? "")
        _state = State(initialValue: initial.state ?? "")
        _zip = State(initialValue: initial.postalCode ?? "")
        _familyMembers = State(initialValue: initial.familyMembers)
        _emergencyContacts = State(initialValue: initial.emergencyContacts)
    }

    var body: some View {
        Form {
            if let banner {
                Section {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Scan") {
                Button("Scan ID to autofill") {
                    isPresentingScanner = true
                }
                .buttonStyle(.borderedProminent)

                Text("On Simulator you can import from Downloads/Photos/Files inside the Scan screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Profile") {
                TextField("Nickname (e.g. Sreeni)", text: $nickname)
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Mobile", text: $mobile)
                    .keyboardType(.phonePad)
            }

            Section("ID") {
                TextField("DOB (MM/dd/yyyy)", text: $dob)
                TextField("Driver License Number", text: $dlNumber)
                SecureField("SSN (last 4)", text: $ssnLast4)
                    .keyboardType(.numberPad)
            }

            Section("Address") {
                TextField("Street Address", text: $address1)
                TextField("Apt / Unit (optional)", text: $address2)
                TextField("City", text: $city)
                TextField("State", text: $state)
                TextField("ZIP", text: $zip)
            }

            Section("Family") {
                if familyMembers.isEmpty {
                    Text("No family members yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(familyMembers) { member in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                        Text([member.relationship, member.phone, member.dateOfBirthMMDDYYYY].compactMap { $0?.nilIfEmpty }.joined(separator: " • "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    familyMembers.remove(atOffsets: idx)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $newFamilyName)
                    TextField("Relationship", text: $newFamilyRelationship)
                    TextField("DOB (MM/dd/yyyy)", text: $newFamilyDob)
                    TextField("Phone", text: $newFamilyPhone)
                        .keyboardType(.phonePad)
                    Button("Add family member") {
                        let name = newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let member = FamilyMember(
                            name: name,
                            relationship: newFamilyRelationship.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                            dateOfBirthMMDDYYYY: newFamilyDob.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                            phone: newFamilyPhone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        )
                        familyMembers.append(member)
                        newFamilyName = ""
                        newFamilyRelationship = ""
                        newFamilyDob = ""
                        newFamilyPhone = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Emergency Contact") {
                if emergencyContacts.isEmpty {
                    Text("No emergency contacts yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(emergencyContacts) { contact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                        Text([contact.relationship, contact.phone].compactMap { $0?.nilIfEmpty }.joined(separator: " • "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    emergencyContacts.remove(atOffsets: idx)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $newEmergencyName)
                    TextField("Relationship", text: $newEmergencyRelationship)
                    TextField("Phone", text: $newEmergencyPhone)
                        .keyboardType(.phonePad)
                    Button("Add emergency contact") {
                        let name = newEmergencyName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let contact = EmergencyContact(
                            name: name,
                            relationship: newEmergencyRelationship.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                            phone: newEmergencyPhone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        )
                        emergencyContacts.append(contact)
                        newEmergencyName = ""
                        newEmergencyRelationship = ""
                        newEmergencyPhone = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(newEmergencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Edit Person")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingScanner) {
            DriverLicenseScannerView { result in
                switch result {
                case .success(let scan):
                    applyScan(scan)
                case .failure(let err):
                    banner = "Scan failed: \(err.localizedDescription)"
                }
                isPresentingScanner = false
            }
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var p = initial
                    p.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                    p.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.dateOfBirthMMDDYYYY = dob.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.driverLicenseNumber = dlNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.mobilePhone = mobile.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.ssnLast4 = ssnLast4.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.addressLine1 = address1.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.addressLine2 = address2.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.city = city.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.state = state.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.postalCode = zip.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    p.familyMembers = familyMembers
                    p.emergencyContacts = emergencyContacts
                    p.updatedAt = Date()
                    onSave(p)
                    dismiss()
                }
                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func applyScan(_ scan: DriverLicenseScanResult) {
        if nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fn = scan.firstName, let ln = scan.lastName {
                nickname = "\(fn) \(ln)"
            } else if let full = scan.fullName, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nickname = full
            }
        }

        if let fn = scan.firstName, !fn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { firstName = fn }
        if let ln = scan.lastName, !ln.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastName = ln }
        if let dobDate = scan.dateOfBirth { dob = formatMMDDYYYY(dobDate) }
        if let dl = scan.documentNumber, !dl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dlNumber = dl }
        if let a1 = scan.addressLine1, !a1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { address1 = a1 }
        if let c = scan.city, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { city = c }
        if let s = scan.state, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state = s }
        if let z = scan.postalCode, !z.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { zip = z }

        banner = "Autofilled from scan."
    }

    private func formatMMDDYYYY(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

