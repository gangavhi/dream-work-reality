import CoreML
import Foundation
import NaturalLanguage

/// Optional Create ML models shipped in the app bundle (train in Xcode → Create ML).
enum CreateMLModelRegistry {
    static let documentTypeClassifierName = "DocumentTypeClassifier"
    static let fieldTaggerName = "FieldSequenceTagger"

    static var hasBundledClassifier: Bool { documentClassifierPath() != nil }
    static var hasBundledFieldTagger: Bool { fieldTaggerPath() != nil }

    static func documentClassifierPath() -> String? {
        modelResourcePath(named: documentTypeClassifierName)
    }

    static func fieldTaggerPath() -> String? {
        modelResourcePath(named: fieldTaggerName)
    }

    static var documentTypeClassifier: NLModel? {
        guard let path = documentClassifierPath() else { return nil }
        return try? NLModel(contentsOf: URL(fileURLWithPath: path))
    }

    private static func modelResourcePath(named name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: name, withExtension: "mlmodel")
        {
            return url.path
        }
        return nil
    }

    private static func loadNLModel(named name: String) -> NLModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: name, withExtension: "mlmodel")
        else { return nil }
        return try? NLModel(contentsOf: url)
    }
}
