# TVEpisodeMatcherMKV

A macOS app that helps you correctly tag MKV TV episodes by matching them
against online metadata and subtitles, including OCR support for PGS
subtitles when needed.

## Requirements

The app relies on external command line tools for some operations. Install these before running:

- `ffmpeg`
- `mediainfo`
- `seconv` (SubtitleEdit CLI, used for OCR of PGS subtitles)

### Install with Homebrew

```bash
brew install ffmpeg mediainfo
```

### Install with Brewfile

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

`seconv` is used to OCR PGS subtitles. The `tools/seconv/` folder is **ignored by git** so each user must provide it locally.

The app will look for `seconv` in this order:

- A path provided in the app (SubtitleEdit CLI path)
- `TVEPISODEFINDER_SECONV` environment variable
- `tools/seconv` relative to the current working directory
- Standard paths: `/opt/homebrew/bin/seconv`, `/usr/local/bin/seconv`, `/usr/bin/seconv`
- A `tools/seconv` folder located near the app bundle

You can point the app at `seconv` by entering either an absolute path or a relative path (e.g. `tools/seconv`).

## Notes

Credentials are stored locally via `UserDefaults` (not committed to git).
