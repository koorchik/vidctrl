# VidCtrl

A desktop app that converts batches of videos for a few everyday goals, built
for people who do not want to learn what a codec is. It is a friendly front end
for [FFmpeg](https://ffmpeg.org/).

Drop videos in, pick what you want, press **Add to queue**. Converting starts
by itself.

![The app: videos and the queue on the left, what to do with them on the right](docs/screenshots/cozy.png)

It comes in two looks. The one above is the one it starts with; this is the
other:

![The same screen in the dark professional look](docs/screenshots/pro.png)

## What it does today

- **For the archive.** Turns camera videos into a master copy for keeping:
  a fraction of the size, looking the same as the original. One quality, the
  highest; the defaults need no thought. Shooting dates, place, timecode and
  the camera's make and model are kept. Two choices, each saying what it
  trades away:
  - *Format:* *Smallest file* (AV1, the default) or *Works everywhere*
    (HEVC, a larger file that also plays on older iPhones, Macs and TVs).
    Without AV1 in the installed FFmpeg, HEVC is used.
  - *Speed:* *Thorough* (the processor) or *Fast* (the graphics card: much
    quicker, a larger file; offered only when a working one is found).

  Sound is made compact too: the lossless sound of an editor export (FLAC,
  PCM) becomes AAC at 320 kbit/s, which is a small part of a high-quality
  video. Sound that is already AAC is kept untouched.
- **Edit in DaVinci Resolve (Linux).** Makes camera and screen recordings open
  with both picture and sound in Resolve on Linux, for Resolve Studio and for
  the free edition.
- **Send to a phone.** A small file that plays on any phone and in messengers
  such as Telegram. HDR footage is adjusted to look right on ordinary screens.
- **Get the sound.** Saves the sound track as its own file, untouched by
  default, or as MP3, M4A, WAV or FLAC.
- **Remove personal data.** Strips place, date, camera and author
  information before sharing. Quick (picture and sound copied untouched) or
  thorough (rebuilt from scratch).
- **Change file type.** Moves a video into MP4, MKV or MOV in seconds, without
  re-encoding the picture.

It does the least work that reaches the goal. A file that is already fine is
left alone; a file that only needs its sound converted is done in seconds with
the picture copied untouched; only what must be re-encoded is re-encoded.

### How it works

The window has three parts:

- **Your videos** (top left): the files you added, each listed once. Newly
  added videos are selected, so dropping videos and pressing Add to queue is
  all it takes.
- **What to do** (right): the goal and its options, whole video or a
  10-second sample, and where to save. It applies to the selected videos.
  **Add to queue** queues them; **Add all** queues every video.
- **Queue** (bottom left): starts by itself, one conversion at a time. Pause,
  reorder, cancel or retry at any time.

Change the settings and press Add to queue again to get the same video in
another form: each job keeps the settings it was added with, and output names
carry them (`clip_av1-crf35.mp4`, `clip_hevc-crf24.mp4`, `clip_phone-1080p.mp4`).

Also:

- **Samples:** choose "10-second sample" to make a short piece with exactly
  the chosen settings, from the start or the middle. Samples go to a
  `Samples` folder, and their row shows the sample's size and the expected
  size of the whole video. "Convert whole video" then queues the real thing.
- **Expected size before starting:** for each selected video and in total,
  with the time it will take. Where the size depends on the footage, short
  pieces are encoded in the background with the exact settings and scaled up.
- Progress, time left and expected size while converting.
- **Video details:** a frame of the video and its key facts, then every
  detail (codecs, bitrates, colour, HDR, sound tracks, timecode), all
  metadata tags with the personal ones marked, and FFmpeg's full report. For
  the original and, once converted, for the result.
- **Show the command:** the exact FFmpeg command for any video or job, on one
  line or explained option by option, ready to paste into a terminal.
- The computer is kept awake while converting (Linux and macOS).
- Originals are never modified or overwritten. Unfinished outputs are removed.
- Plain words first, with the technical detail beside them in smaller type
  ("Smallest file" with "AV1" underneath).
- English and Ukrainian, switchable in the app.
- Two looks, switchable in the app: a warm, light, rounded one and a dark,
  flat, professional one.
- The language, look, last goal and output folder are remembered.

## Status

Early but working on Linux. Not done yet:

- The macOS download is signed and notarized only once the Apple
  credentials are in the repository's secrets (see Releases).
- Windows and macOS builds compile in CI but have not been tried on real
  machines. On macOS the conversion tests pass in CI. On Windows, keeping
  the computer awake and pausing are not implemented, and the tests of
  stopping a conversion part-way fail.
- Only one video is converted at a time.
- "For the archive" is set so that every format and encoder reaches an
  XPSNR of at least 42 dB, reported as visually lossless, on the hardest of
  the 4K clips measured (from a Nikon camera, a phone and a slideshow).
  Other cameras, and Intel, AMD and Apple graphics, are not measured yet.
  The other goals' quality levels are starting values.

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Requirements

- The released app brings its own FFmpeg (8.1, with `ffprobe`); nothing else
  needs installing. Someone who wants another FFmpeg can choose its folder
  in the app: About VidCtrl (the "i" button), "Use FFmpeg from a folder…".
- To develop: FFmpeg 8 or newer with `ffprobe`, built with `libx265`,
  `libsvtav1`, `prores_ks` and `dnxhd`, either on the `PATH` (Linux
  distribution packages and Homebrew have these) or the pinned one that
  `tool/fetch_ffmpeg.sh linux|windows|macos` puts in `third_party/ffmpeg/`,
  which a build then includes. On Windows a "full" build is needed: the
  "essentials" builds lack `libsvtav1`.
- To build: [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or
  newer with desktop support. On Linux also `ninja-build` and `libgtk-3-dev`.

## Run and build

```sh
flutter pub get
flutter run -d linux          # or: -d windows, -d macos
flutter build linux --release # result in build/linux/x64/release/bundle
```

## Tests

```sh
flutter test --exclude-tags "ffmpeg || screenshots"  # fast: logic and UI
flutter test --tags ffmpeg                           # real conversions, needs FFmpeg
flutter test --tags ffmpeg_check                     # only the quick check of the installed FFmpeg
flutter test --tags screenshots                      # renders the screen to build/screenshots/
flutter test tool/make_screenshots.dart              # redraws the pictures in this README
```

The conversion tests generate their own small clips; no footage is stored in
the repository. They take minutes of encoding, so CI runs only the quick
check: FFmpeg is found, has the encoders the app needs, and converts one
short clip.

## Releases

Pushing a version tag publishes a release on GitHub with the app for Linux,
Windows and macOS, once all three have passed their checks and built:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The app is given the tag's version, and the files are named after it
(`vidctrl-0.2.0-linux-x64.tar.gz`, `vidctrl-0.2.0-macos.dmg`). A tag with a
hyphen, such as `v0.2.0-beta.1`, is published as a pre-release. The notes
explain how to get the app going and list the commits since the release
before (`tool/release_notes.sh`).

Each download has FFmpeg inside, fetched by `tool/fetch_ffmpeg.sh`. The
macOS one is a disk image with the app signed with a Developer ID and
notarized by Apple (`tool/package_macos.sh`), so that it opens without a
warning. That takes these repository secrets, and a version tag fails
without them:

| Secret | What it is |
|---|---|
| `MACOS_CERT_P12` | The "Developer ID Application" certificate with its private key, exported as .p12, in base64 |
| `MACOS_CERT_PASSWORD` | The password of that .p12 |
| `NOTARY_KEY_P8` | An App Store Connect API key (the .p8 file's text), for `notarytool` |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown with App Store Connect's API keys |

## Command-line tool for development

The conversion engine can be driven without the UI:

```sh
dart run tool/convert.dart --list                 # goals and their options
dart run tool/convert.dart --caps                 # what this FFmpeg and machine can do
dart run tool/convert.dart archive.master clip.mov # convert one file
dart run tool/convert.dart resolve.studio clip.mp4 --dry-run   # only show the plan and command
dart run tool/convert.dart archive.master clip.mov --sample 30:10 --opt codec=hevc
```

## How it is organised

```
lib/core/   the conversion engine, plain Dart with no UI code
  media/      reading what a file contains (ffprobe)
  scenarios/  the goals: each looks at a file and plans the least work
  ffmpeg/     finding FFmpeg, what it can do, building and running commands
  queue/      running one conversion safely (temporary file, rename, cleanup)
  estimate/   speed, time left, expected size
lib/app/    the Flutter UI: sources/ (videos), recipe/ (what to do),
            queue/, estimates/, home/ (the screen)
lib/l10n/   texts in English and Ukrainian
tool/       developer tools
test/       tests, mirroring lib/
```

Adding a goal means one file in `lib/core/scenarios/`, one line in
`registry.dart`, and its texts; see [CLAUDE.md](CLAUDE.md).

## Licence

Not chosen yet for the app's own code. FFmpeg comes with the app as
separate programs, unmodified builds under the GNU GPL version 3;
`assets/licenses/ffmpeg.txt` says whose builds they are and where their
source code is, and the app shows it under About VidCtrl → Licences. The
bundled fonts are Roboto (Apache License 2.0) and JetBrains Mono (SIL Open
Font License); their licence texts are in `assets/fonts/`.
