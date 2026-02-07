import Foundation

enum FilenameParser {
    static func parse(fileName: String) -> ParsedEpisode? {
        let baseName = fileName.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        if let match = matchSeasonEpisode(pattern: #"(?i)\bS(\d{1,2})[ ._-]*E(\d{1,2})[ ._-]*E(\d{1,2})\b"#, in: baseName, multiEpisode: true) {
            return match
        }
        if let match = matchSeasonEpisode(pattern: #"(?i)\bS(\d{1,2})[ ._-]*E(\d{1,2})[ ._-]*(?:-|\u2013)?[ ._-]*(\d{1,2})\b"#, in: baseName, multiEpisode: true) {
            return match
        }
        if let match = matchSeasonEpisode(pattern: #"(?i)\bS(\d{1,2})[ ._-]*E(\d{1,2})\b"#, in: baseName) {
            return match
        }
        if let match = matchSeasonEpisode(pattern: #"(?i)\b(\d{1,2})x(\d{1,2})[ ._-]*x?(\d{1,2})?\b"#, in: baseName, multiEpisode: true) {
            return match
        }
        if let match = matchSeasonEpisode(pattern: #"(?i)\b(\d{1,2})x(\d{1,2})\b"#, in: baseName) {
            return match
        }
        if let match = matchSeasonEpisodeFromWords(in: baseName) {
            return match
        }
        return nil
    }

    static func parseEpisodeHint(fileName: String) -> Int? {
        let baseName = fileName.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        if let number = matchNumber(pattern: #"(?i)\b(?:episode|ep|e|t)\s*0*(\d{1,2})\b"#, in: baseName) {
            return number
        }
        return nil
    }

    private static func matchSeasonEpisode(pattern: String, in name: String, multiEpisode: Bool = false) -> ParsedEpisode? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let result = regex.firstMatch(in: name, options: [], range: range) else {
            return nil
        }
        guard result.numberOfRanges >= 3,
              let seasonRange = Range(result.range(at: 1), in: name),
              let episodeRange = Range(result.range(at: 2), in: name) else {
            return nil
        }

        let seasonString = String(name[seasonRange])
        let episodeString = String(name[episodeRange])
        guard let season = Int(seasonString), let episode = Int(episodeString) else {
            return nil
        }

        var episodeEnd: Int? = nil
        if multiEpisode, result.numberOfRanges >= 4, let endRange = Range(result.range(at: 3), in: name) {
            if result.range(at: 3).location != NSNotFound {
                let endString = String(name[endRange])
                episodeEnd = Int(endString)
            }
        }

        let showName = extractShowName(from: name, matchRange: result.range)
        return ParsedEpisode(showName: showName, season: season, episode: episode, episodeEnd: episodeEnd)
    }

    private static func matchSeasonEpisodeFromWords(in name: String) -> ParsedEpisode? {
        guard let season = matchNumber(pattern: #"(?i)\bseason[ ._-]*(\d{1,2})\b"#, in: name),
              let episode = matchNumber(pattern: #"(?i)\b(?:episode|ep)[ ._-]*(\d{1,2})\b"#, in: name) else {
            return nil
        }
        let showName = extractShowNameFromWords(in: name)
        return ParsedEpisode(showName: showName, season: season, episode: episode, episodeEnd: nil)
    }

    private static func matchNumber(pattern: String, in name: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let result = regex.firstMatch(in: name, options: [], range: range),
              result.numberOfRanges >= 2,
              let numberRange = Range(result.range(at: 1), in: name) else {
            return nil
        }
        return Int(name[numberRange])
    }

    private static func extractShowName(from name: String, matchRange: NSRange) -> String {
        guard let range = Range(matchRange, in: name) else {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let prefix = name[..<range.lowerBound]
        let cleaned = prefix
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeShowName(cleaned, fallback: name)
    }

    private static func extractShowNameFromWords(in name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let split = cleaned.components(separatedBy: .whitespacesAndNewlines)
        let trimmed = split.prefix {
            let lower = $0.lowercased()
            return !lower.hasPrefix("season") && !lower.hasPrefix("episode") && !lower.hasPrefix("ep")
        }
        .joined(separator: " ")
        return normalizeShowName(trimmed, fallback: name)
    }

    private static func normalizeShowName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let yearStripped = stripTrailingYear(from: trimmed) {
            return yearStripped
        }
        return trimmed
    }

    private static func stripTrailingYear(from name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\s*(?:\(|\[)?(19\d{2}|20\d{2})(?:\)|\])?\s*$"#, options: []) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, options: [], range: range) else {
            return nil
        }
        guard let matchRange = Range(match.range, in: name) else {
            return nil
        }
        let stripped = name[..<matchRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}
