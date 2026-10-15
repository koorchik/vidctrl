#!/usr/bin/env bash
# Writes the notes for the release of a tag: how to get the app going, then
# what was committed since the release before. CI publishes them with the
# release (.github/workflows/ci.yml).
#
#   tool/release_notes.sh v1.2.0
set -euo pipefail

tag="$1"
version="${tag#v}"
# The nearest earlier version tag; none for the first release, which then
# lists everything.
previous="$(git describe --tags --abbrev=0 --match 'v*' "$tag^" 2>/dev/null || true)"

cat <<EOF
## Getting it going

| System | Download | Then |
|---|---|---|
| Linux (x64) | \`tvv-videoconvertor-$version-linux-x64.tar.gz\` | Unpack it and run \`tvv_videoconvertor\` in the folder |
| Windows (x64) | \`tvv-videoconvertor-$version-windows-x64.zip\` | Unpack it and run \`tvv_videoconvertor.exe\` |
| macOS | \`tvv-videoconvertor-$version-macos.zip\` | Unpack it and open the app |

**FFmpeg is not included.** Install FFmpeg 8 or newer, so that \`ffmpeg\` and
\`ffprobe\` are found on the \`PATH\`. Linux distribution packages and Homebrew
have everything the app uses. On Windows take a "full" build: the smaller
"essentials" builds have no AV1 encoder, so "For the archive" makes larger
HEVC files with them, and "Smallest" for the free Resolve fails.

The app is not signed, so Windows and macOS ask before running it for the
first time:

- **Windows:** "Windows protected your PC" → More info → Run anyway.
- **macOS:** after it refuses, System Settings → Privacy & Security → Open
  Anyway. On older versions, right-click the app and choose Open.

So far only the Linux build has been tried on a real machine; the Windows and
macOS builds come straight from the build servers. On Windows, stopping a
conversion part-way has failed in tests, and pausing and keeping the computer
awake are not there yet.

## Changes

EOF
git log --no-merges --format='- %s' "${previous:+$previous..}$tag"
