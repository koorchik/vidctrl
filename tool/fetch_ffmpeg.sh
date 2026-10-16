#!/usr/bin/env bash
# Downloads the FFmpeg that the app ships with into third_party/ffmpeg/<system>/,
# beside its licence and notice. The builds pick it up from there: the CMake
# install rules on Linux and Windows, tool/package_macos.sh on macOS. Without
# it a build has no FFmpeg inside and uses the one on the PATH.
#
#   tool/fetch_ffmpeg.sh linux|windows|macos
#
# The builds are other people's, unmodified, and pinned by checksum here.
# assets/licenses/ffmpeg.txt says where each one and its source come from;
# change the two together (this script checks that the notice names the
# builds pinned here). macOS gets Martin Riedl's builds, made into one
# universal binary; Linux and Windows get BtbN's "gpl" builds. Martin Riedl's
# Linux builds are not used: they are configured with --enable-nonfree, which
# may not be passed on.
set -euo pipefail

system="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/third_party/ffmpeg/$system"
notice="$root/assets/licenses/ffmpeg.txt"

btbn_release=autobuild-2026-09-30-13-08
btbn_name=ffmpeg-n8.1.3-9-g29e619e767
btbn="https://github.com/BtbN/FFmpeg-Builds/releases/download/$btbn_release/$btbn_name"
riedl_arm64=1783011502_8.1.2
riedl_amd64=1783018342_8.1.2
riedl=https://ffmpeg.martin-riedl.de/download/macos

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

for pin in "$btbn_release" "$btbn_name" "$riedl_arm64" "$riedl_amd64"; do
  if ! grep -qF "${pin#ffmpeg-}" "$notice"; then
    echo "error: $notice does not name $pin; update it with the pins" >&2
    exit 1
  fi
done

case "$system" in
  linux)
    fetch "$btbn-linux64-gpl-8.1.tar.xz" \
      97ce978979194b5cf7e06a5e68020dbdaa7a4f3294c5452b6a1bc347100dbb79 ffmpeg.tar.xz
    tar -xJf "$work/ffmpeg.tar.xz" -C "$work"
    bin="$work/$btbn_name-linux64-gpl-8.1/bin"
    files=("$bin/ffmpeg" "$bin/ffprobe")
    ;;
  windows)
    fetch "$btbn-win64-gpl-8.1.zip" \
      7b801cdd3a1a0bb54ae6f572187e68b4ed54f52086cfee133fab2180bfb429fa ffmpeg.zip
    unpack_zip "$work/ffmpeg.zip" "$work"
    bin="$work/$btbn_name-win64-gpl-8.1/bin"
    files=("$bin/ffmpeg.exe" "$bin/ffprobe.exe")
    ;;
  macos)
    fetch "$riedl/arm64/$riedl_arm64/ffmpeg.zip" \
      ef1aa60006c7b77ce170c1608c08d8e4ba1c30c5746f2ac986ded932d0ac2c3c arm64-ffmpeg.zip
    fetch "$riedl/arm64/$riedl_arm64/ffprobe.zip" \
      c39787f4af7a3932502d2d48db6f6feaaa836b48a73ef78c32cc3285df61dfaf arm64-ffprobe.zip
    fetch "$riedl/amd64/$riedl_amd64/ffmpeg.zip" \
      a52ef43883f44c219766d4b3bdde4e635b35465d0b704c01c3a0566b59775df9 amd64-ffmpeg.zip
    fetch "$riedl/amd64/$riedl_amd64/ffprobe.zip" \
      5408ca588c8c72b0dde3afe676d0a7acf25ef97e55ae6eba5c7bede1cda42695 amd64-ffprobe.zip
    for arch in arm64 amd64; do
      for tool in ffmpeg ffprobe; do
        unpack_zip "$work/$arch-$tool.zip" "$work/$arch"
      done
    done
    # One binary for Apple Silicon and Intel; each part keeps its signature
    # until tool/package_macos.sh signs the whole for the release.
    mkdir -p "$work/universal"
    for tool in ffmpeg ffprobe; do
      lipo -create "$work/arm64/$tool" "$work/amd64/$tool" -output "$work/universal/$tool"
    done
    files=("$work/universal/ffmpeg" "$work/universal/ffprobe")
    ;;
  *)
    echo "usage: tool/fetch_ffmpeg.sh linux|windows|macos" >&2
    exit 2
    ;;
esac

rm -rf "$out"
mkdir -p "$out"
cp "${files[@]}" "$out/"
chmod +x "$out"/ff*
cp "$notice" "$out/FFmpeg-NOTICE.txt"
cp "$root/assets/licenses/gpl-3.0.txt" "$out/FFmpeg-LICENSE.txt"
echo "FFmpeg for $system is in ${out#"$root"/}"
