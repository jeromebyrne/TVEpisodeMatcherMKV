import Foundation

struct MKVFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let fileSize: Int64

    var name: String {
        url.lastPathComponent
    }
}

struct ParsedEpisode: Hashable, Sendable {
    let showName: String
    let season: Int
    let episode: Int
    let episodeEnd: Int?
}

struct TMDBShow: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let originalName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case originalName = "original_name"
    }
}

struct TMDBSearchResponse: Decodable, Sendable {
    let results: [TMDBShow]
}

struct TMDBSeasonResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodes: [TMDBEpisode]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case seasonNumber = "season_number"
        case episodes
    }
}

struct TMDBEpisode: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeNumber: Int
    let airDate: String?
    let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case runtime
    }
}

struct MatchCandidate: Identifiable, Hashable, Sendable {
    let id = UUID()
    let episode: TMDBEpisode
    let score: Double
    let reasons: [String]

    var scoreDescription: String {
        let percent = Int(score * 100)
        if reasons.isEmpty {
            return "Score: \(percent)%"
        }
        return "Score: \(percent)% • \(reasons.joined(separator: ", "))"
    }

    var confidenceLabel: String {
        switch score {
        case 0.75...:
            return "High"
        case 0.66..<0.75:
            return "Medium"
        case 0.55..<0.66:
            return "Low"
        default:
            return "Very Low"
        }
    }
}

struct EpisodeMatch: Identifiable, Hashable, Sendable {
    let id = UUID()
    let file: MKVFile
    let bestCandidate: MatchCandidate?
    let candidates: [MatchCandidate]
    let proposedName: String?
    let status: MatchStatus
}

struct MatchStatus: Hashable, Sendable {
    let durationChecked: Bool
    let durationUsed: Bool
    let subtitlesAttempted: Bool
    let subtitlesMatched: Bool
    let subtitlesError: String?
    let filenamePatternsUsed: Bool
}

struct LogEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

enum LogLevel: String, Hashable, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

extension Int {
    var twoDigit: String {
        String(format: "%02d", self)
    }
}
