import AppKit
import Foundation

@MainActor
final class TVEpisodeMatcherMKVViewModel: ObservableObject {
    @Published var selectedFolder: String = "No folder selected" {
        didSet { SettingsStore.set(selectedFolder, for: SettingsKey.lastSelectedFolder) }
    }
    @Published var files: [MKVFile] = []
    @Published var selectedFile: MKVFile?
    @Published var showName: String = "" {
        didSet { SettingsStore.set(showName, for: SettingsKey.lastShowName) }
    }
    @Published var seasonInput: String = "" {
        didSet { SettingsStore.set(seasonInput, for: SettingsKey.lastSeasonInput) }
    }
    @Published var statusMessage: String = ""
    @Published var statusIsError: Bool = false
    @Published var isMatching: Bool = false
    @Published var logs: [LogEntry] = []
    @Published var episodeRangeInput: String = "" {
        didSet { SettingsStore.set(episodeRangeInput, for: SettingsKey.lastEpisodeRange) }
    }
    @Published var allRangeMatched: Bool = false
    @Published var lastRangeCount: Int = 0
    @Published var lastMatchedCount: Int = 0
    @Published var lastMissingEpisodes: [Int] = []
    @Published var showSuggestions: [TMDBShow] = []

    @Published var tmdbAccessToken: String {
        didSet { SettingsStore.set(tmdbAccessToken, for: SettingsKey.tmdbAccessToken) }
    }
    @Published var openSubtitlesApiKey: String {
        didSet { SettingsStore.set(openSubtitlesApiKey, for: SettingsKey.openSubtitlesApiKey) }
    }
    @Published var openSubtitlesUsername: String {
        didSet { SettingsStore.set(openSubtitlesUsername, for: SettingsKey.openSubtitlesUsername) }
    }
    @Published var openSubtitlesPassword: String {
        didSet { SettingsStore.set(openSubtitlesPassword, for: SettingsKey.openSubtitlesPassword) }
    }

    private var matchesById: [UUID: EpisodeMatch] = [:]
    private var fileDurations: [UUID: Double] = [:]
    private var showSuggestionCache: [String: [TMDBShow]] = [:]
    private var lastSelectedShowName: String?

    private struct SubtitleMatchInput: Sendable {
        let showName: String
        let seasonInput: String
        let episodeRangeInput: String
        let tmdbAccessToken: String
        let openSubtitlesApiKey: String
        let openSubtitlesUsername: String
        let openSubtitlesPassword: String
        let files: [MKVFile]
    }

    private struct SubtitleMatchOutcome: Sendable {
        let matchesById: [UUID: EpisodeMatch]
        let fileDurations: [UUID: Double]
        let statusMessage: String
        let statusIsError: Bool
        let lastRangeCount: Int
        let lastMatchedCount: Int
        let lastMissingEpisodes: [Int]
        let logs: [LogEntry]
    }


    init() {
        tmdbAccessToken = SettingsStore.get(SettingsKey.tmdbAccessToken)
        openSubtitlesApiKey = SettingsStore.get(SettingsKey.openSubtitlesApiKey)
        openSubtitlesUsername = SettingsStore.get(SettingsKey.openSubtitlesUsername)
        openSubtitlesPassword = SettingsStore.get(SettingsKey.openSubtitlesPassword)
        showName = SettingsStore.get(SettingsKey.lastShowName)
        seasonInput = SettingsStore.get(SettingsKey.lastSeasonInput)
        episodeRangeInput = SettingsStore.get(SettingsKey.lastEpisodeRange)
        let savedFolder = SettingsStore.get(SettingsKey.lastSelectedFolder)
        if !savedFolder.isEmpty, FileManager.default.fileExists(atPath: savedFolder) {
            selectedFolder = savedFolder
            files = loadMKVFiles(in: URL(fileURLWithPath: savedFolder))
        }
    }

    var canRename: Bool {
        matchesById.values.contains { $0.bestCandidate != nil }
    }

    var canMatchBySubtitles: Bool {
        let trimmedShow = showName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = episodeRangeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let seasonValid = Int(seasonInput.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        let folderSelected = !selectedFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedFolder != "No folder selected"
        return folderSelected
            && seasonValid
            && !trimmedShow.isEmpty
            && !trimmedRange.isEmpty
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url.path
            files = loadMKVFiles(in: url)
            selectedFile = nil
            matchesById = [:]
            fileDurations = [:]
        }
    }


    func matchForFile(_ file: MKVFile) -> EpisodeMatch? {
        matchesById[file.id]
    }

    func clearShowSuggestions() {
        showSuggestions = []
    }

    func selectShowSuggestion(_ show: TMDBShow) {
        showName = show.name
        showSuggestions = []
        lastSelectedShowName = show.name
    }

    func fetchShowSuggestions(query: String, limit: Int = 8) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            showSuggestions = []
            return
        }
        if let lastSelectedShowName, trimmed != lastSelectedShowName {
            self.lastSelectedShowName = nil
        }
        if let lastSelectedShowName, trimmed == lastSelectedShowName {
            showSuggestions = []
            return
        }
        guard !tmdbAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showSuggestions = []
            return
        }
        let cacheKey = trimmed.normalizedTokenString
        if let cached = showSuggestionCache[cacheKey] {
            showSuggestions = cached
            return
        }

        do {
            let tmdb = TMDBClient(accessToken: tmdbAccessToken)
            let results = try await tmdb.searchShows(name: trimmed, limit: limit)
            showSuggestionCache[cacheKey] = results
            showSuggestions = results
        } catch {
            showSuggestions = []
            log(.warning, "Show suggestions failed: \(error.localizedDescription)")
        }
    }

    func autoAssignBySubtitles() async {
        isMatching = true
        statusIsError = false
        statusMessage = "Matching by subtitles..."
        let input = SubtitleMatchInput(
            showName: showName,
            seasonInput: seasonInput,
            episodeRangeInput: episodeRangeInput,
            tmdbAccessToken: tmdbAccessToken,
            openSubtitlesApiKey: openSubtitlesApiKey,
            openSubtitlesUsername: openSubtitlesUsername,
            openSubtitlesPassword: openSubtitlesPassword,
            files: files,
        )

        let outcome = await Task.detached(priority: .userInitiated) {
            await Self.runSubtitleMatch(input: input)
        }.value

        matchesById = outcome.matchesById
        fileDurations = outcome.fileDurations
        lastRangeCount = outcome.lastRangeCount
        lastMatchedCount = outcome.lastMatchedCount
        lastMissingEpisodes = outcome.lastMissingEpisodes
        statusMessage = outcome.statusMessage
        statusIsError = outcome.statusIsError
        logs.append(contentsOf: outcome.logs)
        isMatching = false
    }

    nonisolated private static func runSubtitleMatch(input: SubtitleMatchInput) async -> SubtitleMatchOutcome {
        var logs: [LogEntry] = []
        func log(_ level: LogLevel, _ message: String) {
            logs.append(LogEntry(timestamp: Date(), level: level, message: message))
        }
        func formatMinutes(_ seconds: Double) -> String {
            String(format: "%.1f", seconds / 60.0)
        }

        func failure(_ message: String, logMessage: String) -> SubtitleMatchOutcome {
            log(.error, logMessage)
            return SubtitleMatchOutcome(
                matchesById: [:],
                fileDurations: [:],
                statusMessage: message,
                statusIsError: true,
                lastRangeCount: 0,
                lastMatchedCount: 0,
                lastMissingEpisodes: [],
                logs: logs
            )
        }

        log(.info, "Subtitle match started range='\(input.episodeRangeInput)'")

        let trimmedShow = input.showName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShow.isEmpty else {
            return failure("Enter a show name.", logMessage: "Show name missing")
        }

        guard let seasonNumber = Int(input.seasonInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return failure("Enter a valid season number.", logMessage: "Invalid season input: '\(input.seasonInput)'")
        }

        guard let range = Self.parseEpisodeRange(input.episodeRangeInput) else {
            return failure("Enter an episode range like 13-24.", logMessage: "Invalid episode range '\(input.episodeRangeInput)'")
        }


        guard !input.tmdbAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failure("Enter a TMDB access token.", logMessage: "TMDB access token missing")
        }

        let hasOpenSubtitlesCreds = !input.openSubtitlesApiKey.isEmpty
            && !input.openSubtitlesUsername.isEmpty
            && !input.openSubtitlesPassword.isEmpty

        do {
            let tmdb = TMDBClient(accessToken: input.tmdbAccessToken)
            guard let show = try await tmdb.searchShow(name: trimmedShow) else {
                return failure("No show found for \(trimmedShow).", logMessage: "TMDB search returned no show for '\(trimmedShow)'")
            }

            guard let season = try await tmdb.fetchSeason(showId: show.id, seasonNumber: seasonNumber) else {
                return failure("No season \(seasonNumber) found for \(show.name).", logMessage: "TMDB season not found showId=\(show.id) season=\(seasonNumber)")
            }

            log(.info, "TMDB show matched id=\(show.id) name='\(show.name)' episodes=\(season.episodes.count)")

            let expectedRangeCount = max(0, range.upperBound - range.lowerBound + 1)
            let episodesInRange = season.episodes
                .filter { range.contains($0.episodeNumber) }
                .sorted { $0.episodeNumber < $1.episodeNumber }
            if episodesInRange.isEmpty {
                return failure(
                    "No episodes found in range \(range.lowerBound)-\(range.upperBound).",
                    logMessage: "No episodes in range \(range)"
                )
            }

            var lastMissingEpisodes: [Int] = []
            if episodesInRange.count != expectedRangeCount {
                lastMissingEpisodes = Self.missingEpisodeNumbers(range: range, episodes: episodesInRange)
                log(.warning, "TMDB returned \(episodesInRange.count) episodes for range \(range.lowerBound)-\(range.upperBound) (expected \(expectedRangeCount)). Missing: \(lastMissingEpisodes)")
            }

            let durations = await Self.loadDurations(files: input.files, log: log)
            let files = input.files
            log(.info, "Duration scan complete for \(durations.count)/\(files.count) files")
            for file in files {
                if let duration = durations[file.id] {
                    log(.info, "File duration file='\(file.name)' minutes=\(formatMinutes(duration))")
                } else {
                    log(.warning, "File duration missing file='\(file.name)'")
                }
            }
            var updatedMatches: [UUID: EpisodeMatch] = [:]
            var matchedEpisodes: Set<Int> = []
            var highConfidenceMatches = 0

            if !hasOpenSubtitlesCreds {
                log(.warning, "OpenSubtitles credentials missing; subtitle matching disabled")
            } else {
                let fileSamples = Self.extractFileSubtitleSamples(files, log: log)
                if fileSamples.isEmpty {
                    log(.warning, "No embedded English subtitles found; skipping subtitle match")
                } else {
                    var episodeSamples: [Int: String] = [:]
                    let client = OpenSubtitlesClient(
                        apiKey: input.openSubtitlesApiKey,
                        username: input.openSubtitlesUsername,
                        password: input.openSubtitlesPassword
                    )
                    for episode in episodesInRange {
                        if let sample = try await Self.downloadEnglishSubtitleSample(
                            client: client,
                            showId: show.id,
                            seasonNumber: seasonNumber,
                            episodeNumber: episode.episodeNumber,
                            log: log
                        ) {
                            episodeSamples[episode.episodeNumber] = sample
                            if let runtime = episode.runtime {
                                log(.info, "Episode runtime E\(episode.episodeNumber.twoDigit) minutes=\(runtime)")
                            } else {
                                log(.warning, "Episode runtime missing E\(episode.episodeNumber.twoDigit)")
                            }
                        }
                    }

                    if episodeSamples.isEmpty {
                        log(.warning, "No OpenSubtitles samples downloaded")
                    } else {
                        let threshold = 0.55
                        let margin: Double = 0.05
                        let maxDurationDelta: Double = 0.10
                        let sortedFiles = fileSamples.keys.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        let cost = Self.buildSubtitleCostMatrix(
                            files: sortedFiles,
                            fileSamples: fileSamples,
                            episodes: episodesInRange,
                            episodeSamples: episodeSamples
                        )
                        let assignment = AssignmentSolver.hungarian(cost)
                        let duplicates = Self.duplicateEpisodeTitleMap(episodesInRange)

                        for (index, file) in sortedFiles.enumerated() {
                            let assignedIndex = assignment[index]
                            guard assignedIndex >= 0, assignedIndex < episodesInRange.count else {
                                log(.warning, "Subtitle match left unmatched file='\(file.name)'")
                                continue
                            }
                            let episode = episodesInRange[assignedIndex]
                            guard let fileSample = fileSamples[file],
                                  let episodeSample = episodeSamples[episode.episodeNumber] else {
                                continue
                            }
                            let topMatches = episodesInRange.compactMap { candidate -> (episode: TMDBEpisode, score: Double)? in
                                guard let sample = episodeSamples[candidate.episodeNumber] else { return nil }
                                let score = SubtitleMatcher.similarity(fileSample, sample)
                                return (candidate, score)
                            }
                            .sorted { $0.score > $1.score }
                            .prefix(3)
                            let topMatchText = topMatches.map { match in
                                "E\(match.episode.episodeNumber.twoDigit) \(match.episode.name) \(String(format: "%.2f", match.score))"
                            }.joined(separator: " | ")
                            if !topMatchText.isEmpty {
                                log(.info, "Top subtitle matches file='\(file.name)': \(topMatchText)")
                            }
                            var score = SubtitleMatcher.similarity(fileSample, episodeSample)
                            var chosen = episode
                            var scoreText = String(format: "%.2f", score)
                            if let best = topMatches.first, topMatches.count > 1 {
                                let second = topMatches[topMatches.index(after: topMatches.startIndex)]
                                let delta = best.score - second.score
                                if delta < margin {
                                    log(.warning, "Subtitle match rejected (low margin) file='\(file.name)' best=E\(best.episode.episodeNumber) score=\(String(format: "%.2f", best.score)) delta=\(String(format: "%.2f", delta))")
                                    continue
                                }
                            }

                            if let dupes = duplicates[episode.name], dupes.count > 1 {
                                if let tieBroken = Self.tieBreakDuplicate(
                                    file: file,
                                    fileSample: fileSample,
                                    episodes: dupes,
                                    episodeSamples: episodeSamples
                                ) {
                                    chosen = tieBroken.episode
                                    score = tieBroken.score
                                    scoreText = String(format: "%.2f", score)
                                }
                            }

                            if score < threshold {
                                log(.warning, "Subtitle match low similarity file='\(file.name)' episode=E\(chosen.episodeNumber) score=\(scoreText)")
                                continue
                            }

                            let durationChecked = durations[file.id] != nil
                            var durationUsed = false
                            if let fileDuration = durations[file.id], let runtime = chosen.runtime {
                                durationUsed = true
                                let runtimeSeconds = Double(runtime) * 60.0
                                let delta = abs(fileDuration - runtimeSeconds) / runtimeSeconds
                                if delta > maxDurationDelta {
                                    log(.warning, "Duration gate rejected file='\(file.name)' episode=E\(chosen.episodeNumber) fileMin=\(formatMinutes(fileDuration)) epMin=\(runtime) delta=\(String(format: "%.2f", delta))")
                                    continue
                                }
                                log(.info, "Duration gate accepted file='\(file.name)' episode=E\(chosen.episodeNumber) fileMin=\(formatMinutes(fileDuration)) epMin=\(runtime) delta=\(String(format: "%.2f", delta))")
                            } else if chosen.runtime == nil {
                                log(.warning, "Duration gate skipped (missing runtime) file='\(file.name)' episode=E\(chosen.episodeNumber)")
                            } else if durations[file.id] == nil {
                                log(.warning, "Duration gate skipped (missing file duration) file='\(file.name)' episode=E\(chosen.episodeNumber)")
                            }

                            let candidate = MatchCandidate(episode: chosen, score: 0.9, reasons: ["Subtitles"])
                            let status = MatchStatus(
                                durationChecked: durationChecked,
                                durationUsed: durationUsed,
                                subtitlesAttempted: true,
                                subtitlesMatched: true,
                                subtitlesError: "Subtitle similarity \(scoreText)",
                                filenamePatternsUsed: false
                            )
                            updatedMatches[file.id] = EpisodeMatch(
                                file: file,
                                bestCandidate: candidate,
                                candidates: [candidate],
                                proposedName: Self.renameTemplate(for: chosen),
                                status: status
                            )
                            matchedEpisodes.insert(chosen.episodeNumber)
                            highConfidenceMatches += 1
                        }
                    }
                }
            }

            let matchedEpisodeNumbers = Set(updatedMatches.values.compactMap { $0.bestCandidate?.episode.episodeNumber })
            let matchedEpisodesCount = matchedEpisodeNumbers.count
            let statusMessage: String
            if highConfidenceMatches > 0 {
                statusMessage = "Matched \(highConfidenceMatches) file(s) by subtitles."
            } else {
                statusMessage = "No matches found."
            }
            log(.info, "Subtitle match completed subtitles=\(highConfidenceMatches)")

            return SubtitleMatchOutcome(
                matchesById: updatedMatches,
                fileDurations: durations,
                statusMessage: statusMessage,
                statusIsError: false,
                lastRangeCount: expectedRangeCount,
                lastMatchedCount: matchedEpisodesCount,
                lastMissingEpisodes: lastMissingEpisodes,
                logs: logs
            )
        } catch {
            log(.error, "Subtitle match failed: \(error.localizedDescription)")
            return SubtitleMatchOutcome(
                matchesById: [:],
                fileDurations: [:],
                statusMessage: "Subtitle match failed: \(error.localizedDescription)",
                statusIsError: true,
                lastRangeCount: 0,
                lastMatchedCount: 0,
                lastMissingEpisodes: [],
                logs: logs
            )
        }
    }

    private func updateRangeMatchStatus(rangeCount: Int, matchedCount: Int) {
        lastRangeCount = rangeCount
        lastMatchedCount = matchedCount
        allRangeMatched = rangeCount > 0 && matchedCount >= rangeCount
    }

    nonisolated private static func missingEpisodeNumbers(range: ClosedRange<Int>, episodes: [TMDBEpisode]) -> [Int] {
        let present = Set(episodes.map { $0.episodeNumber })
        return (range.lowerBound...range.upperBound).filter { !present.contains($0) }
    }

    nonisolated private static func duplicateEpisodeTitleMap(_ episodes: [TMDBEpisode]) -> [String: [TMDBEpisode]] {
        var map: [String: [TMDBEpisode]] = [:]
        for episode in episodes {
            map[episode.name, default: []].append(episode)
        }
        return map.filter { $0.value.count > 1 }
    }

    nonisolated private static func tieBreakDuplicate(
        file: MKVFile,
        fileSample: String,
        episodes: [TMDBEpisode],
        episodeSamples: [Int: String]
    ) -> (episode: TMDBEpisode, score: Double)? {
        var best: (TMDBEpisode, Double)? = nil
        for episode in episodes {
            guard let sample = episodeSamples[episode.episodeNumber] else { continue }
            let similarity = SubtitleMatcher.similarity(fileSample, sample)
            var score = similarity
            if best == nil || score > best!.1 {
                best = (episode, score)
            }
        }
        return best.map { ($0.0, $0.1) }
    }


    func openTMDBSettings() {
        guard let url = URL(string: "https://www.themoviedb.org/settings/api") else { return }
        NSWorkspace.shared.open(url)
    }

    func openOpenSubtitlesSettings() {
        guard let url = URL(string: "https://www.opensubtitles.com/en/consumers") else { return }
        NSWorkspace.shared.open(url)
    }

    func renameMatchedFiles() {
        let fileManager = FileManager.default
        var renamedCount = 0

        for match in matchesById.values {
            guard let proposedName = match.proposedName else { continue }
            let destinationFolder = match.file.url.deletingLastPathComponent()
            let destinationURL = uniqueDestinationURL(for: match.file.url, newName: proposedName, in: destinationFolder)
            do {
                try fileManager.moveItem(at: match.file.url, to: destinationURL)
                renamedCount += 1
            } catch {
                statusMessage = "Rename failed for \(match.file.name): \(error.localizedDescription)"
                statusIsError = true
            }
        }

        if renamedCount > 0 {
            let parentFolders = Set(matchesById.values.map { $0.file.url.deletingLastPathComponent() })
            if let first = parentFolders.first {
                files = loadMKVFiles(in: first)
            }
            matchesById = [:]
            selectedFile = nil
        }

        statusMessage = "Renamed \(renamedCount) file(s)."
        statusIsError = false
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func log(_ level: LogLevel, _ message: String) {
        logs.append(LogEntry(timestamp: Date(), level: level, message: message))
    }

    nonisolated private static func parseEpisodeRange(_ input: String) -> ClosedRange<Int>? {
        let cleaned = input.replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: "-")
        if parts.count == 1, let value = Int(parts[0]) {
            return value...value
        }
        if parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start <= end {
            return start...end
        }
        return nil
    }

    nonisolated private static func buildSubtitleCostMatrix(files: [MKVFile], fileSamples: [MKVFile: String], episodes: [TMDBEpisode], episodeSamples: [Int: String]) -> [[Double]] {
        var matrix: [[Double]] = []
        for file in files {
            guard let fileSample = fileSamples[file] else { continue }
            var row: [Double] = []
            for episode in episodes {
                let episodeSample = episodeSamples[episode.episodeNumber] ?? ""
                let similarity = SubtitleMatcher.similarity(fileSample, episodeSample)
                row.append(1.0 - similarity)
            }
            matrix.append(row)
        }
        // Pad square with neutral cost
        let size = max(matrix.count, episodes.count)
        if size == 0 { return matrix }
        for i in 0..<size {
            if i >= matrix.count {
                matrix.append(Array(repeating: 1.0, count: size))
            } else if matrix[i].count < size {
                matrix[i].append(contentsOf: Array(repeating: 1.0, count: size - matrix[i].count))
            }
        }
        return matrix
    }

    nonisolated private static func loadDurations(
        files: [MKVFile],
        log: (LogLevel, String) -> Void
    ) async -> [UUID: Double] {
        var durations: [UUID: Double] = [:]
        await withTaskGroup(of: (MKVFile, DurationInfo).self) { group in
            for file in files {
                group.addTask {
                    let info = await DurationInfoService.durationInfo(for: file.url)
                    return (file, info)
                }
            }

            for await (file, info) in group {
                if let duration = info.duration {
                    durations[file.id] = duration
                } else if let error = info.error {
                    log(.warning, "Duration failed file='\(file.name)' source=\(info.source) error=\(error)")
                } else {
                    log(.warning, "Duration missing file='\(file.name)' source=\(info.source)")
                }
            }
        }
        return durations
    }

    nonisolated private static func extractFileSubtitleSamples(
        _ files: [MKVFile],
        log: (LogLevel, String) -> Void
    ) -> [MKVFile: String] {
        var samples: [MKVFile: String] = [:]
        for file in files {
            let result = SubtitleExtractionService.extractEnglishSubtitleSample(
                from: file.url,
                subtitleEditPath: nil
            )
            if let sample = result.sample {
                samples[file] = sample
                log(.info, "Extracted embedded subtitles file='\(file.name)' codec=\(result.codec ?? "unknown")")
            } else {
                let errorText = result.error ?? "Unknown subtitle extraction failure"
                log(.warning, "No embedded subtitles file='\(file.name)' error=\(errorText)")
            }
        }
        return samples
    }

    nonisolated private static func downloadEnglishSubtitleSample(
        client: OpenSubtitlesClient,
        showId: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        log: (LogLevel, String) -> Void
    ) async throws -> String? {
        let results = try await client.searchSubtitles(
            parentTmdbId: showId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            language: "en"
        )
        guard let first = results.first, let fileId = first.attributes.files?.first?.fileId else {
            return nil
        }
        if let cached = loadCachedSubtitle(
            showId: showId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            fileId: fileId
        ) {
            return SubtitleMatcher.fullText(from: cached)
        }
        let data = try await client.downloadSubtitle(fileId: fileId)
        if cacheSubtitle(data, showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber, fileId: fileId) {
            log(.info, "Cached subtitle showId=\(showId) S\(seasonNumber)E\(episodeNumber) fileId=\(fileId)")
        }
        return SubtitleMatcher.fullText(from: data)
    }

    nonisolated private static func cacheSubtitle(
        _ data: Data,
        showId: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        fileId: Int
    ) -> Bool {
        guard let url = subtitleCacheURL(
            showId: showId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            fileId: fileId
        ) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func loadCachedSubtitle(showId: Int, seasonNumber: Int, episodeNumber: Int, fileId: Int) -> Data? {
        guard let url = subtitleCacheURL(
            showId: showId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            fileId: fileId
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    nonisolated private static func subtitleCacheURL(showId: Int, seasonNumber: Int, episodeNumber: Int, fileId: Int) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("TVEpisodeMatcherMKV/subtitles", isDirectory: true)
        let fileName = "tmdb_\(showId)_s\(seasonNumber)_e\(episodeNumber)_file_\(fileId).bin"
        return folder.appendingPathComponent(fileName)
    }



    nonisolated private static func renameTemplate(for episode: TMDBEpisode) -> String {
        let title = sanitizeForFilename(episode.name)
        return "\(title)_S\(episode.seasonNumber.twoDigit)E\(episode.episodeNumber.twoDigit).mkv"
    }

    nonisolated private static func sanitizeForFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let collapsed = cleaned.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
    }

    private func uniqueDestinationURL(for original: URL, newName: String, in folder: URL) -> URL {
        var destination = folder.appendingPathComponent(newName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let baseName = newName.replacingOccurrences(of: ".mkv", with: "")
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let candidate = "\(baseName)_\(counter).mkv"
            destination = folder.appendingPathComponent(candidate)
            counter += 1
        }
        return destination
    }

    private func loadMKVFiles(in folderURL: URL) -> [MKVFile] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var results: [MKVFile] = []
        for case let fileURL as URL in enumerator {
            let pathExtension = fileURL.pathExtension.lowercased()
            if pathExtension != "mkv" {
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if resourceValues?.isRegularFile == true {
                let size = Int64(resourceValues?.fileSize ?? 0)
                results.append(MKVFile(url: fileURL, fileSize: size))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

}
