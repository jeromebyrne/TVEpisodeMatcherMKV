import Foundation

enum SubtitleMatcher {
    struct Diagnostics: Sendable {
        let leftTotalTokenCount: Int
        let rightTotalTokenCount: Int
        let leftUniqueTokenCount: Int
        let rightUniqueTokenCount: Int
        let sharedUniqueTokenCount: Int
        let wordCosineSimilarity: Double
        let bigramCosineSimilarity: Double
        let characterTrigramSimilarity: Double
        let cosineSimilarity: Double
    }

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
        similarityDiagnostics(left, right).cosineSimilarity
    }

    static func tokenStats(for text: String) -> (totalTokenCount: Int, uniqueTokenCount: Int) {
        let frequencies = tokenFrequencies(text)
        let total = Int(frequencies.values.reduce(0, +))
        return (total, frequencies.count)
    }

    static func similarityDiagnostics(_ left: String, _ right: String) -> Diagnostics {
        let leftTokens = tokenFrequencies(left)
        let rightTokens = tokenFrequencies(right)
        let leftWords = normalizedWords(from: left, removingStopwords: false)
        let rightWords = normalizedWords(from: right, removingStopwords: false)
        let leftBigrams = ngramFrequencies(words: leftWords, size: 2)
        let rightBigrams = ngramFrequencies(words: rightWords, size: 2)
        let leftTrigrams = characterShingles(from: normalize(left), size: 3)
        let rightTrigrams = characterShingles(from: normalize(right), size: 3)
        let leftTotal = Int(leftTokens.values.reduce(0, +))
        let rightTotal = Int(rightTokens.values.reduce(0, +))
        let sharedUnique = Set(leftTokens.keys).intersection(rightTokens.keys).count
        let minimumMeaningfulTokens = 20
        let wordScore: Double
        if leftTotal < minimumMeaningfulTokens || rightTotal < minimumMeaningfulTokens {
            wordScore = 0
        } else {
            wordScore = cosineSimilarity(leftTokens, rightTokens)
        }

        let bigramScore: Double
        if leftWords.count < 8 || rightWords.count < 8 {
            bigramScore = 0
        } else {
            bigramScore = cosineSimilarity(leftBigrams, rightBigrams)
        }

        let trigramScore = jaccardSimilarity(leftTrigrams, rightTrigrams)

        let components: [(Double, Double)] = [
            (wordScore, 0.45),
            (bigramScore, 0.35),
            (trigramScore, 0.20)
        ]
        let activeComponents = components.filter { $0.0 > 0 }
        let score: Double
        if activeComponents.isEmpty {
            score = 0
        } else {
            let totalWeight = activeComponents.reduce(0.0) { $0 + $1.1 }
            score = activeComponents.reduce(0.0) { $0 + ($1.0 * $1.1) } / totalWeight
        }
        return Diagnostics(
            leftTotalTokenCount: leftTotal,
            rightTotalTokenCount: rightTotal,
            leftUniqueTokenCount: leftTokens.count,
            rightUniqueTokenCount: rightTokens.count,
            sharedUniqueTokenCount: sharedUnique,
            wordCosineSimilarity: wordScore,
            bigramCosineSimilarity: bigramScore,
            characterTrigramSimilarity: trigramScore,
            cosineSimilarity: score
        )
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

    private static func tokenFrequencies(_ text: String, removingStopwords: Bool = true) -> [String: Double] {
        let tokens = normalizedWords(from: text, removingStopwords: removingStopwords)
        var counts: [String: Double] = [:]
        for token in tokens where token.count > 1 {
            counts[token, default: 0] += 1
        }
        return counts
    }

    private static func normalizedWords(from text: String, removingStopwords: Bool) -> [String] {
        let tokens = normalize(text).split(separator: " ").map(String.init)
        guard removingStopwords else { return tokens }
        return tokens.filter { $0.count > 1 && !stopwords.contains($0) }
    }

    private static func ngramFrequencies(words: [String], size: Int) -> [String: Double] {
        guard words.count >= size else { return [:] }
        var counts: [String: Double] = [:]
        for index in 0...(words.count - size) {
            let gram = words[index..<(index + size)].joined(separator: " ")
            counts[gram, default: 0] += 1
        }
        return counts
    }

    private static func characterShingles(from text: String, size: Int) -> Set<String> {
        let characters = Array(text)
        guard characters.count >= size else { return [] }
        var shingles: Set<String> = []
        for index in 0...(characters.count - size) {
            shingles.insert(String(characters[index..<(index + size)]))
        }
        return shingles
    }

    private static func jaccardSimilarity(_ left: Set<String>, _ right: Set<String>) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
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
