import Foundation

extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    var normalizedTokenString: String {
        let tokens = tokenizedWords
        return tokens.joined(separator: " ")
    }

    var tokenizedWords: [String] {
        let allowed = CharacterSet.alphanumerics
        let lowered = lowercased()
        let cleaned = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let normalized = String(cleaned)
        return normalized.split(separator: " ").map(String.init)
    }

    func tokenOverlapScore(with other: String) -> Int {
        let left = Set(tokenizedWords)
        let right = Set(other.tokenizedWords)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let overlap = left.intersection(right).count
        let ratio = Double(overlap) / Double(max(left.count, right.count))
        return Int(ratio * 25)
    }
}
