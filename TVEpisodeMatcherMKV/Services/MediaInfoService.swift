import Foundation

enum MediaInfoService {
    static func durationInfo(for url: URL) async -> DurationInfo {
        return ffprobeDuration(for: url)
    }

    private static func ffprobeDuration(for url: URL) -> DurationInfo {
        guard let ffprobePath = resolveFFprobePath() else {
            return DurationInfo(duration: nil, source: "ffprobe", error: "ffprobe not found in common paths")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return DurationInfo(duration: nil, source: "ffprobe", error: "launch failed: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown error"
            return DurationInfo(duration: nil, source: "ffprobe", error: "exit \(process.terminationStatus): \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Double(trimmed)
        return DurationInfo(duration: duration, source: "ffprobe", error: duration == nil ? "invalid output: \(trimmed)" : nil)
    }

    private static func resolveFFprobePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}

struct DurationInfo {
    let duration: Double?
    let source: String
    let error: String?
}
