import Foundation

enum SubtitleMatcher {
    private static let stopwords: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are", "as",
        "at", "be", "because", "been", "before", "being", "below", "between", "both", "but", "by",
        "can", "could", "did", "do", "does", "doing", "down", "during", "each", "few", "for", "from",
        "further", "had", "has", "have", "having", "he", "her", "here", "hers", "herself", "him", "himself",
        "his", "how", "i", "if", "in", "into", "is", "it", "its", "itself", "just", "me", "more", "most",
        "my", "myself", "no", "nor", "not", "now", "of", "off", "on", "once", "only", "or", "other",
        "our", "ours", "ourselves", "out", "over", "own", "s", "same", "she", "should", "so", "some",
        "such", "t", "than", "that", "the", "their", "theirs", "them", "themselves", "then", "there",
        "these", "they", "this", "those", "through", "to", "too", "under", "until", "up", "very", "was",
        "we", "were", "what", "when", "where", "which", "while", "who", "whom", "why", "will", "with",
        "you", "your", "yours", "yourself", "yourselves"
    ]
    static func fullText(from data: Data) -> String? {
        let decoded = decodeData(data)
        guard let text = decoded else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !isTimingLine($0) && !isIndexLine($0) && !$0.isEmpty }
        return normalize(lines.joined(separator: " "))
    }

    static func similarity(_ left: String, _ right: String) -> Double {
        let leftTokens = tokenFrequencies(left)
        let rightTokens = tokenFrequencies(right)
        guard leftTokens.count >= 300, rightTokens.count >= 300 else { return 0 }
        return cosineSimilarity(leftTokens, rightTokens)
    }

    private static func decodeData(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return nil
    }

    private static func isTimingLine(_ line: String) -> Bool {
        return line.contains("-->")
    }

    private static func isIndexLine(_ line: String) -> Bool {
        return Int(line) != nil
    }

    private static func normalize(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let lowered = text.lowercased()
        let cleaned = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let normalized = String(cleaned)
        return normalized.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenFrequencies(_ text: String) -> [String: Double] {
        let tokens = text.split(separator: " ").map(String.init)
        var counts: [String: Double] = [:]
        for token in tokens where token.count > 1 {
            if stopwords.contains(token) { continue }
            counts[token, default: 0] += 1
        }
        return counts
    }

    private static func cosineSimilarity(_ left: [String: Double], _ right: [String: Double]) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let leftNorm = sqrt(left.values.reduce(0) { $0 + $1 * $1 })
        let rightNorm = sqrt(right.values.reduce(0) { $0 + $1 * $1 })
        guard leftNorm > 0, rightNorm > 0 else { return 0 }
        let sharedKeys = Set(left.keys).intersection(right.keys)
        let dot = sharedKeys.reduce(0.0) { $0 + (left[$1] ?? 0) * (right[$1] ?? 0) }
        return dot / (leftNorm * rightNorm)
    }
}
