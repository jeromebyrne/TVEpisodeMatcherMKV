import Foundation

enum DurationInfoService {
    static func durationInfo(for url: URL) async -> DurationInfo {
        return ffprobeDuration(for: url)
    }

    private static func ffprobeDuration(for url: URL) -> DurationInfo {
        let candidates = resolveFFprobeCandidates()
        if candidates.isEmpty {
            return DurationInfo(duration: nil, source: "ffprobe", error: "ffprobe not found in common paths")
        }

        var lastError: String? = nil
        for candidate in candidates {
            let result = runFFprobe(at: candidate.path, url: url, applyBundledLibPath: candidate.isBundled)
            if let duration = result.duration {
                return DurationInfo(duration: duration, source: "ffprobe", error: nil)
            }
            if let error = result.error {
                lastError = error
            }
        }

        return DurationInfo(duration: nil, source: "ffprobe", error: lastError ?? "ffprobe failed")
    }

    private struct FFprobeCandidate {
        let path: String
        let isBundled: Bool
    }

    private static func resolveFFprobeCandidates() -> [FFprobeCandidate] {
        var results: [FFprobeCandidate] = []
        if let bundled = resolveBundledToolBinary(toolDirName: "ffmpeg", binaryName: "ffprobe") {
            results.append(FFprobeCandidate(path: bundled, isBundled: true))
        }
        let systemCandidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in systemCandidates where FileManager.default.isExecutableFile(atPath: path) {
            results.append(FFprobeCandidate(path: path, isBundled: false))
        }
        return results
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

    private static func runFFprobe(at path: String, url: URL, applyBundledLibPath: Bool) -> DurationInfo {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        if applyBundledLibPath {
            applyBundledLibraryPathIfNeeded(to: process, toolDirName: "ffmpeg")
        }
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
}

struct DurationInfo {
    let duration: Double?
    let source: String
    let error: String?
}
