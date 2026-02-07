# TVEpisodeMatcherMKV

A macOS app for matching MKV TV episodes to metadata and subtitles.

## Requirements

The app relies on external command line tools for some operations. You can either bundle them with the app (preferred for zero-setup users) or install them locally.

Tools:
- `ffmpeg` (includes `ffprobe`)
- `seconv` (SubtitleEdit CLI, used for OCR of PGS subtitles)

### Bundle tools in the app (recommended)

Place the tools under these paths in the repo before building:
- `tools/ffmpeg/ffmpeg`
- `tools/ffmpeg/ffprobe`
- `tools/seconv/seconv`

If a tool has dependent `.dylib` files, place them under:
- `tools/ffmpeg/lib/`

When present at build time, the app bundles them into `Contents/Resources/Tools/` and prefers the bundled copies at runtime.

### Install with Homebrew (dev only)

```bash
brew install ffmpeg
```

### Install with Brewfile (dev only)

```bash
brew bundle
```

## Setup

1. Open `TVEpisodeMatcherMKV.xcodeproj` in Xcode.
2. Build and run the `TVEpisodeMatcherMKV` target.
3. Configure API credentials in the app UI:
   - TMDB Access Token
   - OpenSubtitles API Key, Username, Password

## seconv (SubtitleEdit CLI)

`seconv` is used to OCR PGS subtitles. If `tools/seconv/seconv` exists at build time, the app bundles it into the app resources automatically.

The app will look for `seconv` in this order:

- A path provided in the app (SubtitleEdit CLI path)
- A bundled copy at `Contents/Resources/Tools/seconv`
- `TVEPISODEFINDER_SECONV` environment variable
- `tools/seconv` relative to the current working directory
- Standard paths: `/opt/homebrew/bin/seconv`, `/usr/local/bin/seconv`, `/usr/bin/seconv`
- A `tools/seconv` folder located near the app bundle

You can point the app at `seconv` by entering either an absolute path or a relative path (e.g. `tools/seconv`).

## Notes

Credentials are stored locally via `UserDefaults` (not committed to git).
