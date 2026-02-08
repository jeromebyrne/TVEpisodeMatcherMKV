# TVEpisodeMatcherMKV

A macOS app that helps you correctly tag MKV TV episodes by matching them
against online metadata and subtitles, including OCR (optical character
recognition—converting subtitle images into text) for PGS subtitles when
needed. The primary use case is when you rip a TV season from Blu-ray and
the episode files are obfuscated or out of order. You provide the show
name and season number, and the app matches each file against TMDB and
OpenSubtitles to determine the correct episode numbers and names.

MKV (Matroska) is a common container format for video files that can
include multiple audio and subtitle tracks. The app scans MKV files,
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

The app relies on external command line tools for some operations. The installer script (`tools/install_deps.sh`) is the
source of truth for setting up these dependencies. It fetches tools via Homebrew and stages them under `tools/` (macOS
arm64 only). The `tools/` directory is gitignored and populated locally.

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

## Caching Details

The app caches data to reduce repeated network calls and speed up matching:

- TMDB show search results are cached in-memory during a session to avoid repeated lookups while typing.
- OpenSubtitles downloads are cached on disk per show/season/episode/file so repeated matches don’t re-download the same subtitle.
- User-entered credentials and last-used inputs (show name, season, range, folder) are stored locally in `UserDefaults`.

If you want a clean slate, clear the app’s `UserDefaults` and delete the cached subtitle files from the app’s cache folder.

## Setup

1. Run `tools/install_deps.sh` to populate `tools/`.
2. Open `TVEpisodeMatcherMKV.xcodeproj` in Xcode.
3. Build and run the `TVEpisodeMatcherMKV` target.
4. Configure API credentials in the app UI (free accounts required):
   - TMDB Access Token (create a free TMDB account to obtain an API token). Sign up: `https://www.themoviedb.org/signup`
   - OpenSubtitles API Key, Username, Password (create a free OpenSubtitles account). Sign up: `https://www.opensubtitles.com/en/signup`

## seconv (SubtitleEdit CLI)

`seconv` is used to OCR PGS subtitles. If `tools/seconv/seconv` exists at build time, the app bundles it into the app resources automatically.
`tools/seconv/` is populated by `tools/install_deps.sh` (it is not committed to git).

The app will look for `seconv` in this order:

- A bundled copy at `Contents/Resources/Tools/seconv`
- `tools/seconv` relative to the current working directory
- Standard paths: `/opt/homebrew/bin/seconv`, `/usr/local/bin/seconv`, `/usr/bin/seconv`
- A `tools/seconv` folder located near the app bundle

## Notes

Credentials are stored locally via `UserDefaults` (not committed to git).
