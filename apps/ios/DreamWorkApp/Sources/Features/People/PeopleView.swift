import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPresentingNew = false
    @State private var isConfirmingDeleteAll = false
    @State private var isPresentingScanPicker = false
    @State private var scanTargetPerson: PersonProfile?
    @State private var scanBanner: String?
    @State private var isConfirmingDeletePerson = false
    @State private var pendingDeletePersonID: UUID?
    @State private var pendingDeletePersonName: String = ""

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    if appState.peopleStore.people.isEmpty {
                        ContentUnavailableView("No people yet", systemImage: "person.crop.circle.badge.plus", description: Text("Create a profile like “wife”, “daughter”, or “son”."))
                    } else {
                        Section("People") {
                            ForEach(appState.peopleStore.people) { person in
                                NavigationLink {
                                    EditPersonProfileView(initial: person) { updated in
                                        appState.peopleStore.upsert(updated, select: true)
                                    } onDelete: { id in
                                        appState.peopleStore.delete(id)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.displayTitle)
                                        if let fn = person.firstName, let ln = person.lastName {
                                            Text("\(fn) \(ln)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        insuranceSummaryLine(for: person)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        pendingDeletePersonID = person.id
                                        pendingDeletePersonName = person.displayTitle
                                        isConfirmingDeletePerson = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDeletePersonID = person.id
                                        pendingDeletePersonName = person.displayTitle
                                        isConfirmingDeletePerson = true
                                    } label: {
                                        Label("Delete Profile", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete { idx in
                                for i in idx {
                                    let id = appState.peopleStore.people[i].id
                                    appState.peopleStore.delete(id)
                                }
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 0)
                        .id("bottom")
                }
                .navigationTitle("People")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("Top") { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                        Button("Bottom") { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") { isPresentingNew = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Scan") { isPresentingScanPicker = true }
                            .disabled(appState.peopleStore.people.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Delete All") { isConfirmingDeleteAll = true }
                            .disabled(appState.peopleStore.people.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $isPresentingNew) {
                NavigationStack {
                    EditPersonProfileView(initial: PersonProfile(nickname: "")) { created in
                        appState.peopleStore.upsert(created, select: true)
                    }
                }
            }
            .alert("Delete all profiles?", isPresented: $isConfirmingDeleteAll) {
                Button("Delete All", role: .destructive) {
                    appState.peopleStore.deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all saved people profiles on this device.")
            }
            .alert("Delete profile?", isPresented: $isConfirmingDeletePerson) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeletePersonID {
                        appState.peopleStore.delete(id)
                    }
                    pendingDeletePersonID = nil
                    pendingDeletePersonName = ""
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletePersonID = nil
                    pendingDeletePersonName = ""
                }
            } message: {
                Text("Delete “\(pendingDeletePersonName)” from this device?")
            }
            .alert("Scan result", isPresented: Binding(get: { scanBanner != nil }, set: { if !$0 { scanBanner = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanBanner ?? "")
            }
            .sheet(isPresented: $isPresentingScanPicker) {
                NavigationStack {
                    List {
                        Section("Choose profile") {
                            ForEach(appState.peopleStore.people) { person in
                                Button {
                                    scanTargetPerson = person
                                    isPresentingScanPicker = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.displayTitle)
                                        insuranceSummaryLine(for: person)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Scan for…")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPresentingScanPicker = false }
                        }
                    }
                }
            }
            .sheet(item: $scanTargetPerson) { person in
                DriverLicenseScannerView { result in
                    switch result {
                    case .success(let scan):
                        let updated = applyScan(scan, to: person)
                        appState.peopleStore.upsert(updated, select: true)
                        scanBanner = "Updated profile: \(updated.displayTitle)"
                    case .failure(let err):
                        scanBanner = "Scan failed: \(err.localizedDescription)"
                    }
                    scanTargetPerson = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func insuranceSummaryLine(for person: PersonProfile) -> some View {
        let provider = (person.insuranceProvider ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let policy = (person.policyNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !provider.isEmpty || !policy.isEmpty {
            let text = (!provider.isEmpty && !policy.isEmpty) ? "\(provider) • \(policy)" : (!provider.isEmpty ? provider : policy)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func buildProfile(from scan: DriverLicenseScanResult) -> PersonProfile {
        let fn = scan.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ln = scan.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full = scan.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Per request: use the scanned first name as the profile name (nickname) when available.
        let name = !fn.isEmpty ? fn : ((!fn.isEmpty || !ln.isEmpty) ? [fn, ln].filter { !$0.isEmpty }.joined(separator: " ") : (full ?? "New Profile"))

        var p = PersonProfile(nickname: name)
        p.firstName = fn.nilIfEmpty
        p.lastName = ln.nilIfEmpty
        if let dob = scan.dateOfBirth {
            p.dateOfBirthMMDDYYYY = formatMMDDYYYY(dob)
        }
        p.height = scan.height?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.eyeColor = scan.eyeColor?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Address
        p.addressLine1 = scan.addressLine1?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.city = scan.city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.state = scan.state?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.postalCode = scan.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Active DL + DL history (always override from scan).
        let dl = DriverLicense(
            number: scan.documentNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            state: scan.state?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            issueMMDDYYYY: scan.issueDate.map(formatMMDDYYYY),
            expiryMMDDYYYY: scan.expiryDate.map(formatMMDDYYYY),
            isActive: true,
            capturedAt: Date()
        )
        p.driverLicenses = [dl]
        p.driverLicenseNumber = dl.number
        p.driverLicenseIssueMMDDYYYY = dl.issueMMDDYYYY
        p.driverLicenseExpiryMMDDYYYY = dl.expiryMMDDYYYY
        p.driverLicenseState = dl.state
        p.documents = [
            ScannedDocument(
                type: "driver_license",
                number: dl.number,
                issueMMDDYYYY: dl.issueMMDDYYYY,
                expiryMMDDYYYY: dl.expiryMMDDYYYY,
                rawText: scan.rawText,
                capturedAt: dl.capturedAt
            )
        ]

        p.updatedAt = Date()
        if let all = scan.genAIValues {
            p.genAIFields = all
        }
        return p
    }

    private func applyScan(_ scan: DriverLicenseScanResult, to existing: PersonProfile) -> PersonProfile {
        var p = existing

        func trim(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        p.firstName = trim(scan.firstName) ?? p.firstName
        p.lastName = trim(scan.lastName) ?? p.lastName
        if let dob = scan.dateOfBirth {
            p.dateOfBirthMMDDYYYY = formatMMDDYYYY(dob)
        }
        p.height = trim(scan.height) ?? p.height
        p.eyeColor = trim(scan.eyeColor) ?? p.eyeColor

        p.addressLine1 = trim(scan.addressLine1) ?? p.addressLine1
        p.city = trim(scan.city) ?? p.city
        p.state = trim(scan.state) ?? p.state
        p.postalCode = trim(scan.postalCode) ?? p.postalCode

        let dl = DriverLicense(
            number: trim(scan.documentNumber),
            state: trim(scan.state),
            issueMMDDYYYY: scan.issueDate.map(formatMMDDYYYY),
            expiryMMDDYYYY: scan.expiryDate.map(formatMMDDYYYY),
            isActive: true,
            capturedAt: Date()
        )
        p.driverLicenses = p.driverLicenses.map { var x = $0; x.isActive = false; return x }
        p.driverLicenses.insert(dl, at: 0)
        p.driverLicenseNumber = dl.number
        p.driverLicenseIssueMMDDYYYY = dl.issueMMDDYYYY
        p.driverLicenseExpiryMMDDYYYY = dl.expiryMMDDYYYY
        p.driverLicenseState = dl.state

        let doc = ScannedDocument(
            type: "driver_license",
            number: dl.number,
            issueMMDDYYYY: dl.issueMMDDYYYY,
            expiryMMDDYYYY: dl.expiryMMDDYYYY,
            rawText: scan.rawText,
            capturedAt: dl.capturedAt
        )
        p.documents = [doc] + p.documents.filter { $0.type != "driver_license" }

        if let all = scan.genAIValues {
            p.genAIFields = all
        }

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

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
