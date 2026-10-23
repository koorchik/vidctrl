# Roadmap

## Done

- **Engine:** file inspection, per-file plans, FFmpeg runner with progress,
  cancel and pause, safe output handling, capability detection
  (encoders, working hardware encoders, accepted SVT-AV1 parameters).
- **Goals:** "Archive" (AV1 or HEVC, processor or graphics card, camera tags
  kept), "Edit in DaVinci Resolve" on Linux (Studio and free), "Save space"
  (AV1 up to 1080p for call recordings), "Get the sound", "Remove personal
  data" and "Change file type".
- **UI:** videos, settings and queue as separate parts; the queue starts by
  itself and can be paused, reordered and edited; the same video can be
  queued with different settings, and output names carry the settings;
  samples are an option and report the whole video's expected size; expected
  size and time before starting; video details for originals and results;
  "Compare with the original" for a finished result, in plain words with
  the VMAF and XPSNR scores beside; before converting, how close each video
  will look, measured on short pieces; "Archive" raises the quality of a
  video that needs it, marks one still short of looking the same for a
  look by eye (its hardest frame against the original's, at real size),
  and leaves alone one that would hardly shrink;
  keep-awake on Linux and macOS; closing the window asks first while
  converting, and FFmpeg is stopped before the app goes; "Show the command";
  technical names beside plain labels; English and Ukrainian with a
  switcher; two looks with a switcher, a warm light one and a dark
  professional one.
  Language, look, last goal and output folder are remembered. A newer
  release is looked for at the start and shown beside the website's
  address; "Check for updates…" in the About menu.
- **App icon** for the three platforms, drawn by `tool/make_icons.dart`.
- **CI:** analysis, tests, a quick check of FFmpeg and release builds for
  Linux, Windows and macOS; a version tag publishes a GitHub release with the
  three downloads.
- **FFmpeg inside:** each download carries a pinned FFmpeg 8.1
  (`tool/fetch_ffmpeg.sh`), VidCtrl's own build (`vidctrl-ffmpeg`), the
  same on every system, with its licence and a notice of where its source
  is, also shown in the app, which uses no other FFmpeg. A ready-made
  macOS build made blockier AV1 on Apple chips (its SVT-AV1 3.1.2).
  The macOS download is a disk image, signed and notarized when the Apple
  secrets are set (`tool/package_macos.sh`).
- **AI agents:** `vidctrl-client`, which comes beside the app, lets an agent
  or a script add videos to the open window, queue conversions and wait for
  them while the person watches, and "Use with an AI agent" in the header
  gives the text to paste into the agent.

## Next

1. **Finish the newer goals**
   - Remove personal data: show a report of what was removed, and offer
     neutral file names (a name can give away a place or a date).
   - Get the sound: choose which track, or all of them.
2. **Quality calibration.** "Archive" is matched with XPSNR on 4K clips from a
   Nikon camera, a phone and a slideshow. Still to do: footage from other
   cameras (Sony, Canon), matching the numbers with VMAF too (every shipped
   FFmpeg has `libvmaf`; the calibration tool reads only XPSNR so far), Intel
   and AMD graphics, Apple's beyond the M1, and the other goals' quality
   levels. "Save space" is set on a 4K family video and a Google Meet
   recording; screen sharing with small text and phone footage are not
   measured yet. Its one number leaves already squeezed recordings, such as
   calls, only about a tenth smaller, where a higher one would still look the
   same. A fixed number cannot suit both calm and busy footage; choosing it
   per video from a measured sample would, as "Archive" now does upwards
   (lowering its number for calm footage is not done: it stays the
   poorest allowed).
3. **Check in Resolve.** Studio 21.1.1 on Linux is checked: every codec the
   goal keeps, every sound format, sync after a rewrap, and the outputs of
   each variant, also with hardware decoding off (the findings are at the
   top of `resolve_linux.dart`). Still to do: the free edition, and how
   smoothly H.265 4:2:2 plays without a recent NVIDIA card.
4. **Use the whole machine.** One encode often leaves most cores idle.
   Run several conversions at once according to CPU, memory and graphics-card
   capacity; lower process priority so the desktop stays responsive; consider
   splitting a single long video into chunks encoded in parallel.
5. **Disk space.** Warn before starting when the expected output does not fit.
6. **Comfort.** Settings (speed, output naming), finish notification,
   taskbar progress.
7. **Ship.**
   - Set the Apple secrets and try the notarized disk image on a Mac
     (Apple Silicon and Intel).
   - Windows: keep-awake, pause, and ending FFmpeg when the app ends.
     Stopping a conversion part-way fails there: of the conversion tests,
     run once in CI on 2026-10-03, the three that cancel, shut down or stop
     a measurement did not pass.
   - Installers (AppImage/deb, Windows installer) and signing on Windows.
   - Linux: a desktop entry named after the application identifier, with the
     icons installed beside it. Wayland desktops take the window icon from
     there; until then `tool/desktop_entry.dart` registers one by hand.
   - Make the conversion tests pass on Windows (they pass on macOS). CI runs
     only the quick FFmpeg check, so they have to be run on a Windows
     machine.

## Later

Automatic quality per video for "Save space" too, "fit into N MB", user-defined goals, lossless
trimming, an in-app before/after comparison for samples, watch folders,
updating itself in place.

## Open decisions

- Licence for the app code.
