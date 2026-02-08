import Foundation

enum SubtitleExtractionService {
    static func extractEnglishSubtitleSample(from url: URL, subtitleEditPath: String?) -> SubtitleExtractionResult {
        guard let ffprobePath = resolveFFprobePath() else {
            return SubtitleExtractionResult(sample: nil, error: "ffprobe not found (run tools/install_deps.sh)", codec: nil)
        }
        guard let ffmpegPath = resolveFFmpegPath() else {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg not found (run tools/install_deps.sh)", codec: nil)
        }

        let (streamInfo, streamError) = subtitleStreamInfo(fileURL: url, ffprobePath: ffprobePath)
        guard let streamInfo else {
            return SubtitleExtractionResult(sample: nil, error: streamError ?? "No subtitle streams found", codec: nil)
        }

        if let codec = streamInfo.codec, !isTextSubtitleCodec(codec) {
            if codec == "hdmv_pgs_subtitle" {
                guard let seconvPath = resolveSubtitleEditPath(preferred: subtitleEditPath) else {
                    let details = "no seconv at preferred='\(subtitleEditPath ?? "")' cwd='\(FileManager.default.currentDirectoryPath)'"
                    return SubtitleExtractionResult(sample: nil, error: "PGS subtitles require OCR (SubtitleEdit CLI not found: \(details)). Run tools/install_deps.sh", codec: codec)
                }
                NSLog("SubtitleEdit CLI resolved path: %@", seconvPath)
                return extractPgsWithOcr(
                    fileURL: url,
                    streamIndex: streamInfo.index,
                    ffmpegPath: ffmpegPath,
                    seconvPath: seconvPath
                )
            }
            return SubtitleExtractionResult(sample: nil, error: "Unsupported subtitle codec \(codec)", codec: codec)
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".srt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        applyBundledLibraryPathIfNeeded(to: process, toolDirName: "ffmpeg")
        process.arguments = [
            "-y",
            "-i", url.path,
            "-map", "0:\(streamInfo.index)",
            "-c:s", "srt",
            outputURL.path
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg launch failed: \(error.localizedDescription)", codec: streamInfo.codec)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg exit \(process.terminationStatus)", codec: streamInfo.codec)
        }

        guard let data = try? Data(contentsOf: outputURL) else {
            return SubtitleExtractionResult(sample: nil, error: "Failed to read extracted subtitles", codec: streamInfo.codec)
        }
        try? FileManager.default.removeItem(at: outputURL)
        let sample = SubtitleMatcher.fullText(from: data)
        if sample == nil {
            return SubtitleExtractionResult(sample: nil, error: "Subtitle text decode failed", codec: streamInfo.codec)
        }
        return SubtitleExtractionResult(sample: sample, error: nil, codec: streamInfo.codec)
    }

    private static func subtitleStreamInfo(fileURL: URL, ffprobePath: String) -> (SubtitleStreamInfo?, String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        applyBundledLibraryPathIfNeeded(to: process, toolDirName: "ffmpeg")
        process.arguments = [
            "-v", "error",
            "-select_streams", "s",
            "-show_entries", "stream=index,codec_name:stream_tags=language",
            "-of", "json",
            fileURL.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return (nil, "ffprobe launch failed: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "unknown error"
            return (nil, "ffprobe exit \(process.terminationStatus): \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]] else {
            return (nil, "ffprobe returned no streams")
        }
        if streams.isEmpty {
            return (nil, "ffprobe found 0 subtitle streams")
        }

        // Prefer English language tracks
        for stream in streams {
            guard let index = stream["index"] as? Int else { continue }
            let tags = stream["tags"] as? [String: Any]
            let language = (tags?["language"] as? String)?.lowercased() ?? ""
            let codec = (stream["codec_name"] as? String)?.lowercased()
            if language == "eng" || language == "en" {
                return (SubtitleStreamInfo(index: index, codec: codec), nil)
            }
        }

        // Fallback to first subtitle stream
        if let first = streams.first, let index = first["index"] as? Int {
            let codec = (first["codec_name"] as? String)?.lowercased()
            return (SubtitleStreamInfo(index: index, codec: codec), nil)
        }

        return (nil, "ffprobe found subtitle streams but none usable")
    }

    private static func isTextSubtitleCodec(_ codec: String) -> Bool {
        let supported = ["subrip", "ass", "ssa", "mov_text", "webvtt", "srt"]
        return supported.contains(codec)
    }

    private static func resolveFFprobePath() -> String? {
        if let bundled = resolveBundledToolBinary(toolDirName: "ffmpeg", binaryName: "ffprobe") {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func resolveFFmpegPath() -> String? {
        if let bundled = resolveBundledToolBinary(toolDirName: "ffmpeg", binaryName: "ffmpeg") {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func resolveSubtitleEditPath(preferred: String?) -> String? {
        if let preferred, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let resolved = resolveSeconvBinary(from: preferred) {
                return resolved
            }
            let cwdCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(preferred).path
            if let resolved = resolveSeconvBinary(from: cwdCandidate) {
                return resolved
            }
            if let bundleResolved = resolveSeconvInBundleResources(relativePath: preferred) {
                return bundleResolved
            }
            if let bundleResolved = resolveSeconvRelativeToBundle(relativePath: preferred) {
                return bundleResolved
            }
        }
        if let bundleResolved = resolveSeconvInBundleResources(relativePath: "Tools/seconv") {
            return bundleResolved
        }
        if let envPath = ProcessInfo.processInfo.environment["TVEPISODEFINDER_SECONV"] {
            let resolved = resolveSeconvBinary(from: envPath)
            if let resolved { return resolved }
        }
        let envRoots = [
            ProcessInfo.processInfo.environment["SRCROOT"],
            ProcessInfo.processInfo.environment["PROJECT_DIR"]
        ].compactMap { $0 }
        for root in envRoots {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent("tools/seconv").path
            if let resolved = resolveSeconvBinary(from: candidate) {
                return resolved
            }
        }
        let cwdCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tools/seconv").path
        if let resolved = resolveSeconvBinary(from: cwdCandidate) {
            return resolved
        }
        let candidates = [
            "/opt/homebrew/bin/seconv",
            "/usr/local/bin/seconv",
            "/usr/bin/seconv"
        ]
        for path in candidates {
            if let resolved = resolveSeconvBinary(from: path) {
                return resolved
            }
        }
        if let bundleResolved = resolveSeconvInBundleResources(relativePath: "Tools/seconv") {
            return bundleResolved
        }
        if let bundleResolved = resolveSeconvRelativeToBundle(relativePath: "tools/seconv") {
            return bundleResolved
        }
        return nil
    }

    private static func resolveSeconvBinary(from path: String) -> String? {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            if isDir.boolValue {
                let candidate = URL(fileURLWithPath: path).appendingPathComponent("seconv").path
                return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
            } else {
                return FileManager.default.isExecutableFile(atPath: path) ? path : nil
            }
        }
        return nil
    }

    private static func resolveSeconvRelativeToBundle(relativePath: String) -> String? {
        let bundleURL = Bundle.main.bundleURL
        var current = bundleURL
        for _ in 0..<6 {
            let candidate = current.appendingPathComponent(relativePath).path
            if let resolved = resolveSeconvBinary(from: candidate) {
                return resolved
            }
            current.deleteLastPathComponent()
        }
        return nil
    }

    private static func resolveSeconvInBundleResources(relativePath: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent(relativePath).path
        return resolveSeconvBinary(from: candidate)
    }

    private static func resolveBundledToolBinary(toolDirName: String, binaryName: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL
            .appendingPathComponent("Tools")
            .appendingPathComponent(toolDirName)
            .appendingPathComponent(binaryName)
            .path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private static func applyBundledLibraryPathIfNeeded(to process: Process, toolDirName: String) {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let libDir = resourceURL
            .appendingPathComponent("Tools")
            .appendingPathComponent(toolDirName)
            .appendingPathComponent("lib")
        let libPath = libDir.path
        guard FileManager.default.fileExists(atPath: libPath) else { return }

        var env = ProcessInfo.processInfo.environment
        let existing = env["DYLD_LIBRARY_PATH"] ?? ""
        env["DYLD_LIBRARY_PATH"] = existing.isEmpty ? libPath : "\(libPath):\(existing)"
        let fallback = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
        env["DYLD_FALLBACK_LIBRARY_PATH"] = fallback.isEmpty ? libPath : "\(libPath):\(fallback)"
        process.environment = env
    }

    private static func extractPgsWithOcr(fileURL: URL, streamIndex: Int, ffmpegPath: String, seconvPath: String) -> SubtitleExtractionResult {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "Temp dir failed: \(error.localizedDescription)", codec: "hdmv_pgs_subtitle")
        }
        let supURL = tempDir.appendingPathComponent("subtitle.sup")

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: ffmpegPath)
        applyBundledLibraryPathIfNeeded(to: extract, toolDirName: "ffmpeg")
        extract.arguments = [
            "-y",
            "-i", fileURL.path,
            "-map", "0:\(streamIndex)",
            "-c:s", "copy",
            supURL.path
        ]
        extract.standardOutput = Pipe()
        extract.standardError = Pipe()
        do {
            try extract.run()
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg (PGS) launch failed: \(error.localizedDescription)", codec: "hdmv_pgs_subtitle")
        }
        extract.waitUntilExit()
        guard extract.terminationStatus == 0 else {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg (PGS) exit \(extract.terminationStatus)", codec: "hdmv_pgs_subtitle")
        }

        let seconv = Process()
        seconv.executableURL = URL(fileURLWithPath: seconvPath)
        seconv.currentDirectoryURL = tempDir
        seconv.arguments = [
            supURL.lastPathComponent,
            "srt"
        ]
        seconv.standardOutput = Pipe()
        seconv.standardError = Pipe()
        do {
            try seconv.run()
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "SubtitleEdit launch failed: \(error.localizedDescription)", codec: "hdmv_pgs_subtitle")
        }
        seconv.waitUntilExit()
        guard seconv.terminationStatus == 0 else {
            return SubtitleExtractionResult(sample: nil, error: "SubtitleEdit exit \(seconv.terminationStatus)", codec: "hdmv_pgs_subtitle")
        }

        let srtFiles = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension.lowercased() == "srt" } ?? []
        guard let srtURL = srtFiles.first, let data = try? Data(contentsOf: srtURL) else {
            return SubtitleExtractionResult(sample: nil, error: "SubtitleEdit produced no SRT", codec: "hdmv_pgs_subtitle")
        }
        let sample = SubtitleMatcher.fullText(from: data)
        if sample == nil {
            return SubtitleExtractionResult(sample: nil, error: "OCR subtitle decode failed", codec: "hdmv_pgs_subtitle")
        }
        return SubtitleExtractionResult(sample: sample, error: nil, codec: "hdmv_pgs_subtitle")
    }
}

struct SubtitleExtractionResult {
    let sample: String?
    let error: String?
    let codec: String?
}

struct SubtitleStreamInfo {
    let index: Int
    let codec: String?
}
