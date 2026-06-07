import Foundation

/// Resolves US state codes from OCR text — reference data only, never a default for a specific state.
enum USJurisdictionSupport {
    private static let nameToCode: [String: String] = [
        "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR",
        "CALIFORNIA": "CA", "COLORADO": "CO", "CONNECTICUT": "CT", "DELAWARE": "DE",
        "DISTRICT OF COLUMBIA": "DC", "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI",
        "IDAHO": "ID", "ILLINOIS": "IL", "INDIANA": "IN", "IOWA": "IA",
        "KANSAS": "KS", "KENTUCKY": "KY", "LOUISIANA": "LA", "MAINE": "ME",
        "MARYLAND": "MD", "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN",
        "MISSISSIPPI": "MS", "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE",
        "NEVADA": "NV", "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ", "NEW MEXICO": "NM",
        "NEW YORK": "NY", "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH",
        "OKLAHOMA": "OK", "OREGON": "OR", "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI",
        "SOUTH CAROLINA": "SC", "SOUTH DAKOTA": "SD", "TENNESSEE": "TN", "TEXAS": "TX",
        "UTAH": "UT", "VERMONT": "VT", "VIRGINIA": "VA", "WASHINGTON": "WA",
        "WEST VIRGINIA": "WV", "WISCONSIN": "WI", "WYOMING": "WY",
    ]

    private static let ocrNameAliases: [String: String] = [
        "TEXASS": "TEXAS",
        "CALIF": "CALIFORNIA",
        "PENN": "PENNSYLVANIA",
    ]

    /// Infer issuing / residence state from city-state-ZIP lines, header state names, or isolated codes.
    static func inferStateCode(from lines: [String], joined: String? = nil) -> String? {
        for line in lines {
            if let csz = DriverLicenseParserSupport.parseCityStateZip(line) {
                return csz.state
            }
        }

        if let fromPlace = inferStateCode(fromPlaceText: joined ?? lines.joined(separator: "\n")) {
            return fromPlace
        }

        for line in lines {
            let tokens = line
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            for token in tokens {
                let code = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if code.count == 2, ScanFieldValidator.isPlausibleUSState(code) {
                    return code
                }
            }
        }
        return nil
    }

    /// Extract a US state code embedded in free text (e.g. place of birth `TEXAS, U.S.A.`).
    static func inferStateCode(fromPlaceText text: String) -> String? {
        let upper = text.uppercased()
        guard !upper.isEmpty else { return nil }

        var normalized = upper
        for (alias, canonical) in ocrNameAliases {
            normalized = normalized.replacingOccurrences(of: alias, with: canonical)
        }

        let names = nameToCode.keys.sorted { $0.count > $1.count }
        for name in names {
            if normalized.contains(name), let code = nameToCode[name] {
                return code
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\b([A-Z]{2})\b"#) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            var matches: [String] = []
            regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: normalized)
                else { return }
                let code = String(normalized[r])
                if ScanFieldValidator.isPlausibleUSState(code) {
                    matches.append(code)
                }
            }
            if matches.count == 1 {
                return matches[0]
            }
        }
        return nil
    }
}
