import SwiftUI

struct EditPersonProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let initial: PersonProfile
    let onSave: (PersonProfile) -> Void
    let onDelete: ((UUID) -> Void)?

    @State private var isPresentingScanner = false
    @State private var banner: String?
    @State private var isShowingRawScan = false
    @State private var lastRawScanText: String = ""
    @State private var isConfirmingDelete = false

    @State private var nickname: String
    @State private var firstName: String
    @State private var lastName: String
    @State private var dob: String
    @State private var dlNumber: String
    @State private var dlIssue: String
    @State private var dlExpiry: String
    @State private var dlState: String
    @State private var height: String
    @State private var eyeColor: String
    @State private var email: String
    @State private var mobile: String
    @State private var ssnLast4: String
    @State private var insuranceProvider: String
    @State private var policyNumber: String
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
    @State private var autosaveTask: Task<Void, Never>?

    // Prevent unintended save when user explicitly cancels or deletes.
    @State private var didCancel = false
    @State private var didDelete = false

    init(initial: PersonProfile, onSave: @escaping (PersonProfile) -> Void, onDelete: ((UUID) -> Void)? = nil) {
        self.initial = initial
        self.onSave = onSave
        self.onDelete = onDelete
        _nickname = State(initialValue: initial.nickname)
        _firstName = State(initialValue: initial.firstName ?? "")
        _lastName = State(initialValue: initial.lastName ?? "")
        _dob = State(initialValue: initial.dateOfBirthMMDDYYYY ?? "")
        _dlNumber = State(initialValue: initial.driverLicenseNumber ?? "")
        _dlIssue = State(initialValue: initial.driverLicenseIssueMMDDYYYY ?? "")
        _dlExpiry = State(initialValue: initial.driverLicenseExpiryMMDDYYYY ?? "")
        _dlState = State(initialValue: initial.driverLicenseState ?? "")
        _height = State(initialValue: initial.height ?? "")
        _eyeColor = State(initialValue: initial.eyeColor ?? "")
        _email = State(initialValue: initial.email ?? "")
        _mobile = State(initialValue: initial.mobilePhone ?? "")
        _ssnLast4 = State(initialValue: initial.ssnLast4 ?? "")
        _insuranceProvider = State(initialValue: initial.insuranceProvider ?? "")
        _policyNumber = State(initialValue: initial.policyNumber ?? "")
        _address1 = State(initialValue: initial.addressLine1 ?? "")
        _address2 = State(initialValue: initial.addressLine2 ?? "")
        _city = State(initialValue: initial.city ?? "")
        _state = State(initialValue: initial.state ?? "")
        _zip = State(initialValue: initial.postalCode ?? "")
        _familyMembers = State(initialValue: initial.familyMembers)
        _emergencyContacts = State(initialValue: initial.emergencyContacts)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Color.clear
                    .frame(height: 0)
                    .id("top")

                if let banner {
                    Section {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !lastRawScanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Show raw OCR text (before GenAI)") {
                                isShowingRawScan = true
                            }
                            .buttonStyle(.bordered)
                        }
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
                    FormField(title: "Nickname (e.g. wife / daughter / son)", text: $nickname)
                    FormField(title: "First Name", text: $firstName)
                    FormField(title: "Last Name", text: $lastName)
                    FormField(title: "Email") {
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    FormField(title: "Mobile") {
                        TextField("", text: $mobile)
                            .keyboardType(.phonePad)
                    }
                }

                Section("ID") {
                    FormField(title: "DOB (MM/dd/yyyy)", text: $dob)
                    FormField(title: "Driver License Number", text: $dlNumber)
                    FormField(title: "DL Issue (MM/dd/yyyy)", text: $dlIssue)
                    FormField(title: "DL Expiry (MM/dd/yyyy)", text: $dlExpiry)
                    FormField(title: "DL State (e.g. CA)") {
                        TextField("", text: $dlState)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    FormField(title: "Height (e.g. 5'02\")", text: $height)
                    FormField(title: "Eyes (e.g. Black)", text: $eyeColor)
                    FormField(title: "SSN (last 4)") {
                        SecureField("", text: $ssnLast4)
                            .keyboardType(.numberPad)
                    }
                }

                Section("Insurance") {
                    FormField(title: "Insurance Provider", text: $insuranceProvider)
                    FormField(title: "Policy Number", text: $policyNumber)
                }

                Section("Address") {
                    FormField(title: "Street Address", text: $address1)
                    FormField(title: "Apt / Unit (optional)", text: $address2)
                    FormField(title: "City", text: $city)
                    FormField(title: "State", text: $state)
                    FormField(title: "ZIP", text: $zip)
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

                Color.clear
                    .frame(height: 0)
                    .id("bottom")
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Top") { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                    Button("Bottom") { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
            }
        }
        .navigationTitle("Edit Person")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: autosaveSignature) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            // If the user leaves via back swipe / dismiss gesture, persist latest edits too.
            // (Autosave debounce can miss fast exits.)
            if didCancel || didDelete { return }
            onSave(buildProfileFromCurrentValues())
        }
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
                Button("Cancel") {
                    didCancel = true
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(buildProfileFromCurrentValues())
                    dismiss()
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if onDelete != nil {
                    Button("Delete Profile", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .alert("Delete this profile?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                didDelete = true
                onDelete?(initial.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this profile from this device.")
        }
        .sheet(isPresented: $isShowingRawScan) {
            NavigationStack {
                ScrollView {
                    Text(lastRawScanText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Raw OCR text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isShowingRawScan = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Copy") {
                            UIPasteboard.general.string = lastRawScanText
                        }
                        .disabled(lastRawScanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func applyScan(_ scan: DriverLicenseScanResult) {
        // This is the raw OCR/barcode text captured before any additional mapping in this view.
        // (The scanner pipeline may include barcode + OCR; this is still the "raw" input for GenAI.)
        lastRawScanText = scan.rawText

        let nickTrimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if nickTrimmed.isEmpty || nickTrimmed.lowercased() == "driver license" {
            if let fn = scan.firstName, let ln = scan.lastName {
                nickname = "\(fn) \(ln)"
            } else if let full = scan.fullName, !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nickname = full
            }
        }

        func isObviouslyWrongName(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.isEmpty { return true }
            // Common OCR junk that should never be a name.
            if ["driver", "license", "officer", "director", "limited", "mited", "dl", "id"].contains(t) { return true }
            if t.contains("driver license") { return true }
            // If it has digits, it's not a name.
            if t.rangeOfCharacter(from: .decimalDigits) != nil { return true }
            return false
        }

        // Fill profile fields when empty OR when they look obviously wrong (e.g. "MITED").
        if (firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isObviouslyWrongName(firstName)),
           let fn = scan.firstName, !fn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { firstName = fn }
        if (lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isObviouslyWrongName(lastName)),
           let ln = scan.lastName, !ln.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastName = ln }
        if dob.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let dobDate = scan.dateOfBirth { dob = formatMMDDYYYY(dobDate) }
        if address1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let a1 = scan.addressLine1, !a1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { address1 = a1 }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let c = scan.city, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { city = c }
        if state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let s = scan.state, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state = s }
        if zip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let z = scan.postalCode, !z.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { zip = z }

        // DL update policy: always override active DL fields (number/issue/expiry/state).
        if let dl = scan.documentNumber, !dl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dlNumber = dl }
        if let iss = scan.issueDate { dlIssue = formatMMDDYYYY(iss) }
        if let exp = scan.expiryDate { dlExpiry = formatMMDDYYYY(exp) }
        if let st = scan.state, !st.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dlState = st }
        if height.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let h = scan.height, !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { height = h }
        if eyeColor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let e = scan.eyeColor, !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { eyeColor = e }

        // Persist immediately so scan results land in People without requiring a Save tap.
        var p = initial
        p.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        p.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.dateOfBirthMMDDYYYY = dob.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.height = height.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.eyeColor = eyeColor.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        // DL update policy: only override active DL fields (number/issue/expiry/state).
        let scannedDL = DriverLicense(
            number: dlNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            state: dlState.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            issueMMDDYYYY: dlIssue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            expiryMMDDYYYY: dlExpiry.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isActive: true,
            capturedAt: Date()
        )
        p.driverLicenses = p.driverLicenses.map { var x = $0; x.isActive = false; return x }
        p.driverLicenses.insert(scannedDL, at: 0)
        p.driverLicenseNumber = scannedDL.number
        p.driverLicenseIssueMMDDYYYY = scannedDL.issueMMDDYYYY
        p.driverLicenseExpiryMMDDYYYY = scannedDL.expiryMMDDYYYY
        p.driverLicenseState = scannedDL.state

        let doc = ScannedDocument(
            type: "driver_license",
            number: scannedDL.number,
            issueMMDDYYYY: scannedDL.issueMMDDYYYY,
            expiryMMDDYYYY: scannedDL.expiryMMDDYYYY,
            rawText: scan.rawText,
            capturedAt: scannedDL.capturedAt
        )
        p.documents = [doc] + p.documents.filter { $0.type != "driver_license" }
        p.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.mobilePhone = mobile.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.ssnLast4 = ssnLast4.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.insuranceProvider = insuranceProvider.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.policyNumber = policyNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.addressLine1 = address1.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.addressLine2 = address2.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.city = city.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.state = state.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.postalCode = zip.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.familyMembers = familyMembers
        p.emergencyContacts = emergencyContacts
        if let all = scan.genAIValues {
            p.genAIFields = all
        }
        p.updatedAt = Date()
        onSave(p)

        banner = """
        Captured from scan:
        - Name: \(scan.fullName ?? [scan.firstName, scan.lastName].compactMap { $0?.nilIfEmpty }.joined(separator: " "))
        - First: \(scan.firstName ?? "—")
        - Last: \(scan.lastName ?? "—")
        - DOB: \(scan.dateOfBirth.map(formatMMDDYYYY) ?? "—")
        - DL #: \(scan.documentNumber ?? "—")
        - Issue: \(scan.issueDate.map(formatMMDDYYYY) ?? "—")
        - Expiry: \(scan.expiryDate.map(formatMMDDYYYY) ?? "—")
        - Address: \(scan.addressLine1 ?? "—")
        - City: \(scan.city ?? "—")
        - State: \(scan.state ?? "—")
        - ZIP: \(scan.postalCode ?? "—")
        - Height: \(scan.height ?? "—")
        - Eyes: \(scan.eyeColor ?? "—")
        """
    }

    private var autosaveSignature: String {
        [
            nickname,
            firstName,
            lastName,
            dob,
            dlNumber,
            dlIssue,
            dlExpiry,
            dlState,
            height,
            eyeColor,
            email,
            mobile,
            ssnLast4,
            insuranceProvider,
            policyNumber,
            address1,
            address2,
            city,
            state,
            zip,
            String(familyMembers.count),
            String(emergencyContacts.count),
        ].joined(separator: "|")
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            onSave(buildProfileFromCurrentValues())
        }
    }

    private func buildProfileFromCurrentValues() -> PersonProfile {
        var p = initial
        let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty {
            p.nickname = nick
        } else {
            // SQLite requires nickname NOT NULL; keep existing nickname or derive a safe fallback.
            let existing = initial.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if !existing.isEmpty {
                p.nickname = existing
            } else {
                let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                let ln = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                let derived = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
                p.nickname = derived.isEmpty ? "Unnamed Person" : derived
            }
        }
        p.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.dateOfBirthMMDDYYYY = dob.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.driverLicenseNumber = dlNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.driverLicenseIssueMMDDYYYY = dlIssue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.driverLicenseExpiryMMDDYYYY = dlExpiry.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.driverLicenseState = dlState.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.height = height.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.eyeColor = eyeColor.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.mobilePhone = mobile.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.ssnLast4 = ssnLast4.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.insuranceProvider = insuranceProvider.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.policyNumber = policyNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.addressLine1 = address1.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.addressLine2 = address2.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.city = city.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.state = state.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.postalCode = zip.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.familyMembers = familyMembers
        p.emergencyContacts = emergencyContacts
        p.updatedAt = Date()
        return p
    }

    private func formatMMDDYYYY(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df.string(from: date)
    }
}

private struct FormField<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .padding(.vertical, 2)
    }
}

private extension FormField where Content == TextField<Text> {
    init(title: String, text: Binding<String>) {
        self.init(title: title) {
            TextField("", text: text)
        }
    }
}

private extension FormField where Content == SecureField<Text> {
    init(title: String, secureText: Binding<String>) {
        self.init(title: title) {
            SecureField("", text: secureText)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

