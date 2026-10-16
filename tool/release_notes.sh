#!/usr/bin/env bash
# Writes the notes for the release of a tag: how to get the app going, then
# what was committed since the release before. CI publishes them with the
# release (.github/workflows/ci.yml).
#
#   tool/release_notes.sh v1.2.0
#
# MACOS_NOTARIZED=true when the macOS app was signed and notarized; without
# it the notes say how to open an app that macOS refuses.
set -euo pipefail

tag="$1"
version="${tag#v}"
# The nearest earlier version tag; none for the first release, which then
# lists everything.
previous="$(git describe --tags --abbrev=0 --match 'v*' "$tag^" 2>/dev/null || true)"
# Where FFmpeg's notice is: a link in CI, which knows the repository.
notice="assets/licenses/ffmpeg.txt"
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  notice="[$notice](${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/blob/$tag/$notice)"
else
  notice="\`$notice\`"
fi
if [[ "${MACOS_NOTARIZED:-}" == true ]]; then
  macos="The macOS app is signed and notarized by Apple and opens without asking."
else
  # Downloaded files carry a quarantine mark, and macOS refuses an app that
  # Apple has not notarized while it has one. Removing it from the whole app
  # also covers the FFmpeg inside, which the app starts by itself.
  macos="The macOS app is not notarized by Apple yet, so macOS refuses to open
it. After dragging it to Applications, open Terminal and run this once; then
VidCtrl opens like any other app:

\`\`\`sh
xattr -dr com.apple.quarantine /Applications/VidCtrl.app
\`\`\`"
fi

cat <<EOF
## Getting it going

| System | Download | Then |
|---|---|---|
| Linux (x64) | \`vidctrl-$version-linux-x64.tar.gz\` | Unpack it and run \`vidctrl\` in the folder |
| Windows (x64) | \`vidctrl-$version-windows-x64.zip\` | Unpack it and run \`vidctrl.exe\` |
| macOS (Apple Silicon and Intel) | \`vidctrl-$version-macos.dmg\` | Open it and drag VidCtrl to Applications |

**FFmpeg is included**, so nothing else needs installing. It is FFmpeg 8.1,
unmodified builds under the GNU GPL version 3; $notice says whose builds
they are and where their source code is.

The Windows app is not signed, so Windows asks before running it for the
first time: "Windows protected your PC" → More info → Run anyway.

$macos

So far only the Linux build has been tried on a real machine; the Windows and
macOS builds come straight from the build servers. On Windows, stopping a
conversion part-way has failed in tests, and pausing and keeping the computer
awake are not there yet.

## Changes

EOF
git log --no-merges --format='- %s' "${previous:+$previous..}$tag"
