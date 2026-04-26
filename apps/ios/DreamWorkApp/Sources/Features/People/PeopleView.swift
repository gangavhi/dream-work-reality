import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPresentingNew = false
    @State private var isConfirmingDeleteAll = false
    @State private var isPresentingScanNew = false
    @State private var scanBanner: String?

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
                        Button("Scan New") { isPresentingScanNew = true }
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
            .alert("Scan result", isPresented: Binding(get: { scanBanner != nil }, set: { if !$0 { scanBanner = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanBanner ?? "")
            }
            .sheet(isPresented: $isPresentingScanNew) {
                DriverLicenseScannerView { result in
                    switch result {
                    case .success(let scan):
                        let created = buildProfile(from: scan)
                        appState.peopleStore.upsert(created, select: true)
                        scanBanner = "Created profile: \(created.displayTitle)"
                    case .failure(let err):
                        scanBanner = "Scan failed: \(err.localizedDescription)"
                    }
                    isPresentingScanNew = false
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
