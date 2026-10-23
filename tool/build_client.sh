#!/usr/bin/env bash
# Compiles vidctrl-client, the console program that drives the open window
# (bin/vidctrl_client.dart), into the given folder: the one that holds the
# app, where the client looks for it (lib/core/control/launcher.dart). CI
# runs it after `flutter build` (.github/workflows/ci.yml); on macOS
# tool/package_macos.sh then puts it into the app and signs it.
#
#   tool/build_client.sh build/linux/x64/release/bundle
#   tool/build_client.sh build/windows/x64/runner/Release   (vidctrl-client.exe)
#
# `dart compile exe` refuses this package, as a dependency of the app
# (objective_c) has build hooks; `dart build cli` runs them and compiles the
# same program. It writes bundle/bin/<program> and bundle/lib/ with the
# hooks' libraries, which the program would load from the lib/ beside its
# bin/. The only one is objective_c's, made on macOS, which only
# Objective-C interop loads: the client has none (it imports only
# lib/core/), so the program is copied alone. Any other library stops the
# build, rather than ship a client that misses it.
set -euo pipefail

folder="${1:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "$folder" || ! -d "$folder" ]]; then
  echo "usage: tool/build_client.sh <folder that holds the app>" >&2
  exit 1
fi

if [[ "${OS:-}" == Windows_NT ]]; then
  ext=.exe
else
  ext=
fi

# Relative to the repository, so that no path needs converting for the
# Windows dart. `dart build cli` empties its output folder first.
out=build/cli
(cd "$root" && dart build cli --target bin/vidctrl_client.dart --output "$out")

shopt -s nullglob
for lib in "$root/$out"/bundle/lib/*; do
  if [[ "$(basename "$lib")" != objective_c.dylib ]]; then
    echo "error: dart build cli made ${lib#"$root"/}, which the client may need" >&2
    exit 1
  fi
done

program="$root/$out/bundle/bin/vidctrl_client$ext"
if [[ ! -f "$program" ]]; then
  echo "error: dart build cli made no ${program#"$root"/}" >&2
  exit 1
fi
cp "$program" "$folder/vidctrl-client$ext"
echo "Made $folder/vidctrl-client$ext"
