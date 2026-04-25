import SwiftUI

struct BlankSchoolRegistrationFormView: View {
    @EnvironmentObject private var appState: AppState
    enum FieldKind: Hashable {
        case text
        case dateMMDDYYYY
        case phone
        case email
        case state2
        case zip
    }

    struct Field: Identifiable, Hashable {
        let id: String
        let key: String
        let label: String
        let kind: FieldKind
        var value: String
    }

    @State private var fields: [Field] = BlankSchoolRegistrationFormView.defaultFields
    @State private var banner: String?
    @State private var submitInFlight = false
    @FocusState private var focusedFieldKey: String?
    @State private var isPresentingScanner = false
    @State private var autoOpenScannerOnLaunch = false
    @State private var capturedStore = CapturedValueStore()
    @State private var allowOverwriteFromScan = false
    @State private var lastScan: DriverLicenseScanResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                GroupBox("School Intake") {
                    Text("Fill in your details, then Save or Submit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)

                GroupBox("Scan") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Scan ID") {
                            focusedFieldKey = nil
                            isPresentingScanner = true
                        }
                        .buttonStyle(.borderedProminent)

                        Toggle("Allow scan to overwrite existing fields", isOn: $allowOverwriteFromScan)
                            .font(.footnote)

                        Button("Save scanned details to People") {
                            guard let scan = lastScan else {
                                banner = "Scan first, then tap “Save scanned details to People”."
                                return
                            }
                            var person = appState.peopleStore.selectedPerson ?? PersonProfile(nickname: "Sreeni")
                            if person.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                person.nickname = "Sreeni"
                            }
                            person.firstName = scan.firstName ?? person.firstName
                            person.lastName = scan.lastName ?? person.lastName
                            person.dateOfBirthMMDDYYYY = scan.dateOfBirth.map { formatMMDDYYYY($0) } ?? person.dateOfBirthMMDDYYYY
                            person.driverLicenseNumber = scan.documentNumber ?? person.driverLicenseNumber
                            person.addressLine1 = scan.addressLine1 ?? person.addressLine1
                            person.city = scan.city ?? person.city
                            person.state = scan.state ?? person.state
                            person.postalCode = scan.postalCode ?? person.postalCode
                            person.updatedAt = Date()
                            appState.peopleStore.upsert(person, select: true)
                            banner = "Saved to People: \(person.displayTitle)"
                        }
                        .buttonStyle(.bordered)
                        .disabled(lastScan == nil)

                        Text("Upload from your Mac (Simulator): tap Scan ID, then choose Browse Downloads / Choose Photo / Choose File.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)

                GroupBox("Fields") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach($fields) { $field in
                            fieldEditor(field: $field)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.horizontal)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Scan ID") {
                            focusedFieldKey = nil
                            isPresentingScanner = true
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            persist()
                            banner = "Saved on this device."
                        }
                        .buttonStyle(.borderedProminent)

                        Button(submitInFlight ? "Submitting…" : "Submit") {
                            Task { await submit() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(submitInFlight)

                        Button("Clear") {
                            fields = Self.defaultFields
                            UserDefaults.standard.removeObject(forKey: storageKey)
                            banner = "Cleared."
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("School Intake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scan ID") {
                    focusedFieldKey = nil
                    isPresentingScanner = true
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedFieldKey = nil }
            }
        }
        .onAppear {
            if let saved = readSavedValues() {
                for idx in fields.indices {
                    if let v = saved[fields[idx].key] {
                        fields[idx].value = v
                    }
                }
            }

            // user-controlled scan; no auto-present on launch
        }
        .sheet(isPresented: $isPresentingScanner) {
            DriverLicenseScannerView { result in
                switch result {
                case .success(let scan):
                    let report = applyDeduped(scan)
                    banner = report
                    lastScan = scan
                case .failure(let err):
                    banner = "Scan failed: \(err.localizedDescription)"
                }
                isPresentingScanner = false
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func fieldEditor(field: Binding<Field>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.wrappedValue.label)
                .font(.headline)

            switch field.wrappedValue.kind {
            case .dateMMDDYYYY:
                DatePicker(
                    "",
                    selection: Binding(
                        get: { parseMMDDYYYY(field.wrappedValue.value) ?? Date() },
                        set: { field.wrappedValue.value = formatMMDDYYYY($0) }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .labelsHidden()

                Text("Format: MM/dd/yyyy")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .email:
                TextField("name@example.com", text: field.value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedFieldKey, equals: field.wrappedValue.key)

            case .phone:
                TextField("+1 (555) 555-5555", text: field.value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                    .focused($focusedFieldKey, equals: field.wrappedValue.key)

            case .zip:
                TextField("ZIP Code", text: field.value)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .focused($focusedFieldKey, equals: field.wrappedValue.key)

            case .state2:
                TextField("State (e.g. CA)", text: field.value)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedFieldKey, equals: field.wrappedValue.key)

            case .text:
                TextField(field.wrappedValue.label, text: field.value, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedFieldKey, equals: field.wrappedValue.key)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static var defaultFields: [Field] {
        [
            .init(id: "first_name", key: "first_name", label: "First Name", kind: .text, value: ""),
            .init(id: "last_name", key: "last_name", label: "Last Name", kind: .text, value: ""),
            .init(id: "display_name", key: "display_name", label: "Student Full Name", kind: .text, value: ""),
            .init(id: "date_of_birth", key: "date_of_birth", label: "Date of Birth", kind: .dateMMDDYYYY, value: ""),
            .init(id: "driver_license_number", key: "driver_license_number", label: "Driver License Number", kind: .text, value: ""),
            .init(id: "guardian_name", key: "guardian_name", label: "Parent or Guardian Name", kind: .text, value: ""),
            .init(id: "guardian_phone", key: "guardian_phone", label: "Parent or Guardian Phone", kind: .phone, value: ""),
            .init(id: "guardian_email", key: "guardian_email", label: "Parent or Guardian Email", kind: .email, value: ""),
            .init(id: "address_line_1", key: "address_line_1", label: "Street Address", kind: .text, value: ""),
            .init(id: "city", key: "city", label: "City", kind: .text, value: ""),
            .init(id: "state", key: "state", label: "State", kind: .state2, value: ""),
            .init(id: "postal_code", key: "postal_code", label: "ZIP Code", kind: .zip, value: ""),
            .init(id: "insurance_provider", key: "insurance_provider", label: "Insurance Provider", kind: .text, value: ""),
            .init(id: "policy_number", key: "policy_number", label: "Policy Number", kind: .text, value: ""),
        ]
    }

    private var storageKey: String { "school_registration.blank.values.v1" }

    private func persist() {
        let dict = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func readSavedValues() -> [String: String]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private func formatMMDDYYYY(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df.string(from: date)
    }

    private func parseMMDDYYYY(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df.date(from: trimmed)
    }

    private func applyDeduped(_ scan: DriverLicenseScanResult) -> String {
        var applied: [String] = []
        var skipped: [String] = []

        func maybeSet(_ key: String, _ value: String, label: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if !allowOverwriteFromScan {
                // If the user already typed something, don't overwrite it.
                if let current = fields.first(where: { $0.key == key })?.value.trimmingCharacters(in: .whitespacesAndNewlines),
                   !current.isEmpty {
                    skipped.append("\(label) (already filled)")
                    return
                }

                // If we've already captured the same value before, skip.
                if capturedStore.hasSameCapturedValue(key: key, candidate: trimmed) {
                    skipped.append("\(label) (already captured)")
                    return
                }
            }

            set(key, trimmed)
            _ = capturedStore.captureIfNew(key: key, value: trimmed)
            applied.append(label)
        }

        if let first = scan.firstName { maybeSet("first_name", first, label: "First name") }
        if let last = scan.lastName { maybeSet("last_name", last, label: "Last name") }
        if let full = scan.fullName { maybeSet("display_name", full, label: "Full name") }
        if let dob = scan.dateOfBirth { maybeSet("date_of_birth", formatMMDDYYYY(dob), label: "DOB") }
        if let dl = scan.documentNumber { maybeSet("driver_license_number", dl, label: "Driver license #") }
        if let a1 = scan.addressLine1 { maybeSet("address_line_1", a1, label: "Street address") }
        if let city = scan.city { maybeSet("city", city, label: "City") }
        if let state = scan.state { maybeSet("state", state, label: "State") }
        if let zip = scan.postalCode { maybeSet("postal_code", zip, label: "ZIP") }

        if applied.isEmpty, skipped.isEmpty {
            let excerpt = scan.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if excerpt.isEmpty {
                return "Scan finished, but no text/barcode was detected. Try a clearer photo (include the PDF417 barcode), or use a PDF if you have one."
            }
            let preview = String(excerpt.prefix(500))
            return "Scan finished. No usable fields found. Raw scan preview:\n\(preview)"
        }

        if applied.isEmpty {
            return "Scan finished. Skipped: \(skipped.joined(separator: ", "))"
        }

        if skipped.isEmpty {
            return "Scanned and filled: \(applied.joined(separator: ", "))"
        }

        return "Filled: \(applied.joined(separator: ", ")). Skipped: \(skipped.joined(separator: ", "))"
    }

    private func set(_ key: String, _ value: String) {
        guard let idx = fields.firstIndex(where: { $0.key == key }) else { return }
        fields[idx].value = value
    }

    private func submit() async {
        submitInFlight = true
        defer { submitInFlight = false }

        persist()

        // Current Core API supports only {id, display_name}.
        let displayName = fields.first(where: { $0.key == "display_name" })?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !displayName.isEmpty else {
            banner = "Student Full Name is required to submit."
            return
        }

        let payload: [String: String] = [
            "id": "school-form-\(UUID().uuidString.lowercased())",
            "display_name": displayName,
        ]

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:18081/manual-entry")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            if (200..<300).contains(status) {
                banner = "Submitted. (Core API saved display name.)"
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                banner = "Submit failed (\(status)). \(body)"
            }
        } catch {
            banner = "Submit failed: \(error.localizedDescription)"
        }
    }
}

