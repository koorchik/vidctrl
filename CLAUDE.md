# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter desktop app (Linux, Windows, macOS) that converts batches of videos
by goal ("For the archive", "Edit in DaVinci Resolve", "Send to a phone", …). It
drives the `ffmpeg` and `ffprobe` executables as separate processes; it does
not link FFmpeg libraries. FFmpeg is not bundled yet: it is found on `PATH`
(FFmpeg 8 or newer, with `libx265`, `libsvtav1`, `prores_ks`, `dnxhd`).

What is built and what is not: `docs/ROADMAP.md`.

## Commands

```sh
flutter pub get
flutter run -d linux                                  # or -d windows, -d macos
flutter build linux --release                         # build/linux/x64/release/bundle

flutter test --exclude-tags "ffmpeg || screenshots"   # fast: logic and widgets
flutter test --tags ffmpeg                            # real conversions, needs ffmpeg + ffprobe
flutter test --tags ffmpeg_check                      # just the quick check of the installed FFmpeg
flutter test --tags screenshots                       # writes PNGs to build/screenshots/

flutter test test/app/workspace_test.dart             # one file
flutter test test/app/workspace_test.dart --plain-name "pause holds the queue"

flutter analyze
dart format lib test tool                             # CI fails on unformatted code
flutter gen-l10n                                      # after editing lib/l10n/*.arb
flutter test tool/make_icons.dart                     # redraws the app icon files
flutter test tool/make_screenshots.dart               # redraws the README's pictures (docs/screenshots/)
dart run tool/desktop_entry.dart                      # Linux: registers the icon with the desktop

dart run tool/convert.dart --list                     # the engine without the UI
dart run tool/convert.dart archive.master clip.mov --dry-run
dart run tool/calibrate_archive.dart a.mov b.mp4      # quality numbers for "For the archive"
```

- Several `--exclude-tags` flags do not combine; use the `"a || b"` form.
- After a UI change, run the screenshots and look at the PNGs. If the main
  screen looks different, redraw the README's pictures too; they are committed.
- CI (`.github/workflows/ci.yml`) runs the format check, `flutter analyze`,
  the fast tests, the quick FFmpeg check and a release build on Linux, Windows
  and macOS. The check (`test/integration/ffmpeg_check_test.dart`, a second
  long) is: FFmpeg found, the needed encoders there, one short clip
  converted. The real conversions (`--tags ffmpeg`, minutes of encoding) are
  not run in CI: run them here before a change to the engine goes out.
- CI's Linux has Ubuntu's FFmpeg 6.1, older than the app supports. The check
  passes with it, but one real conversion test does not (irregular frame
  timing comes out at 23.976 instead of 30), so a result from CI's Linux says
  nothing about FFmpeg 8.
- A pushed version tag (`v1.2.0`, or `v1.2.0-beta.1` for a pre-release) makes
  the same workflow publish a GitHub release once all three builds pass. The
  tag gives the app its version (`--build-name`) and the archives their
  names; `pubspec.yaml`'s version is not used. `tool/release_notes.sh v1.2.0`
  prints the notes: fixed instructions, then the commit subjects since the
  previous tag, so commit subjects are what users read.

## Architecture

### Two layers

- `lib/core/` is the engine: plain Dart with no Flutter imports, so it runs
  under `dart run` (`tool/convert.dart`) and is tested without widgets.
- `lib/app/` is the Flutter UI and its state (Riverpod notifiers).

### How a conversion is decided (`lib/core`)

A preset holds no command line. `Preset.plan(MediaInfo, options,
Capabilities)` (`scenarios/scenario.dart`) looks at one file and returns a
`ConversionPlan` with a `PlanKind`: `skip` (already fine), `remux`,
`audioOnly`, `encode` or `unsupported`. Re-encoding is the last resort.

- `media/ffprobe.dart` turns a file into `MediaInfo`; the whole ffprobe report
  is kept on `MediaInfo.raw` for the details window.
- `ffmpeg/capabilities.dart` probes what this FFmpeg and machine can really
  do (encoders, working hardware encoders, filters, accepted SVT-AV1
  parameters). Presets consult it; nothing is assumed.
- `ffmpeg/command_builder.dart` turns a plan into arguments. A sample is the
  same arguments plus a time range, so a sample cannot differ from the real
  result. `forDisplay: true` gives the version shown to people.
- `ffmpeg/runner.dart` runs the process (progress, graceful cancel, pause);
  `queue/job_executor.dart` wraps one conversion: temporary file, rename on
  success, cleanup on failure.
- `estimate/size_estimator.dart` predicts output size: calculated for copies
  and fixed-rate formats, measured by encoding short pieces otherwise.
- `scenarios/registry.dart` lists the scenarios in display order.

Sound: lossless or unusual sound (the FLAC or PCM of an editor export) becomes
AAC at 320 kbit/s for stereo (`highQualityAac` in `scenarios/blocks.dart`); AAC
already at or below that is copied untouched. Resolve on Linux is the
exception: it reads no AAC, so those presets write PCM.

### App state (`lib/app`)

Four notifiers, each owning one concern. Data flows left to right:

```
sourcesProvider ─┐
                 ├─> previewProvider ──> (video list, panel summary)
recipeProvider ──┤        │
                 │   estimateCacheProvider <── finished samples
                 └─> queueProvider ──> JobExecutor
```

- **Videos** (`sources/`): files added, each path once. The selection says
  which videos the panel applies to; newly added videos become the selection.
- **Recipe** (`recipe/`): the panel's goal, options, whole video or sample, and
  output folder. Goal and folder are remembered (`settings.dart`); the sample
  choice is not.
- **Preview** (`sources/preview_controller.dart`): plans each selected video
  with the current recipe and has its expected size measured, only while the
  queue is idle.
- **Queue** (`queue/`): a job is a snapshot (video info, recipe, plan, output
  path) made by Add to queue / Add all, so later panel changes do not touch
  it. The queue starts by itself and runs one job at a time. An identical job
  still pending is not added twice.
- **Estimates** (`estimates/`): expected sizes shared by the video list and
  the queue, keyed by file and goal; a finished sample overwrites a
  measurement with its better one.

Output names carry the settings through each preset's `nameSuffix`
(`_hevc-crf20`); samples add `_sample10s` and go to `Samples/`.
`test/core/scenarios/file_names_test.dart` lists them all.

The screen (`home/`) is three panes over those providers: `videos_pane`,
`queue_pane`, `recipe_pane`. `home/scenario_texts.dart` maps scenario, preset
and option ids to words; the engine knows them only by id.

### The seam for tests

Everything that touches the machine is reached through `environmentProvider`
(`providers.dart`): ffprobe, the job executor, capabilities, the sleep
inhibitor, the estimator, the thumbnailer. Tests replace it with
`FakeEnvironment` (`test/support/fakes.dart`), whose fake jobs finish only when
the test says so. `test/support/pump_app.dart` is the widget-test harness;
`test/support/test_media.dart` generates real clips for the `ffmpeg` tests, so
no footage is stored in the repository.

## UI rules that tests enforce

The test of every UI decision: a non-technical person drops in large camera
videos and gets small files that look the same, with no help.

- **Plain words lead; technical names follow in smaller type** ("Smallest
  file" with "AV1" underneath). Technical terms on the main screen go only
  through the `TechnicalText` widget (`home/technical_text.dart`).
  `test/app/home_screen_test.dart` checks every other text against a list of
  terms, in both languages.
- **Nothing to scroll in the "What to do" panel.** It shows every control at
  the smallest window size (`window.dart`), in every goal, option and
  language. `test/app/no_scrolling_test.dart` checks every combination at
  three window heights, and also that no label is cut off or broken inside a
  word. So a new control takes one row (label beside the control), and
  anything bigger opens in a small window ("More options…"). If the test
  fails after a change, make the change fit; do not raise the minimum window
  size without a reason.
- **Safe defaults.** "For the archive" is pre-selected: one quality, the
  highest, in AV1 (HEVC where FFmpeg has no AV1). Drop videos, press Add to
  queue, done. Its format and speed rows each say under them what the chosen
  variant trades away (`choiceHint` in `scenario_texts.dart`; each variant's
  is also its tooltip). With such rows, the goal's own explanation shows
  only in the roomier window, so the smallest one still fits.
- More is available on request only: "More options…", and "Show the command"
  and "Video details" in the ⋯ menus.

## The two looks

The app comes in two looks (`Look` in `theme.dart`), switched with the palette
button beside the language button and remembered (`lookProvider` in
`settings.dart`). The layout and every size are the same in both.

- **Cozy**, the one the app starts with: light, warm, rounded and cheerful.
  Bright cream surfaces over a soft peach-to-mint backdrop, cocoa text, an
  orange accent, sentence-case headings, and a set of colours (`Hues`) so
  that each goal, track type and icon has its own.
- **Professional**: dark, flat and nearly square, the look of the camctrl app
  (a sibling project). Near-black surfaces told apart by steps of grey and
  1 px lines, one blue accent, pane titles and control labels in spaced
  capitals, technical captions in the fixed-width font.

How a widget stays right in both:

- Colours come from `Theme.of(context).colorScheme`. Both schemes set by hand
  every role the widgets read, so set a new role in both before reading it,
  or it shows Flutter's default colour.
- Everything else that differs (corner radii, border widths, capitals, the
  caption font, a few colours with no scheme role) comes from
  `AppLook.of(context)`. No widget names a palette or checks which look is on.
- An icon or mark that should be colourful in Cozy reads `look.hues`, which
  is null in Professional, and falls back to the quiet colour:
  `look.hues?.amber.deep ?? scheme.onSurfaceVariant`. A `Hue` is a pair:
  `deep` for the icon or small text (each passes as text on white), `soft`
  for the fill behind it. Goals take theirs by position (`hues.at(index)`).
- Pane titles and control labels go through `PaneTitle` and `ControlLabel`
  (`home/headings.dart`), which make the capitals; the ARB strings stay in
  ordinary case.
- A change of size belongs in the shared `_theme()` builder, never in one
  look: `no_scrolling_test.dart` checks the panel in each look, and
  `flutter test --tags screenshots` writes every screen once per look
  (`3_queue_cozy.png`, `3_queue_pro.png`).
- In both looks the accent is for what is chosen, active or clickable; green
  for done; the scheme's `tertiary` (teal in Cozy, amber in Professional) for
  things worth noticing (a sample, HDR, personal data); red for failures.

## Adding a goal

1. Write `lib/core/scenarios/<name>.dart` with a `Scenario` and its presets.
   Give the plan a `nameSuffix` that names the settings that matter.
2. Add it to `scenarios` in `registry.dart`.
3. Add its texts to both ARB files and to `home/scenario_texts.dart`.
4. Add table-driven plan tests in `test/core/scenarios/`, a row in
   `file_names_test.dart`, and at least one real conversion in
   `test/integration/conversion_test.dart`.

The UI renders presets and options generically; it needs no other change.

## Conventions

- Tests are named for the behaviour they check, and assert what a user would
  observe.
- A user-facing string goes in **both** ARB files (`app_en.arb` is the
  template; the generated `app_localizations*.dart` files are committed).
- FFmpeg arguments are always a list, never a shell string. Paths are passed
  with the `file:` prefix (`inputUrl`).
- Outputs are written to a hidden `.name.part` file and renamed on success.
  Originals are never overwritten.
- No personal information in files: no usernames, home paths, hostnames or
  real names. Use relative paths and placeholders.

## Things that were learned the hard way

- **Colour tags:** FFmpeg 8 carries primaries, transfer, matrix and range from
  source to output by itself and ignores `-color_primaries`, `-color_trc` and
  `-colorspace` for encodes. Presets pass no colour arguments; the HLG tests
  in `conversion_test.dart` are what guards this.
- **SVT-AV1 parameters:** an unknown `-svtav1-params` key only produces a
  warning ("Error parsing option") and exit code 0. `CapabilityProbe` checks
  the warning text, not just the exit code.
- **Hardware encoders:** being listed by `ffmpeg -encoders` means compiled in,
  not usable. Each is tested with a real 8-frame encode, in 10-bit.
- **MOV cannot hold AV1 or VP9** when written by FFmpeg; those go to MP4.
- **Muxer-specific options** such as `-write_tmcd` and `-movflags` make
  FFmpeg fail on other containers; add them only for MP4/MOV.
- **MP4 drops unknown tags** such as `make` when writing; MOV keeps them.
  Matters for test fixtures with planted metadata. `-movflags
  use_metadata_tags` keeps them in MP4, but then also copies the source's
  `major_brand` and `compatible_brands` tags (a camera MOV's `qt`), so the
  archive goal blanks those with `-metadata major_brand=` and the like. The
  real file type box is unaffected.
- **NVENC's constant quality is capped.** With `-rc vbr -cq N -b:v 0` and
  no `-maxrate`, NVENC limits the bitrate by itself (about 21 Mbit/s for
  HEVC, 31 for AV1 at 4K), so on detailed footage `-cq 20` and `-cq 24` gave
  byte-identical files and a picture below the CPU encoders'. A high
  `-maxrate` alone makes it write HEVC level 6.1, which some players refuse;
  a 40M limit alone makes it pick level 5.0 in the high tier. The archive
  goal sets `-level` and `-tier main` for the picture size and frame rate
  and that level's limit (`playableLevel` in `archive.dart`). Two-pass
  (`-multipass`) gave nothing measurable in this mode, at 40% more time.
- **Quality numbers** in `archive.dart` were matched with FFmpeg's `xpsnr`
  filter (no `libvmaf` in Ubuntu's build), on 10-second 4K pieces, to at
  least 42 dB on the hardest clip; `tool/calibrate_archive.dart` repeats
  the measurement on any clips. One number cannot give the same score on
  calm and busy footage, so the hardest clip decides.
- **Tone mapping** needs the `zscale` and `tonemap` filters, which not every
  build has; `Capabilities.hasFilter` is checked first.
- **Cancel:** `q` on stdin makes FFmpeg finish the file and exit with code 0,
  so the runner tracks cancellation itself. `cancel()` only asks: FFmpeg has
  exited and the `.part` file is gone when the handle's `result` completes.
  An app that leaves in between abandons a running FFmpeg and the unfinished
  file, so closing the window goes through `QueueController.shutDown()` and
  `EstimateCache.stopMeasuring()`, which wait.
- **Expected size** of a quality-targeted encode cannot be calculated; the
  estimator encodes 3-second pieces spread over the video (picture only; the
  sound is calculated) and scales up. It is stopped when converting starts.
- **Byte counts overflow when multiplied.** Tens of gigabytes times
  gigabytes exceeds 64-bit integers; take the ratio first.
- **Widget tests:**
  - Real disk access never completes inside the test's fake clock; go through
    `addVideos()` in `pump_app.dart`, which uses `tester.runAsync`.
  - Awaiting `StreamSubscription.cancel()` also escapes the fake clock; the
    queue controller does not await it.
  - `pumpAndSettle` never returns while a job runs (its progress bar
    animates); pump fixed times instead.
  - Without `loadRealFonts()` text is laid out in a much wider placeholder
    font; tests about what fits must load the real ones.
- **Fonts:** both fonts are bundled so text takes the same room on every
  computer (the no-scrolling layout depends on it). Roboto is the interface
  font; it has no arrow glyphs, so JetBrains Mono is its fallback. JetBrains
  Mono is also the fixed-width font, because the generic `monospace` family
  does not resolve to one on every Linux desktop.
- **Closing the window:** `window_manager` reports a close a second time,
  for the close that `destroy()` itself causes. Answering that with another
  `destroy()` reaches the plugin after the window is gone and crashes the app
  on Linux (a segmentation fault that `flutter run` shows only as "Lost
  connection to device"). `WindowCloseGuard` destroys once. The engine's
  "The implicit view cannot be removed" line on every close is harmless.
- **App icon:** the drawing in `tool/make_icons.dart` is the source; it
  writes the macOS, Windows and Linux files, so change the drawing and never
  the files. On Linux the runner sets the window icon, which only X11
  desktops show. Wayland desktops take it from a desktop entry named after
  the application identifier and show a generic icon without one. There is
  no installer yet, so `tool/desktop_entry.dart` registers the entry on a
  developer's computer: run it again after the icon changes, and with
  `--remove` before changing the identifier. A window already open keeps the
  icon it opened with, so restart the app to see a change.
- **Menus near the window's edge:** `MenuAnchor` opens a menu from its
  button's left side, and one that would run past the window is moved back
  only until it touches the edge, where its side and shadow are cut off. The
  buttons in the panel's corner use `showMenuUnder`
  (`home/widgets/button_menu.dart`) instead, which lines the menu up with the
  button's right side. A test opens both at the smallest window.
- **Resolve on Linux** (Blackmagic's codec list for 21.1): no AAC in either
  edition, no H.264/H.265 in the free edition. Details in the header of
  `resolve_linux.dart`.
