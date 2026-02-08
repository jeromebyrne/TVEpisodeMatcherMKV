import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TVEpisodeMatcherMKVViewModel()
    @State private var showRenameConfirm = false
    @State private var showSearchTask: Task<Void, Never>?
    @State private var hoveredShowSuggestion: TMDBShow?
    @FocusState private var showFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 16) {
                GroupBox("Authentication") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            SecureField("TMDB Access Token", text: $viewModel.tmdbAccessToken)
                                .textFieldStyle(.roundedBorder)
                            Button("Open TMDB API Settings") {
                                viewModel.openTMDBSettings()
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            SecureField("OpenSubtitles API Key", text: $viewModel.openSubtitlesApiKey)
                                .textFieldStyle(.roundedBorder)
                            Button("Open OpenSubtitles API") {
                                viewModel.openOpenSubtitlesSettings()
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                        HStack(spacing: 12) {
                            TextField("OpenSubtitles Username", text: $viewModel.openSubtitlesUsername)
                                .textFieldStyle(.roundedBorder)
                            SecureField("OpenSubtitles Password", text: $viewModel.openSubtitlesPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Episode Matching") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button("Select Folder") {
                                viewModel.selectFolder()
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            Text(viewModel.selectedFolder)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        HStack(spacing: 12) {
                            Text("Show")
                            TextField("Enter show name", text: $viewModel.showName)
                                .textFieldStyle(.roundedBorder)
                                .focused($showFieldFocused)
                                .anchorPreference(key: ShowFieldAnchorKey.self, value: .bounds) { $0 }
                                .onChange(of: viewModel.showName) { newValue in
                                    showSearchTask?.cancel()
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard trimmed.count >= 3 else {
                                        viewModel.clearShowSuggestions()
                                        return
                                    }
                                    showSearchTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        guard !Task.isCancelled else { return }
                                        await viewModel.fetchShowSuggestions(query: trimmed, limit: 8)
                                    }
                                }
                            Text("Season")
                            TextField("2", text: $viewModel.seasonInput)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }

                    HStack(spacing: 12) {
                        Text("Episode Range")
                        TextField("13-24", text: $viewModel.episodeRangeInput)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                        Button("Match") {
                            Task { await viewModel.autoAssignBySubtitles() }
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!viewModel.canMatchBySubtitles)
                        Spacer()
                    }

                        Spacer(minLength: 4)

                        HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Files")
                                .font(.headline)
                            List(selection: $viewModel.selectedFile) {
                                    if viewModel.files.isEmpty {
                                        Text("No files loaded")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(viewModel.files) { file in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(file.name)
                                                if let match = viewModel.matchForFile(file) {
                                                    if let best = match.bestCandidate {
                                                        HStack(spacing: 6) {
                                                            Text("Matched: S\(best.episode.seasonNumber.twoDigit)E\(best.episode.episodeNumber.twoDigit) • \(best.episode.name)")
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                            Text(best.confidenceLabel)
                                                                .font(.caption2)
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(confidenceColor(for: best.confidenceLabel))
                                                                .foregroundStyle(.white)
                                                                .clipShape(Capsule())
                                                        }
                                                    } else {
                                                        Text("No match")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            HStack {
                                Button("Rename") {
                                    showRenameConfirm = true
                                }
                                .buttonStyle(PrimaryActionButtonStyle())
                                .disabled(!viewModel.canRename)
                                Spacer()
                            }
                        }

                        if !viewModel.statusMessage.isEmpty {
                            Text(viewModel.statusMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                        }
                        if viewModel.lastRangeCount > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.allRangeMatched ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(viewModel.allRangeMatched ? Color.green : Color.orange)
                                Text("Range matched: \(viewModel.lastMatchedCount)/\(viewModel.lastRangeCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !viewModel.lastMissingEpisodes.isEmpty {
                                Text("Missing episodes from TMDB: \(viewModel.lastMissingEpisodes.map(String.init).joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text("Console")
                                    .font(.headline)
                                Spacer()
                                Button("Clear") {
                                    viewModel.clearLogs()
                                }
                                .buttonStyle(PrimaryActionButtonStyle())
                            }
                            List {
                                if viewModel.logs.isEmpty {
                                    Text("No logs yet")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(viewModel.logs) { entry in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(entry.timestamp, style: .time)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("[\(entry.level.rawValue)]")
                                                .font(.caption)
                                                .foregroundStyle(colorForLevel(entry.level))
                                            Text(entry.message)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 140)
                        }
                    }
                    .padding(8)
                }
            }
            .disabled(viewModel.isMatching)
        }
        .overlayPreferenceValue(ShowFieldAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, showFieldFocused && !viewModel.showSuggestions.isEmpty {
                    let frame = proxy[anchor]
                    VStack(spacing: 0) {
                        ForEach(viewModel.showSuggestions, id: \.self) { show in
                            Button {
                                viewModel.selectShowSuggestion(show)
                                showFieldFocused = false
                            } label: {
                                HStack(spacing: 6) {
                                    Text(show.name)
                                        .foregroundStyle(.primary)
                                    if let original = show.originalName, original != show.name {
                                        Text("(\(original))")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(hoveredShowSuggestion == show ? Color.accentColor.opacity(0.15) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredShowSuggestion = hovering ? show : nil
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 4)
                    .frame(width: max(240, frame.width), alignment: .leading)
                    .offset(x: frame.minX, y: frame.maxY + 4)
                    .zIndex(20)
                }
            }
        }
        .overlay {
            if viewModel.isMatching {
                ZStack {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Processing...")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(Color(NSColor.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: showFieldFocused) { focused in
            if !focused {
                viewModel.clearShowSuggestions()
            }
        }
        .onTapGesture {
            showFieldFocused = false
            viewModel.clearShowSuggestions()
        }
        .confirmationDialog("Rename all matched files?", isPresented: $showRenameConfirm) {
            Button("Rename") {
                viewModel.renameMatchedFiles()
            }
        }
    }

    private func confidenceColor(for label: String) -> Color {
        switch label {
        case "High":
            return .green
        case "Medium":
            return .orange
        case "Low":
            return .red
        default:
            return .gray
        }
    }

    private func statusRow(_ label: String, _ ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isEnabled ? Color.accentColor : Color.gray)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ShowFieldAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

#Preview {
    ContentView()
}
