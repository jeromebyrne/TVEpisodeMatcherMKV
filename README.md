# TVEpisodeMatcherMKV

A macOS app that helps you correctly tag MKV TV episodes by matching them
against online metadata and subtitles, including OCR (optical character
recognition—converting subtitle images into text) for PGS subtitles when
needed. MKV (Matroska) is a common container format for video files that
can include multiple audio and subtitle tracks. The app scans MKV files,
parses filenames for hints, fetches season/episode metadata from TMDB,
and then uses a combination of subtitle text similarity and
timing/duration checks (via `ffprobe`) to map each file to the most likely
episode. For embedded PGS subtitles (image-based subtitles), it invokes
SubtitleEdit CLI (`seconv`) to OCR them into text before scoring. If
embedded subtitles are missing or insufficient, it can compare against
downloaded subtitle samples from OpenSubtitles.

## Glossary

- MKV (Matroska): A multimedia container format that can hold video, audio, and multiple subtitle tracks.
- PGS (Presentation Graphic Stream): Image-based subtitles often found on Blu-ray sources.
- OCR (Optical Character Recognition): Converts subtitle images into selectable text.
- TMDB: The Movie Database API used for show and episode metadata.
- OpenSubtitles: Subtitle database used for downloading reference subtitle samples.

## Requirements

The app relies on external command line tools for some operations. Use the installer script to fetch tools via Homebrew
and stage them under `tools/` (macOS arm64 only). The `tools/` directory is gitignored and populated locally.

Tools:
- `ffmpeg` (includes `ffprobe`)
- `seconv` (SubtitleEdit CLI, used for OCR of PGS subtitles)

### Install tools (recommended)

Run:

```bash
tools/install_deps.sh
```

This installs `ffmpeg` via Homebrew and copies `ffmpeg/ffprobe` plus required `.dylib` files into `tools/ffmpeg/`.
For `seconv` (SubtitleEdit CLI), the script builds from source using `dotnet` (installed via Homebrew) unless you provide:
- `SECONV_ZIP=/path/to/seconv.zip`
- `SECONV_DIR=/path/to/seconv_dir`
You can also override the source repo/ref:
- `SECONV_REPO=https://github.com/SubtitleEdit/subtitleedit-cli.git`
- `SECONV_REF=<git ref>`

When present at build time, the app bundles the tools into `Contents/Resources/Tools/` and prefers the bundled copies at runtime.
If a bundled `ffprobe` fails to launch, the app will fall back to a system `ffprobe` if available.
If dependencies are missing at runtime, error messages will suggest running `tools/install_deps.sh`.

### Troubleshooting

- Homebrew permissions errors: run `brew doctor` and fix ownership/permissions for your Homebrew prefix and cache.
- `seconv` build warnings: the SubtitleEdit CLI build may emit .NET nullability warnings; these are expected.
- PGS OCR not working: confirm `tools/seconv/seconv` exists, then clean/rebuild so it is bundled into the app.

## Setup

1. Run `tools/install_deps.sh` to populate `tools/`.
2. Open `TVEpisodeMatcherMKV.xcodeproj` in Xcode.
3. Build and run the `TVEpisodeMatcherMKV` target.
4. Configure API credentials in the app UI (free accounts required):
   - TMDB Access Token (create a free TMDB account to obtain an API token)
   - OpenSubtitles API Key, Username, Password (create a free OpenSubtitles account)

## seconv (SubtitleEdit CLI)

`seconv` is used to OCR PGS subtitles. If `tools/seconv/seconv` exists at build time, the app bundles it into the app resources automatically.
`tools/seconv/` is populated by `tools/install_deps.sh` (it is not committed to git).

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
