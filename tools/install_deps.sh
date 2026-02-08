#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This installer is macOS-only." >&2
  exit 1
fi

arch="$(uname -m)"
if [[ "$arch" != "arm64" ]]; then
  echo "This installer targets Apple Silicon (arm64)." >&2
  exit 1
fi

ensure_brew_writable() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install from https://brew.sh/" >&2
    exit 1
  fi
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  if [[ -n "$brew_prefix" && ! -w "$brew_prefix" ]]; then
    echo "Homebrew prefix is not writable: $brew_prefix" >&2
    echo "Run 'brew doctor' and fix ownership/permissions before running this script." >&2
    exit 1
  fi
  brew_cache="$(brew --cache 2>/dev/null || true)"
  if [[ -n "$brew_cache" && ! -w "$brew_cache" ]]; then
    echo "Homebrew cache is not writable: $brew_cache" >&2
    echo "Run 'brew doctor' and fix ownership/permissions before running this script." >&2
    exit 1
  fi
  brew_logs="$(brew --cache)/../Logs/Homebrew"
  if [[ -d "$brew_logs" && ! -w "$brew_logs" ]]; then
    echo "Homebrew logs dir is not writable: $brew_logs" >&2
    echo "Run 'brew doctor' and fix ownership/permissions before running this script." >&2
    exit 1
  fi
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ffmpeg_dir="$repo_root/tools/ffmpeg"
ffmpeg_lib_dir="$ffmpeg_dir/lib"
seconv_dir="$repo_root/tools/seconv"

mkdir -p "$ffmpeg_lib_dir" "$seconv_dir"
chmod -R u+w "$ffmpeg_dir" "$ffmpeg_lib_dir" "$seconv_dir" 2>/dev/null || true

ffmpeg_bin="$(command -v ffmpeg || true)"
ffprobe_bin="$(command -v ffprobe || true)"

if [[ -z "$ffmpeg_bin" || -z "$ffprobe_bin" ]]; then
  ensure_brew_writable
  brew install ffmpeg
  ffmpeg_bin="$(command -v ffmpeg || true)"
  ffprobe_bin="$(command -v ffprobe || true)"
fi

ffmpeg_prefix="$(brew --prefix ffmpeg 2>/dev/null || true)"

if [[ -n "$ffmpeg_prefix" ]]; then
  if [[ -z "$ffmpeg_bin" && -x "$ffmpeg_prefix/bin/ffmpeg" ]]; then
    ffmpeg_bin="$ffmpeg_prefix/bin/ffmpeg"
  fi
  if [[ -z "$ffprobe_bin" && -x "$ffmpeg_prefix/bin/ffprobe" ]]; then
    ffprobe_bin="$ffmpeg_prefix/bin/ffprobe"
  fi
fi

if [[ -z "$ffmpeg_bin" || -z "$ffprobe_bin" ]]; then
  echo "ffmpeg/ffprobe not found after brew install." >&2
  exit 1
fi

rm -f "$ffmpeg_dir/ffmpeg" "$ffmpeg_dir/ffprobe"
cp "$ffmpeg_bin" "$ffmpeg_dir/ffmpeg"
cp "$ffprobe_bin" "$ffmpeg_dir/ffprobe"
chmod +x "$ffmpeg_dir/ffmpeg" "$ffmpeg_dir/ffprobe"

copy_lib() {
  local src="$1"
  local base
  base="$(basename "$src")"
  if [[ -f "$ffmpeg_lib_dir/$base" ]]; then
    return 0
  fi
  cp "$src" "$ffmpeg_lib_dir/$base"
}

queue=()

collect_deps() {
  local bin="$1"
  while IFS= read -r line; do
    local path
    path="$(echo "$line" | awk '{print $1}')"
    if [[ "$path" == /opt/homebrew/* || "$path" == /usr/local/* ]]; then
      queue+=("$path")
    fi
  done < <(otool -L "$bin" | tail -n +2)
}

collect_deps "$ffmpeg_dir/ffmpeg"
collect_deps "$ffmpeg_dir/ffprobe"

seen=()
while [[ ${#queue[@]} -gt 0 ]]; do
  item="${queue[0]}"
  queue=("${queue[@]:1}")

  skip=false
  for s in "${seen[@]}"; do
    if [[ "$s" == "$item" ]]; then
      skip=true
      break
    fi
  done
  if $skip; then
    continue
  fi
  seen+=("$item")

  if [[ -f "$item" ]]; then
    copy_lib "$item"
    collect_deps "$item"
  fi
done

seconv_repo="${SECONV_REPO:-https://github.com/SubtitleEdit/subtitleedit-cli.git}"
seconv_ref="${SECONV_REF:-}"

# Install seconv: prefer explicit zip/dir, otherwise build from source.
# Provide one of:
#   SECONV_ZIP=/path/to/seconv.zip
#   SECONV_DIR=/path/to/seconv_dir
#   SECONV_REPO=https://github.com/SubtitleEdit/subtitleedit-cli.git (optional)
#   SECONV_REF=<git ref> (optional)
if [[ -n "${SECONV_ZIP:-}" ]]; then
  if [[ ! -f "$SECONV_ZIP" ]]; then
    echo "SECONV_ZIP not found: $SECONV_ZIP" >&2
    exit 1
  fi
  rm -rf "$seconv_dir"/*
  unzip -q "$SECONV_ZIP" -d "$seconv_dir"
elif [[ -n "${SECONV_DIR:-}" ]]; then
  if [[ ! -d "$SECONV_DIR" ]]; then
    echo "SECONV_DIR not found: $SECONV_DIR" >&2
    exit 1
  fi
  rm -rf "$seconv_dir"/*
  cp -R "$SECONV_DIR"/. "$seconv_dir"
else
  if ! command -v dotnet >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    ensure_brew_writable
    brew install dotnet git
  fi

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  echo "Building seconv from source..."
  git clone --depth 1 "$seconv_repo" "$tmp_dir/seconv"
  if [[ -n "$seconv_ref" ]]; then
    git -C "$tmp_dir/seconv" fetch --depth 1 origin "$seconv_ref"
    git -C "$tmp_dir/seconv" checkout "$seconv_ref"
  fi

  csproj=""
  if [[ -f "$tmp_dir/seconv/src/se-cli/seconv.csproj" ]]; then
    csproj="$tmp_dir/seconv/src/se-cli/seconv.csproj"
  else
    csproj="$(find "$tmp_dir/seconv" -name "*.csproj" | head -n 1)"
  fi
  if [[ -z "$csproj" ]]; then
    echo "Unable to locate seconv csproj in $seconv_repo" >&2
    exit 1
  fi

  rm -rf "$seconv_dir"/*
  dotnet publish "$csproj" -c Release -r osx-arm64 --self-contained true -p:PublishSingleFile=true -o "$seconv_dir"

  if [[ -f "$seconv_dir/seconv" ]]; then
    :
  elif [[ -f "$seconv_dir/SubtitleEdit.CLI" ]]; then
    mv "$seconv_dir/SubtitleEdit.CLI" "$seconv_dir/seconv"
  elif [[ -f "$seconv_dir/subtitleedit-cli" ]]; then
    mv "$seconv_dir/subtitleedit-cli" "$seconv_dir/seconv"
  fi

  if [[ -f "$seconv_dir/seconv" ]]; then
    chmod +x "$seconv_dir/seconv"
  else
    echo "seconv binary not found after build; check output in $seconv_dir" >&2
    exit 1
  fi
fi

echo "Done. Tools installed under tools/"
