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
            if isImageSubtitleCodec(codec) {
                guard let seconvPath = resolveSubtitleEditPath(preferred: subtitleEditPath) else {
                    let details = "no seconv at preferred='\(subtitleEditPath ?? "")' cwd='\(FileManager.default.currentDirectoryPath)'"
                    return SubtitleExtractionResult(sample: nil, error: "\(ocrDisplayName(for: codec)) subtitles require OCR (SubtitleEdit CLI not found: \(details)). Run tools/install_deps.sh", codec: codec)
                }
                NSLog("SubtitleEdit CLI resolved path: %@", seconvPath)
                if codec == "hdmv_pgs_subtitle" {
                    return extractPgsWithOcr(
                        fileURL: url,
                        streamIndex: streamInfo.index,
                        ffmpegPath: ffmpegPath,
                        seconvPath: seconvPath
                    )
                }
                if codec == "dvd_subtitle" {
                    guard let ffprobePath = resolveFFprobePath() else {
                        return SubtitleExtractionResult(sample: nil, error: "ffprobe not found (run tools/install_deps.sh)", codec: codec)
                    }
                    guard let tesseractPath = resolveTesseractPath() else {
                        return SubtitleExtractionResult(sample: nil, error: "DVD subtitles require tesseract (install via Homebrew)", codec: codec)
                    }
                    return extractDvdSubWithOcr(
                        fileURL: url,
                        streamIndex: streamInfo.index,
                        ffmpegPath: ffmpegPath,
                        ffprobePath: ffprobePath,
                        tesseractPath: tesseractPath
                    )
                }
                return extractImageSubtitleTrackWithOcr(
                    fileURL: url,
                    streamIndex: streamInfo.index,
                    codec: codec,
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

    private static func isImageSubtitleCodec(_ codec: String) -> Bool {
        let supported = ["hdmv_pgs_subtitle", "dvd_subtitle"]
        return supported.contains(codec)
    }

    private static func ocrDisplayName(for codec: String) -> String {
        switch codec {
        case "hdmv_pgs_subtitle":
            return "PGS"
        case "dvd_subtitle":
            return "DVD"
        default:
            return codec
        }
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

    private static func resolveTesseractPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tesseract",
            "/usr/local/bin/tesseract",
            "/usr/bin/tesseract"
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

    private static func extractImageSubtitleTrackWithOcr(
        fileURL: URL,
        streamIndex: Int,
        codec: String,
        ffmpegPath: String,
        seconvPath: String
    ) -> SubtitleExtractionResult {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "Temp dir failed: \(error.localizedDescription)", codec: codec)
        }

        let isolatedTrackURL = tempDir.appendingPathComponent("subtitle-track.mkv")
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: ffmpegPath)
        applyBundledLibraryPathIfNeeded(to: extract, toolDirName: "ffmpeg")
        extract.arguments = [
            "-y",
            "-i", fileURL.path,
            "-map", "0:\(streamIndex)",
            "-c", "copy",
            isolatedTrackURL.path
        ]
        extract.standardOutput = Pipe()
        extract.standardError = Pipe()

        do {
            try extract.run()
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg (\(codec)) launch failed: \(error.localizedDescription)", codec: codec)
        }
        extract.waitUntilExit()
        guard extract.terminationStatus == 0 else {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg (\(codec)) exit \(extract.terminationStatus)", codec: codec)
        }

        let seconv = Process()
        seconv.executableURL = URL(fileURLWithPath: seconvPath)
        seconv.currentDirectoryURL = tempDir
        seconv.arguments = [
            isolatedTrackURL.lastPathComponent,
            "srt",
            "/overwrite"
        ]
        seconv.standardOutput = Pipe()
        seconv.standardError = Pipe()

        do {
            try seconv.run()
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "SubtitleEdit launch failed: \(error.localizedDescription)", codec: codec)
        }
        seconv.waitUntilExit()
        guard seconv.terminationStatus == 0 else {
            return SubtitleExtractionResult(sample: nil, error: "SubtitleEdit exit \(seconv.terminationStatus)", codec: codec)
        }

        let srtFiles = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil))?.filter { $0.pathExtension.lowercased() == "srt" } ?? []
        guard let srtURL = srtFiles.first, let data = try? Data(contentsOf: srtURL) else {
            return SubtitleExtractionResult(sample: nil, error: "SubtitleEdit produced no SRT", codec: codec)
        }

        let sample = SubtitleMatcher.fullText(from: data)
        if sample == nil {
            return SubtitleExtractionResult(sample: nil, error: "OCR subtitle decode failed", codec: codec)
        }
        return SubtitleExtractionResult(sample: sample, error: nil, codec: codec)
    }

    private static func extractDvdSubWithOcr(
        fileURL: URL,
        streamIndex: Int,
        ffmpegPath: String,
        ffprobePath: String,
        tesseractPath: String
    ) -> SubtitleExtractionResult {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "Temp dir failed: \(error.localizedDescription)", codec: "dvd_subtitle")
        }

        guard let duration = subtitleOverlayDuration(fileURL: fileURL, ffprobePath: ffprobePath) else {
            return SubtitleExtractionResult(sample: nil, error: "ffprobe duration failed", codec: "dvd_subtitle")
        }

        let framePattern = tempDir.appendingPathComponent("frame-%06d.png")
        let render = Process()
        render.executableURL = URL(fileURLWithPath: ffmpegPath)
        applyBundledLibraryPathIfNeeded(to: render, toolDirName: "ffmpeg")
        render.arguments = [
            "-y",
            "-f", "lavfi",
            "-i", "color=size=720x480:duration=\(String(format: "%.3f", duration)):rate=10:color=black",
            "-i", fileURL.path,
            "-filter_complex",
            "[0:v][1:\(streamIndex)]overlay,mpdecimate,crop=500:120:180:330,scale=2000:-1,format=gray,lut=y='if(gt(val,80),255,0)'",
            "-fps_mode", "vfr",
            framePattern.path
        ]
        render.standardOutput = Pipe()
        render.standardError = Pipe()

        do {
            try render.run()
        } catch {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg (dvd_subtitle) launch failed: \(error.localizedDescription)", codec: "dvd_subtitle")
        }
        render.waitUntilExit()
        guard render.terminationStatus == 0 else {
            return SubtitleExtractionResult(sample: nil, error: "ffmpeg (dvd_subtitle) exit \(render.terminationStatus)", codec: "dvd_subtitle")
        }

        let frameURLs = ((try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !frameURLs.isEmpty else {
            return SubtitleExtractionResult(sample: nil, error: "No DVD subtitle frames rendered", codec: "dvd_subtitle")
        }

        var collected: [String] = []
        var previous = ""
        for frameURL in frameURLs.prefix(350) {
            guard let text = ocrText(from: frameURL, tesseractPath: tesseractPath) else { continue }
            let cleaned = cleanOcrText(text)
            guard isUsableOcrText(cleaned) else { continue }
            if cleaned == previous {
                continue
            }
            previous = cleaned
            collected.append(cleaned)
            if combinedTokenCount(collected) >= 220 {
                break
            }
        }

        guard !collected.isEmpty else {
            return SubtitleExtractionResult(sample: nil, error: "DVD OCR produced no usable text", codec: "dvd_subtitle")
        }
        let joined = collected.joined(separator: "\n")
        guard let sample = SubtitleMatcher.fullText(from: Data(joined.utf8)), !sample.isEmpty else {
            return SubtitleExtractionResult(sample: nil, error: "DVD OCR text normalization failed", codec: "dvd_subtitle")
        }
        return SubtitleExtractionResult(sample: sample, error: nil, codec: "dvd_subtitle")
    }

    private static func subtitleOverlayDuration(fileURL: URL, ffprobePath: String) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        applyBundledLibraryPathIfNeeded(to: process, toolDirName: "ffmpeg")
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            fileURL.path
        ]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, let duration = Double(output), duration > 0 else {
            return nil
        }
        return duration
    }

    private static func ocrText(from imageURL: URL, tesseractPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tesseractPath)
        process.arguments = [
            imageURL.path,
            "stdout",
            "--psm", "6"
        ]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func cleanOcrText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "I")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsableOcrText(_ text: String) -> Bool {
        guard text.count >= 10 else { return false }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let spaces = text.unicodeScalars.filter { CharacterSet.whitespaces.contains($0) }.count
        guard letters >= 8, spaces >= 1 else { return false }
        return Double(letters) / Double(max(text.count, 1)) >= 0.55
    }

    private static func combinedTokenCount(_ lines: [String]) -> Int {
        lines.joined(separator: " ")
            .split(separator: " ")
            .count
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
