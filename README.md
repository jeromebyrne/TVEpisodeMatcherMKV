# TVEpisodeMatcherMKV

A macOS app that helps you correctly tag MKV TV episodes by matching them
against online metadata and subtitles, including OCR support for PGS
subtitles when needed.

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

### Uninstall tools (dev only)

```bash
tools/uninstall_deps.sh
```

This removes repo-local tool installs under `tools/` and uninstalls Homebrew packages (`ffmpeg`, `dotnet`, `git`).

### Troubleshooting

- Homebrew permissions errors: run `brew doctor` and fix ownership/permissions for your Homebrew prefix and cache.
- `seconv` build warnings: the SubtitleEdit CLI build may emit .NET nullability warnings; these are expected.
- PGS OCR not working: confirm `tools/seconv/seconv` exists, then clean/rebuild so it is bundled into the app.

## Setup

1. Run `tools/install_deps.sh` to populate `tools/`.
2. Open `TVEpisodeMatcherMKV.xcodeproj` in Xcode.
3. Build and run the `TVEpisodeMatcherMKV` target.
4. Configure API credentials in the app UI:
   - TMDB Access Token
   - OpenSubtitles API Key, Username, Password

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
