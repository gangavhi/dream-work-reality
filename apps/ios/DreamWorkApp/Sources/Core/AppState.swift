import Foundation
import SwiftUI

enum AppTab: Hashable {
    case home
    case people
    case forms
    case settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published private(set) var statusText: String = "Core service not loaded"
    @Published private(set) var manualEntryCount: Int = 0
    @Published private(set) var selectedPersonName: String = "No person loaded"
    @Published private(set) var people: [PersonRecord] = []
    @Published private(set) var extractionRunCount: Int = 0
    @Published private(set) var isImportingDocument = false
    @Published var documentImportMessage: String?
    @Published var scanReviewPayload: ScanReviewPayload?
    @Published var showDocumentScanner = false
    @Published var showFileImporter = false

    private let coreService: CoreBridgeService

    init(coreService: CoreBridgeService) {
        self.coreService = coreService
    }

    func refreshPeopleList() {
        people = coreService.listPeople()
    }

    func refreshStatus() {
        statusText = coreService.fetchStatus()
        manualEntryCount = coreService.manualEntryCount()
        extractionRunCount = coreService.extractionRunCount()
        refreshPeopleList()
    }

    func savePerson(_ person: PersonRecord) -> Bool {
        guard coreService.savePerson(person) else { return false }
        refreshStatus()
        return true
    }

    func deletePerson(id: String) -> Bool {
        let personName = people.first(where: { $0.id == id })?.displayTitle
        guard coreService.deletePerson(id: id) else { return false }
        DocumentFingerprintStore.removeEntries(forPersonID: id, personName: personName)
        refreshStatus()
        return true
    }

    /// Imports a document downloaded from a Mac-hosted HTTP folder (Simulator testing).
    func importDocument(fromRemoteURL url: URL) async {
        do {
            let localURL = try await LaptopDocumentListing.downloadToTemporaryFile(from: url)
            await importDocument(from: localURL, urlIsTemporaryCopy: true)
        } catch {
            documentImportMessage = error.localizedDescription
        }
    }

    /// Imports a document from a URL. Document type is inferred from OCR after extraction.
    func importDocument(
        from url: URL,
        urlIsTemporaryCopy: Bool = false
    ) async {
        documentImportMessage = nil
        isImportingDocument = true

        let localURL: URL
        let shouldDeleteLocalCopy: Bool
        do {
            if urlIsTemporaryCopy {
                localURL = url
                shouldDeleteLocalCopy = true
            } else {
                // Picker URLs must be copied while security-scoped access is still valid.
                localURL = try DocumentImportHelper.makeLocalCopy(of: url)
                shouldDeleteLocalCopy = true
            }
        } catch {
            isImportingDocument = false
            documentImportMessage = error.localizedDescription
            return
        }

        defer {
            isImportingDocument = false
            if shouldDeleteLocalCopy {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        let bridge = coreService

        do {
            let result = try await DocumentTextExtractor.extractAndPersist(from: localURL) { json in
                bridge.ingestNormalizedDocumentJSON(json)
            }
            refreshStatus()

            var fullText = OcrFieldSuggester.fullText(from: result.document)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var classification = DocumentTypeClassifier.classify(from: fullText)
            var driverLicenseScan: DriverLicenseScanResult?

            if classification.documentType == .driversLicense || classification.documentType == .stateId {
                driverLicenseScan = try? await DriverLicenseScannerPipeline.scan(fileURL: localURL)
            }

            if fullText.isEmpty {
                if driverLicenseScan == nil {
                    driverLicenseScan = try? await DriverLicenseScannerPipeline.scan(fileURL: localURL)
                }
                if let dlText = driverLicenseScan?.rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                   !dlText.isEmpty
                {
                    fullText = dlText
                    classification = DocumentTypeClassifier.classify(from: fullText)
                }
            }

            if fullText.isEmpty, driverLicenseScan == nil {
                documentImportMessage =
                    "No text was detected in this file. Try a clearer photo or PDF, or enter details manually under People."
                return
            }

            await presentScanReview(
                document: result.document,
                classification: classification,
                pageCount: result.pageCount,
                blockCount: result.blockCount,
                driverLicenseScan: driverLicenseScan
            )
        } catch {
            documentImportMessage = error.localizedDescription
        }
    }

    func presentScanReview(
        document: VisionOcrAdapter.NormalizedDocument,
        classification: DocumentClassification,
        pageCount: Int,
        blockCount: Int,
        driverLicenseScan: DriverLicenseScanResult? = nil
    ) async {
        let detectedType = classification.documentType
        let fullText: String = {
            let fromDoc = OcrFieldSuggester.fullText(from: document)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !fromDoc.isEmpty { return fromDoc }
            return driverLicenseScan?.rawText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()
        let heuristic = OcrFieldSuggester.suggest(from: fullText, documentType: detectedType)
        let enrichment = await coreService.enrichScanReview(
            ocrText: fullText,
            detectedDocumentType: detectedType,
            fallbackSuggestions: heuristic,
            driverLicenseScan: driverLicenseScan
        )
        let effectiveType = enrichment.understanding.flatMap { understandingType(from: $0.documentType) }
            ?? detectedType
        let refinedClassification = DocumentTypeClassifier.refine(
            DocumentClassification(
                documentType: effectiveType,
                confidence: classification.confidence,
                matchedSignals: classification.matchedSignals
            ),
            driverLicenseScan: driverLicenseScan,
            fullText: fullText
        )
        let prefilled = driverLicenseScan.map { DriverLicenseFieldMapper.personRecord(from: $0) }
        scanReviewPayload = ScanReviewPayload(
            detectedDocumentType: effectiveType,
            classificationConfidence: refinedClassification.confidence,
            classificationSignals: refinedClassification.matchedSignals,
            fullText: fullText,
            ocrBlockCount: blockCount,
            pageCount: pageCount,
            suggestions: enrichment.suggestions,
            understanding: enrichment.understanding,
            personResolution: enrichment.personResolution,
            storagePlan: enrichment.storagePlan,
            usedAI: enrichment.usedAI,
            prefilledPerson: prefilled
        )
    }

    private func understandingType(from raw: String) -> ScannedDocumentType? {
        switch raw.lowercased() {
        case "drivers_license", "driver_license", "drivers license": return .driversLicense
        case "passport": return .passport
        case "state_id", "state id": return .stateId
        case "insurance_card", "insurance card": return .insuranceCard
        case "utility_bill", "utility bill": return .utilityBill
        case "bank_statement", "bank statement": return .bankStatement
        case "tax_form", "tax_document", "tax document": return .taxDocument
        case "employment_document", "employment document", "pay_stub", "pay stub": return .employmentDocument
        case "ssn_card", "ssn card", "social_security_card", "social security card": return .ssnCard
        default: return nil
        }
    }

    func saveAndLoadDemoPerson() {
        let id = "person-1"
        let saved = coreService.saveManualEntry(id: id, displayName: "Alex Carter")
        if saved, let name = coreService.readManualEntryName(id: id) {
            selectedPersonName = name
        } else {
            selectedPersonName = "Failed to load person"
        }
        refreshStatus()
    }

    func openPeople() {
        selectedTab = .people
    }

    func seedSamplePeople() {
        _ = savePerson(
            PersonRecord.empty(id: "person-1")
                .withValue("Alex Carter", for: ProfileFieldKey.displayName)
                .withValue(HouseholdRelationship.selfMember.rawValue, for: ProfileFieldKey.relationship)
        )
        _ = savePerson(
            PersonRecord.empty(id: "person-2")
                .withValue("Sam Rivera", for: ProfileFieldKey.displayName)
                .withValue(HouseholdRelationship.child.rawValue, for: ProfileFieldKey.relationship)
        )
        refreshStatus()
    }
}
