#!/usr/bin/env bash
# Makes the macOS download: puts FFmpeg into the app, signs everything inside
# out, packs a disk image and, with Apple's credentials, has the app and the
# image notarized so that macOS opens them without a warning. CI runs it
# (.github/workflows/ci.yml) after `flutter build macos --release` and
# `tool/fetch_ffmpeg.sh macos`.
#
#   tool/package_macos.sh vidctrl-1.2.0-macos.dmg
#
# Environment, all optional; without them the app is signed ad hoc (it then
# runs only after System Settings → Privacy & Security → Open Anyway):
#   MACOS_SIGN_IDENTITY  a "Developer ID Application: …" identity in the keychain
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                        an App Store Connect API key, for notarytool
set -euo pipefail

dmg="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/macos/Build/Products/Release/VidCtrl.app"
ffmpeg="$root/third_party/ffmpeg/macos"
identity="${MACOS_SIGN_IDENTITY:--}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ ! -x "$ffmpeg/ffmpeg" ]]; then
  echo "error: no FFmpeg in ${ffmpeg#"$root"/}; run tool/fetch_ffmpeg.sh macos" >&2
  exit 1
fi

# Beside the app's own executable, where lib/core/ffmpeg/locator.dart looks;
# the notice and licence among the resources.
cp "$ffmpeg/ffmpeg" "$ffmpeg/ffprobe" "$app/Contents/MacOS/"
mkdir -p "$app/Contents/Resources/FFmpeg"
cp "$ffmpeg/FFmpeg-NOTICE.txt" "$ffmpeg/FFmpeg-LICENSE.txt" "$app/Contents/Resources/FFmpeg/"

# Notarization asks for the hardened runtime and a secure timestamp on every
# piece of code; an ad hoc signature can have neither.
sign() {
  if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$@"
  else
    codesign --force --sign "$identity" --options runtime --timestamp "$@"
  fi
}

# notarize <file>: submits it and waits; fails unless Apple accepts it.
notarize() {
  xcrun notarytool submit "$1" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait --output-format json > "$work/notary.json"
  local status id
  status="$(plutil -extract status raw -o - "$work/notary.json")"
  if [[ "$status" != "Accepted" ]]; then
    id="$(plutil -extract id raw -o - "$work/notary.json")"
    echo "error: notarization of $1 ended as \"$status\"; Apple's log follows" >&2
    xcrun notarytool log "$id" \
      --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2
    exit 1
  fi
}

# Inside out: the frameworks, FFmpeg, then the app around them.
shopt -s nullglob
for code in "$app"/Contents/Frameworks/*.framework "$app"/Contents/Frameworks/*.dylib; do
  sign "$code"
done
sign "$app/Contents/MacOS/ffmpeg" "$app/Contents/MacOS/ffprobe"
sign --entitlements "$root/macos/Runner/Release.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

notarized=false
if [[ "$identity" != "-" && -n "${NOTARY_KEY_ID:-}" ]]; then
  # The app is notarized and stapled on its own as well, so that it opens
  # without a network connection once copied out of the image.
  ditto -c -k --keepParent "$app" "$work/VidCtrl.zip"
  notarize "$work/VidCtrl.zip"
  xcrun stapler staple "$app"
  notarized=true
fi

# The image: the app and a shortcut to Applications to drag it to.
mkdir "$work/image"
ditto "$app" "$work/image/VidCtrl.app"
ln -s /Applications "$work/image/Applications"
rm -f "$dmg"
hdiutil create -volname VidCtrl -srcfolder "$work/image" -fs HFS+ -format ULMO "$dmg"

if [[ "$identity" != "-" ]]; then
  codesign --force --sign "$identity" --timestamp "$dmg"
fi
if [[ "$notarized" == true ]]; then
  notarize "$dmg"
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
echo "Made $dmg (notarized: $notarized)"
