import Foundation

/// Local SDK facade for form autofill. It consumes the identity graph produced by scanning
/// and returns only fields that are safe enough to prefill without bypassing review.
enum SmartAutofillSDK {
    struct Request: Hashable {
        var requestedKeys: Set<String>
        var includeFieldsRequiringReview: Bool

        init(
            requestedKeys: Set<String> = [],
            includeFieldsRequiringReview: Bool = false
        ) {
            self.requestedKeys = requestedKeys
            self.includeFieldsRequiringReview = includeFieldsRequiringReview
        }
    }

    struct Response: Hashable {
        let fields: [String: String]
        let canonicalIdentity: CanonicalIdentityProfile
        let requiresReview: [String]
        let sourceDocumentType: String
    }

    static func buildResponse(
        from payload: SmartAutofillPayload,
        request: Request = Request()
    ) -> Response {
        var fields: [String: String] = [:]
        var requiresReview: [String] = []

        for field in payload.fields {
            if !request.requestedKeys.isEmpty, !request.requestedKeys.contains(field.profileKey) {
                continue
            }
            if field.requiresManualConfirmation {
                requiresReview.append(field.profileKey)
                guard request.includeFieldsRequiringReview else { continue }
            }
            fields[field.profileKey] = field.value
        }

        return Response(
            fields: fields,
            canonicalIdentity: payload.canonicalIdentity,
            requiresReview: requiresReview.sorted(),
            sourceDocumentType: payload.documentType
        )
    }
}
