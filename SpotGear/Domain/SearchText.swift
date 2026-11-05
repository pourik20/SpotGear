import Foundation

/// Case- and diacritics-insensitive matching for collection search.
enum SearchText {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every word of the query must appear in at least one field.
    static func matches(query: String, fields: [String?]) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = fields.compactMap { $0 }.map(fold).joined(separator: " ")
        return words.allSatisfy { haystack.contains($0) }
    }
}
