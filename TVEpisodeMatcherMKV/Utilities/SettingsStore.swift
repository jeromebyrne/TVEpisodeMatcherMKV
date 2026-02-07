import Foundation

enum SettingsKey {
    static let tmdbAccessToken = "tmdbAccessToken"
    static let openSubtitlesApiKey = "openSubtitlesApiKey"
    static let openSubtitlesUsername = "openSubtitlesUsername"
    static let openSubtitlesPassword = "openSubtitlesPassword"
    static let lastShowName = "lastShowName"
    static let lastSeasonInput = "lastSeasonInput"
    static let lastEpisodeRange = "lastEpisodeRange"
    static let subtitleEditCliPath = "subtitleEditCliPath"
    static let lastSelectedFolder = "lastSelectedFolder"
}

enum SettingsStore {
    private static let defaults = UserDefaults.standard

    static func set(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
    }

    static func get(_ key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }
}
