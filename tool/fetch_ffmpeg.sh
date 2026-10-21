#!/usr/bin/env bash
# Downloads the FFmpeg that the app ships with into third_party/ffmpeg/<system>/,
# beside its licence and notice. The builds pick it up from there: the CMake
# install rules on Linux and Windows, tool/package_macos.sh on macOS. Without
# it a build has no FFmpeg inside and uses the one on the PATH.
#
#   tool/fetch_ffmpeg.sh linux|windows|macos
#
# Every system gets VidCtrl's own build of the same FFmpeg and libraries,
# made and checked by the vidctrl-ffmpeg repository, pinned here by checksum.
# assets/licenses/ffmpeg.txt says where it and its source come from; change
# the two together (this script checks that the notice names the release).
set -euo pipefail

system="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/third_party/ffmpeg/$system"
notice="$root/assets/licenses/ffmpeg.txt"

release=8.1.3-3
base="https://github.com/koorchik/vidctrl-ffmpeg/releases/download/$release/ffmpeg-$release"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sha256() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# fetch <url> <sha256> <file in $work>
fetch() {
  echo "Downloading $1"
  curl -fsSL --retry 3 -o "$work/$3" "$1"
  local actual
  actual="$(sha256 "$work/$3")"
  if [[ "$actual" != "$2" ]]; then
    echo "error: $1 has the checksum $actual, not $2" >&2
    exit 1
  fi
}

# unpack_zip <zip> <folder>
unpack_zip() {
  mkdir -p "$2"
  if command -v unzip > /dev/null; then
    unzip -q -o "$1" -d "$2"
  else
    7z x -y -bd -o"$2" "$1" > /dev/null
  fi
}

if ! grep -qF "release $release" "$notice"; then
  echo "error: $notice does not name release $release; update it with the pin" >&2
  exit 1
fi

case "$system" in
  linux)
    fetch "$base-linux-x64.zip" \
      9f2e383f6d5f9d14f3010282db693afd7128b2bbae257afa0a2984a6fc3d51f3 ffmpeg.zip
    files=(ffmpeg ffprobe)
    ;;
  windows)
    fetch "$base-windows-x64.zip" \
      ac2e5b29957e24a00bab933e78fe69d7375979ed8a0ea3b4525344c7667161f5 ffmpeg.zip
    files=(ffmpeg.exe ffprobe.exe)
    ;;
  macos)
    fetch "$base-macos.zip" \
      9a544dba3cad36c24de5a8f6d3d406a5256c545d22692ec10aaa23eca08ef642 ffmpeg.zip
    files=(ffmpeg ffprobe)
    ;;
  *)
    echo "usage: tool/fetch_ffmpeg.sh linux|windows|macos" >&2
    exit 2
    ;;
esac
unpack_zip "$work/ffmpeg.zip" "$work/bin"

rm -rf "$out"
mkdir -p "$out"
for file in "${files[@]}"; do cp "$work/bin/$file" "$out/"; done
chmod +x "$out"/ff*
cp "$notice" "$out/FFmpeg-NOTICE.txt"
cp "$root/assets/licenses/gpl-3.0.txt" "$out/FFmpeg-LICENSE.txt"
echo "FFmpeg for $system is in ${out#"$root"/}"
