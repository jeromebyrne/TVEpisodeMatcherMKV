import Foundation

enum SettingsKey {
    static let tmdbAccessToken = "tmdbAccessToken"
    static let openSubtitlesApiKey = "openSubtitlesApiKey"
    static let openSubtitlesUsername = "openSubtitlesUsername"
    static let openSubtitlesPassword = "openSubtitlesPassword"
    static let openSubtitlesParentImdbIdOverride = "openSubtitlesParentImdbIdOverride"
    static let openSubtitlesSeasonOffsetInput = "openSubtitlesSeasonOffsetInput"
    static let subtitleSimilarityThreshold = "subtitleSimilarityThreshold"
    static let lastShowName = "lastShowName"
    static let lastSeasonInput = "lastSeasonInput"
    static let lastEpisodeRange = "lastEpisodeRange"
    static let lastSelectedFolder = "lastSelectedFolder"
}

enum SettingsStore {
    private static let defaults = UserDefaults.standard

    static func set(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
    }

    static func set(_ value: Double, for key: String) {
        defaults.set(value, forKey: key)
    }

    static func get(_ key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }

    static func getDouble(_ key: String, defaultValue: Double) -> Double {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.double(forKey: key)
    }
}
