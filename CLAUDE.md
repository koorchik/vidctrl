# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter desktop app (Linux, Windows, macOS) that converts batches of videos
by goal ("Archive", "Save space", "Edit in DaVinci Resolve", …). It drives the
`ffmpeg` and `ffprobe` executables as separate processes; it does not link
FFmpeg libraries. Each release carries a pinned FFmpeg 8.1 (see "Bundled
FFmpeg"); in development it is found on `PATH` (FFmpeg 8 or newer, with
`libx265`, `libsvtav1`, `prores_ks`, `dnxhd`).

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
dart format lib test tool bin                         # CI fails on unformatted code
flutter gen-l10n                                      # after editing lib/l10n/*.arb
flutter test tool/make_icons.dart                     # redraws the app icon files
flutter test tool/make_screenshots.dart               # redraws the README's pictures (docs/screenshots/)
dart run tool/desktop_entry.dart                      # Linux: registers the icon with the desktop
tool/fetch_ffmpeg.sh linux                            # the pinned FFmpeg into third_party/ffmpeg/ (or windows, macos)
tool/build_client.sh build/linux/x64/release/bundle   # vidctrl-client beside a built app
tool/build_client.sh build/linux/x64/debug/bundle     # once, for the agent window under flutter run
flutter test tool/make_manual.dart                    # rewrites docs/CLIENT.md and the client's goal words

dart run tool/convert.dart --list                     # the engine without the UI
dart run tool/convert.dart archive.master clip.mov --dry-run
dart run tool/calibrate_archive.dart a.mov b.mp4      # quality numbers for the archive

# With a window open (flutter run), drive it from another terminal; add
# --json to any command, and see the client's own help for the commands:
dart run bin/vidctrl_client.dart --help
# With none open, any command but status, manual and help starts one;
# VIDCTRL_APP names a development build to start:
VIDCTRL_APP=build/linux/x64/debug/bundle/vidctrl dart run bin/vidctrl_client.dart queue
```

- Several `--exclude-tags` flags do not combine; use the `"a || b"` form.
- After a UI change, run the screenshots and look at the PNGs. If the main
  screen looks different, redraw the README's pictures too; they are committed.
- CI (`.github/workflows/ci.yml`) runs the format check, `flutter analyze`,
  the fast tests, the quick FFmpeg check and a release build on Linux, Windows
  and macOS. The check (`test/integration/ffmpeg_check_test.dart`, seconds
  long) is: FFmpeg found, the needed encoders there, one short clip
  converted, the archive's AV1 close enough to its original. The real
  conversions (`--tags ffmpeg`, minutes of encoding) are not run in CI: run
  them here before a change to the engine goes out.
- CI tests the FFmpeg the app ships: it fetches the pinned one first and
  puts it first on the `PATH`, then checks that the built app carries it.
- The builds CI makes carry `vidctrl-client` where it finds the app
  (`tool/build_client.sh`): the Linux bundle, beside `vidctrl.exe`, and
  `Contents/MacOS/`, where `tool/package_macos.sh` signs it with FFmpeg. CI
  checks that it is there and that `vidctrl-client --help` runs.
- A pushed version tag (`v1.2.0`, or `v1.2.0-beta.1` for a pre-release) makes
  the same workflow publish a GitHub release once all three builds pass. The
  tag gives the app its version (`--build-name`) and the downloads their
  names; `pubspec.yaml`'s version is not used. Through `--dart-define` it
  also gives the version the About menu shows and the repository whose
  latest release it is compared with (`lib/app/build_info.dart`): once at
  the start, for the header's "New version" tag (`newerReleaseProvider`),
  and on "Check for updates…". Any other build is a development build,
  which does not check; to try the check, run with
  `--dart-define=VIDCTRL_VERSION=0.1.0 --dart-define=VIDCTRL_REPOSITORY=<owner>/<repo>`.
  `tool/release_notes.sh v1.2.0` prints the notes: fixed instructions, then
  the commit subjects since the previous tag, so commit subjects are what
  users read. Without the signing secrets listed in the README the macOS
  app is signed ad hoc, not notarized, and the notes say how to open it.

## Bundled FFmpeg

- `tool/fetch_ffmpeg.sh` pins VidCtrl's own builds by checksum, one per
  system, from the separate `vidctrl-ffmpeg` repository: the same library
  versions everywhere, so what was measured is what ships. The ready-made
  builds used before differed by system, and the macOS one carried SVT-AV1
  3.1.2 (see "SVT-AV1 on Apple chips"). Its `build.sh` builds for macOS
  (universal), Linux and Windows (cross-compiled on Ubuntu), pinning every
  library by version and checksum and taking only what the app uses; its
  `check.sh` must pass for each before a release (linked only to what every
  computer of that kind has, not nonfree, the encoders, hardware ones too,
  and filters the app uses, the archive's AV1 "looks the same"). The
  workflow there, run by hand with Publish, builds and checks the three and
  makes one release with the zips and a tar of every source; then pin the
  zips here.
- They are GPL v3 (`--enable-version3`). The notice
  `assets/licenses/ffmpeg.txt` points at each build's source and build
  scripts; it goes beside the binaries, into the app's licences page
  (`lib/app/licenses.dart`) and the release notes. The fetch script refuses
  pins that the notice does not name, so change the two together.
- Where each build puts it, and where `FfmpegLocator` looks: Linux
  `bundle/lib/ffmpeg/` (`linux/CMakeLists.txt`), Windows beside the `.exe`
  (`windows/CMakeLists.txt`), macOS `Contents/MacOS/`
  (`tool/package_macos.sh`, which also signs inside out, makes the disk
  image and notarizes). The CMake rules add it only when
  `third_party/ffmpeg/<system>/` exists, so a development build uses the
  `PATH`.
- To move to a newer FFmpeg: publish it from `vidctrl-ffmpeg`, change the
  release and checksums here and the notice, run `tool/fetch_ffmpeg.sh
  linux`, then `flutter test --tags ffmpeg` with `third_party/ffmpeg/linux`
  first on the `PATH`.
- The app offers no way to use another FFmpeg: the quality numbers were
  measured with the bundled one. `FfmpegLocator` falls back to the `PATH`
  only for development, where nothing is bundled.

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
- `ffmpeg/runner.dart` runs the process (progress, cancel, pause);
  `queue/job_executor.dart` wraps one conversion: temporary file, rename on
  success, cleanup on failure.
- `estimate/size_estimator.dart` predicts output size: calculated for copies
  and fixed-rate formats, measured by encoding short pieces otherwise. Each
  piece is also compared with the original, so the video list and the
  waiting jobs say how close the result will look (the poorest piece).
- `quality/quality_search.dart` chooses each archive video's quality from
  those measurements. The poorest piece must look the same (VMAF 95, or
  XPSNR 42 without VMAF); the preset's standard crf is the poorest allowed,
  and a video that falls short gets a lower one, down to a best
  (`RaisesQuality` in `scenario.dart`, numbers in `archive.dart`). Four
  outcomes: standard, raised, `belowTarget` (still short at the best: it
  is converted anyway, its name ends in `-check` and the app asks for a
  look by eye) and `notWorthIt` (the result would keep over 80% of the
  original's size: left as it is, with "Convert anyway" in the queue). The
  search measures the best number second, so a hopeless video costs two
  tries; otherwise it interpolates, six tries at most. A standard result
  already past the size limit ends it: better ones only grow.
- `quality/frame_grabber.dart` grabs the hardest frame of the poorest piece
  from the original and the result, full size, for the (i) window
  (`home/widgets/quality_report.dart`), which shows them at real size with
  an Original/Result switch. Before converting, the piece encoded while
  measuring stands in for the result; it is kept only for a `belowTarget`
  video and deleted when the app closes.
- `quality/quality_meter.dart` compares a result with its original in one
  pass: XPSNR (`xpsnr`) always, VMAF (`libvmaf`, the 4K model above 1080p)
  where the FFmpeg has it; frames paired by order, a sample against the same
  piece. `closenessOf` turns the scores into words, by VMAF where measured.
  "Compare with the original", the size estimator and
  `tool/calibrate_archive.dart` use it.
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
  still pending is not added twice. An archive job whose quality is not
  known yet measures its video first ("Checking the quality…", then
  "Choosing the quality… try N"), keeps the result for the list too, and
  takes its plan and file name from it. Cancel and pause stop the
  measuring at once (it cannot be held midway; continuing measures again).
  A sample of a video not worth converting is made all the same. Adding is
  never blocked by measuring.
- **Estimates** (`estimates/`): expected sizes shared by the video list and
  the queue, keyed by file and goal; a finished sample overwrites a
  measurement with its better one.
- **Quality** (`quality/`): "Compare with the original" in a finished job's
  ⋯ menu, one comparison at a time, the result kept by job id. Offered only
  where each output frame stands for one source frame (`canComparePlan`:
  no resizing, retiming or tone mapping). Closing the window stops it, like
  the queue and the estimates.

Output names carry the settings through each preset's `nameSuffix`
(`_hevc-crf20`); samples add `_sample10s` and go to `Samples/`.
`test/core/scenarios/file_names_test.dart` lists them all.

The screen (`home/`) is a header (`app_header`) and three panes over those
providers: `videos_pane`, `queue_pane`, `recipe_pane`. `home/scenario_texts.dart` maps scenario, preset
and option ids to words; the engine knows them only by id.

### Control by `vidctrl-client`

A running window serves a JSON-RPC control server so a program or an agent can
drive it the way a person does: `lib/core/control/` is the transport (plain
Dart: `package:json_rpc_2` over a loopback socket, a `hello` with a token as
the first message, the endpoint file, the protocol's names), and
`lib/app/control/` is the server (`controlProvider`, started by `main.dart`
and stopped first when the window closes). Every method goes through the
notifiers the buttons use (`SourcesController`, `QueueController`,
`EstimateCache`, `QualityController`), so the window shows what a client does
and the rules (plans, quality search, one job at a time) are the same. The
first window to start owns the endpoint file `control.json` (Linux
`$XDG_RUNTIME_DIR/vidctrl/`, else `~/.cache/vidctrl/`; macOS under
`~/Library/Application Support/app.camctrl.vidctrl/`; Windows
`%LOCALAPPDATA%\VidCtrl\`), mode 0600, holding port, token, pid, version and
protocol; it is removed when the window closes. The client program
(`dart run bin/vidctrl_client.dart …`, `vidctrl-client` once compiled) imports
only `lib/core/`; `VIDCTRL_APP` names the app it starts when no window is
open, for a development build, and `VIDCTRL_ENDPOINT=<file>` gives the
window and the client another endpoint file, so a development copy runs
beside an installed one. On macOS the client starts the app with `open`,
which passes it no environment, so `VIDCTRL_ENDPOINT` does not reach a
window started that way: start that window by hand with it set. `dart
compile exe` refuses this package (a dependency, `objective_c`, has build
hooks); `dart build cli --target bin/vidctrl_client.dart` makes the
program, and `tool/build_client.sh` copies it beside an app.

### The seam for tests

Everything that touches the machine is reached through `environmentProvider`
(`providers.dart`): the FFmpeg found and where, ffprobe, the job executor,
capabilities, the sleep inhibitor, the estimator, the thumbnailer. Tests replace it with
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
- **Safe defaults.** "Archive" is pre-selected: one quality, the highest, in
  AV1 (HEVC where FFmpeg has no AV1). Drop videos, press Add to queue, done.
  Its format and speed rows each say under them what the chosen variant trades
  away (`choiceHint` in `scenario_texts.dart`; each variant's is also its
  tooltip). With such rows, the goal's own explanation shows only in the
  roomier window, so the smallest one still fits.
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
3. Add its texts to both ARB files and to `home/scenario_texts.dart`. Keep
   the title short; what sets it apart from a like goal goes in a subtitle
   (`scenarioSubtitle`), shown smaller under it on the tile ("Archive" / "no
   quality loss"). `no_scrolling_test.dart` fails if either is cut off. What
   the goal does to every video unasked (a size limit) goes in a notice
   (`scenarioNotice`), shown under its explanation in `tertiary`.
4. Add table-driven plan tests in `test/core/scenarios/`, a row in
   `file_names_test.dart`, and at least one real conversion in
   `test/integration/conversion_test.dart`.
5. For `vidctrl-client`'s manual, say in `_leaves`
   (`lib/core/control/manual.dart`, one entry per scenario) what the goal
   is for and leaves as it is in a few words (the manual's line, which
   must stay under 16 KB in all), and what it leaves in full (`help
   goals`); then run `flutter test tool/make_manual.dart`, which
   rewrites `docs/CLIENT.md` and the goal words the client prints
   (`manual_test.dart` fails until then).

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
- **Where the colour samples sit** (chroma location): FFmpeg forgets it
  when it makes a picture 10-bit and gives it to no hardware AV1 encoder,
  so a camera's 8-bit video came out as AV1 saying "unknown", and a player
  may draw the colour half a sample off. HEVC needs nothing: saying nothing
  means "left" there. AV1 encodes are marked after encoding
  (`av1ChromaPositionArgs` in `blocks.dart`, the `av1_metadata` filter);
  4:2:2 and 4:4:4 are made 4:2:0 with `out_chroma_loc=left`, as FFmpeg's
  own conversion puts the samples elsewhere. The conversion tests check it.
- **SVT-AV1 on Apple chips:** SVT-AV1 3.1.2, in Martin Riedl's macOS builds
  (built with Apple clang 14), encodes worse with its Arm code than with
  its C code: at the same size, faces on a 4K camera clip got blocks (38.7
  against 40.6 dB). SVT-AV1 4.2 (Homebrew) is right; its Arm build cannot
  run its C code (`asm=c` fails there), so the check compares scores, not
  files. The quick FFmpeg check encodes a test pattern with the archive's
  AV1 and requires more than 44 dB: 45.1 to 46.2 with good builds, 42.5
  with that one. Riedl's build script still pins 3.1.2, hence
  VidCtrl's own builds (40.57 dB on that camera clip on an M1, like Linux;
  the test pattern scores 45.20 dB on every system).
- **XPSNR 42 dB is strict for grainy footage.** On a 4K Nikon clip the
  archive's AV1 gave 41.4 dB and VMAF 96.0, with nothing to see; 42 dB took
  1.5 times the size (crf 27). The blocky Arm build gave 39.5 dB and VMAF
  92.5. So the comparison's verdict follows VMAF (95 "looks the same", 93
  "very close").
- **Already compressed films lose detail at the archive's quality.** A
  dark, grainy 1080p film download (H.264, about 10 Mbit/s) came out with
  smooth, plastic faces at crf 35: VMAF 89 to 97 by piece, XPSNR near 39 dB.
  A camera's file carries far more than it needs (a Nikon's 4K HEVC at 112
  Mbit/s lost nothing visible at a tenth of that); such a download does
  not. More bytes are the only cure: crf 25 took 2 to 2.4 times the size,
  and crf 20 (70% of the original's) still fell short of it. XPSNR barely
  moves on grain (38.0 to 39.1 dB from crf 35 to 20), so it cannot pick a
  crf there. Nothing else helped per byte: `luminance-qp-bias`, variance
  boost, `ac-bias`, `tf-strength`, `tune=1` (worse), preset 2 (5 to 10%
  smaller, four times slower); SVT-AV1 has no two-pass mode with crf.
  `film-grain=8` cost nothing in size and removed banding, but brought
  back only grain, not detail, and lowers plain XPSNR 1 to 2 dB, as drawn
  grain is not the original's; it was left out for now.
- **Screenshots for comparing:** FFmpeg turns an 8-bit picture into RGB by
  a faster, less exact path than a 10-bit one, so the 8-bit original came
  out darker and more contrasty than its 10-bit copy, a difference that is
  not in the files. `scale=flags=accurate_rnd+full_chroma_int` before
  `format=rgb24` makes both alike (`FrameGrabber`); the colour tags in the
  files are read as they are.
- **SVT-AV1 4.2 notes:** `scd=1` is ignored with a warning. `tune=0` turns
  CDEF and loop restoration off on frames it finds noisy. `film-grain=N`
  sets how noisy the encoder assumes the picture to be (N/10) when it
  measures the grain, on flat blocks only; with `film-grain-denoise=0` (the
  default) the denoised copy is only measured, the original is encoded,
  and a frame with no grain found gets none.
- **`xpsnr` takes the original first.** It weighs each difference by how
  busy the first picture is, so the first input must be the original (as
  FFmpeg's documentation says); `libvmaf` is the other way round. The
  calibration and the first comparisons had the copy first, which read 0.3
  to 0.8 dB low; `comparisonArgs` now puts the original first.
- **FFmpeg's `xpsnr` misreads 10-bit pictures** whose rows are not packed
  in memory: it takes the second input's stride to be its width. Any width
  that is not a multiple of 32 (every upright phone video) gave about 7 dB
  where 40 was right, and a file against itself was far from `inf`; a crop
  alone does not help, as it keeps the stride. `comparisonArgs` crops to a
  multiple of 32 and copies into fresh frames (`crop=…,copy`).
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
  calm and busy footage, so the hardest clip decides. The tool pairs frames
  by order: paired by time, as `xpsnr` does by itself, the piece's MKV
  (times rounded to milliseconds) and the MP4 encode disagree at 29.97
  frames a second, every other frame was compared with its neighbour, and
  the scores came out up to 19 dB too low.
- **Tone mapping** needs the `zscale` and `tonemap` filters, which not every
  build has; `Capabilities.hasFilter` is checked first.
- **Cancel kills FFmpeg.** `q` on stdin makes FFmpeg finish the file first,
  and a 4K AV1 encode then takes half a minute to empty its pipeline
  (SIGTERM nearly as long). The file is deleted anyway, so `cancel()` sends
  SIGKILL. The exit code cannot tell a cancelled run from a finished one, so
  the runner tracks cancellation itself. FFmpeg has exited and the `.part`
  file is gone only when the handle's `result` completes. An app that leaves
  in between abandons a running FFmpeg and the unfinished file, so closing
  the window goes through `QueueController.shutDown()` and
  `EstimateCache.stopMeasuring()`, which wait.
- **Expected size** of a quality-targeted encode cannot be calculated; the
  estimator encodes 3-second pieces spread over the video (picture only; the
  sound is calculated) and scales up. It is stopped when converting starts.
  Comparing the pieces makes it 40 to 80% slower (a film's six pieces: 12
  to 19 s); that time is kept out of the expected conversion time. The
  poorest piece decides: a film whose dark scenes lose detail is fine on
  average. Choosing a better quality adds a try per number: 38 s for that
  film (crf 35, then 20, both short: `belowTarget`), 8 to 25 s for camera
  and phone videos that need none. The per-frame scores come from a log
  file, whose path inside `-lavfi` is escaped twice (`escapeFilterPath`).
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
  connection to device"). `WindowCloseGuard` destroys once. On Linux the
  window must not really be destroyed: that shuts the Flutter engine down,
  and with NVIDIA's driver the app then crashes after `main()` returns, in
  the driver's exit handler (a core dump in `libnvidia-eglcore`, under
  `__run_exit_handlers`, on Wayland and X11). A blank Flutter app does not
  crash, because Flutter's own close quits and leaves the window in place;
  `window_manager` replaces that close with its own. The runner's
  `window_delete_event_cb` (`linux/runner/my_application.cc`) does what
  Flutter's does. It runs after the plugin's handler, which can still keep
  the window open.
- **App icon:** the drawing in `tool/make_icons.dart` is the source; it
  writes the macOS, Windows and Linux files and the copy the header shows
  (`assets/app_icon.png`), so change the drawing and never the files. On Linux the runner sets the window icon, which only X11
  desktops show. Wayland desktops take it from a desktop entry named after
  the application identifier and show a generic icon without one. There is
  no installer yet, so `tool/desktop_entry.dart` registers the entry on a
  developer's computer: run it again after the icon changes, and with
  `--remove` before changing the identifier. A window already open keeps the
  icon it opened with, so restart the app to see a change.
- **PATH on macOS:** an app opened from the Finder gets
  `/usr/bin:/bin:/usr/sbin:/sbin`, without Homebrew's folders, so
  `FfmpegLocator` looks in `/opt/homebrew/bin` and `/usr/local/bin` itself.
- **The header** (`home/widgets/app_header.dart`) is on every screen, the
  "engine missing" one included: the app's name and website on the left,
  the About, look and language buttons at the right, ending where the panel
  does. It takes the place of the margin above the panes, so the panel is
  20 px shorter than the window's margins alone would make it, and the
  roomier spacing starts at a 790 px window (`no_scrolling_test.dart`
  checks that height). CamCtrl, a camera remote from the same maker, is
  offered under Resolve's explanation only in the roomier panel: the
  smallest one has no line to spare.
- **Menus near the window's edge:** `MenuAnchor` opens a menu from its
  button's left side, and one that would run past the window is moved back
  only until it touches the edge, where its side and shadow are cut off. The
  buttons in the header's corner use `showMenuUnder`
  (`home/widgets/button_menu.dart`) instead, which lines the menu up with the
  button's right side. A test opens both at the smallest window.
- **File dialog on Linux:** GTK matches the filter's patterns
  case-sensitively, so `*.mov` hides a camera's `DSC_0001.MOV`.
  `dialogExtensions` (`media/video_files.dart`) gives each letter in both
  cases there (`[mM][oO][vV]`); Windows and macOS get plain extensions.
- **Resolve on Linux** (Blackmagic's codec list for 21.1): no AAC in either
  edition, no H.264/H.265 in the free edition. Checked in Studio 21.1.1:
  AC-3 does not play (silent from MOV and MP4, distorted from MKV), Opus
  plays only from MP4, and AVI does not import. With hardware decoding off
  (Preferences, Decode Options), Studio still decodes H.264, H.265 4:2:2,
  AV1 and VP9 on the processor: an NVIDIA card makes playback smooth, it
  is not what makes the picture appear. Details in the header of
  `resolve_linux.dart`.
- **Resolve shows a copied picture early** when the MOV's edit list holds an
  empty edit (the picture starts after the sound, as from MPEG-TS or MKV)
  followed by the B-frame delay: it applies the delay twice, up to two
  frames, out of sync with the sound. `-movflags +negative_cts_offsets`
  leaves no delay to double. Not for AVI sources, which have no
  presentation times: there it moves the picture by a second. Measured with
  a white frame and a beep at the same moment;
  `editListMediaTimes` (`test_media.dart`) guards it.
