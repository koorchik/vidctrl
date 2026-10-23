# Controlling the running app from the command line

Status: built on the agent-control branch (2026-10-23); macOS hardened-runtime check (Task 0) open.

## Why

The owner wants to hand VidCtrl work to an AI agent (Claude Code or any
other) or a script: "find the big videos on this computer, put them in the
queue, tell me when they are done". The agent does the finding itself
(`find`, `du`); what it lacks is a way to reach the app. The owner keeps
watching the window: videos appear in the list, jobs appear in the queue and
convert, exactly as if they had been dropped in by hand.

A command line was chosen over an MCP server: it serves agents, shell
scripts and people alike, and with the starting prompt and the manual an
agent needs nothing more, so there is no MCP server (see "Non-goals"). The
owner liked working with DaVinci Resolve
through an MCP server and wants the same feeling: the agent drives, the
window shows.

## Goals

- A command, `vidctrl-client` (a client of the running app), that
  talks to the **running window** and changes what the window shows. If no
  window is running, it opens one and then talks to it.
- It can do what the window can do with videos and the queue, by the same
  code paths, and nothing more: add videos, list them with what the list
  shows (expected size, how close the result will look), queue them with a
  goal and its options, pause, resume, cancel, remove, retry, reorder,
  "Convert anyway", "Convert the whole video" from a sample, "Compare with
  the original", "Video details", "Show the command".
- It can wait: block until a job, or the whole queue, is finished, and exit
  with a code that says how it went. It can also stream events (job started,
  progress, finished, failed) so an agent can report each result while the
  rest still converts.
- Output for people by default, `--json` on every command for programs.

## Non-goals

- **No headless mode.** The command never converts by itself and never
  starts a second, hidden copy of the engine. All work happens in the
  window, where the owner sees it.
- **No FFmpeg arguments, no quality numbers.** Goals and options are the
  ones the panel offers, by their ids (`archive`, `speed=fast`). A preset's
  crf, encoder flags and the like cannot be set; that is what makes the
  quality guarantees hold.
- **No control of the panel.** The command does not change the goal shown
  in "What to do", the selection's goal or the remembered settings; a job
  queued from the command line carries its own recipe, like every job.
- **No file search.** The agent finds the files and passes paths.
- **No closing the window** (the owner saw no need), no settings, look or
  language changes.
- **No MCP server.** The owner decided against it: the starting prompt and
  `vidctrl-client` give an agent everything, and MCP would add nothing.

## Anti-goals

What would make this a failure even if it worked:

- The command and the window disagree: something queued from the command
  line behaves differently from the same thing done with the mouse, or the
  window does not show it. The command must go through the same notifiers
  (`SourcesController`, `QueueController`, `EstimateCache`,
  `QualityController`) as the buttons, never around them.
- Anyone but the person logged in can reach it: another user on the
  machine, another machine, a web page in the browser.
- An agent can make the app lose work or a file the UI could not: the
  command adds no destructive power beyond the window's (originals are
  never overwritten, `.part` files and renames stay the executor's).
- **Anything that deletes or suggests deleting a file on disk.** No command
  deletes a file, original or result. Nothing the command prints, the manual
  included, tells or hints to delete the originals: no "before deleting the
  original", no "the original can go now", no recipe that cleans up. An
  agent reading it must never come away thinking that is its job.

## Decided with the owner

- The agent never clicks; the window only reflects state.
- Same abilities as the UI, no detailed compression parameters.
- Cancelling the running conversion and removing jobs need **no
  confirmation** in the window, as they need none there now.
- Closing the window from the command line: not offered.
- The name is **`vidctrl-client`**: it is a client of the running app, not
  a command-line version of it.
- **Easy to start:** a button in the window gives a prompt to copy into any
  agent, with where `vidctrl-client` is, to run `manual` first and how to
  wait for the conversions (see "Use with an AI agent").
- A command prints the **full manual** for an agent (`vidctrl-client
  manual`, see "The manual").
- **No instructions to delete originals, anywhere.** "Remove" means taking a
  video off the list or a job out of the queue, as in the window; the file
  on disk stays. Every removing command and its manual entry says so.
- Monitoring and waiting are core, not extras: "wait until it's converted,
  then get the result", or get each result as it finishes.

## Constraints

- **Where the caller runs:** the same user, on the same desktop session as
  the window, not sandboxed: an ordinary terminal, a script, or Claude Code
  as the owner runs it (its Bash sandbox is off). The command needs the
  app's loopback network, its per-user folder and, to start the app, the
  desktop. A sandboxed agent (Claude Code's sandbox gives a process its own
  network), WSL on Windows, SSH and containers are not served; `docs/CLIENT.md`
  says to exempt `vidctrl-client` from a sandbox.
- **Packaging:** it must work from today's zips and disk image, and from
  package managers that link the program onto the `PATH` (AUR, the Homebrew
  tap, Scoop, winget, all planned soon after launch): the command finds the
  app through its own resolved path (`Platform.resolvedExecutable`, which
  follows links), so a link in `/usr/bin` or a Homebrew `binary` still leads
  into the bundle. AppImage and Flathub come later and need their own
  answer (AppImage mounts somewhere new each launch; Flatpak has its own
  `$XDG_RUNTIME_DIR` and cannot start the host app). Keep finding the app
  and the endpoint behind one small interface so those can be added.

## Shape

Three pieces:

1. **Protocol** (`lib/core/control/`, plain Dart, no Flutter): the message
   types, method and event names, error codes, where the endpoint file
   lives, and a small client. Shared by the app and the command, and
   testable without widgets, like the rest of `lib/core`.
2. **Control server** (`lib/app/control/`): started by the app once at
   launch, inside the same isolate, holding a `Ref` (or the
   `ProviderContainer`). Each request becomes a call on a notifier; each
   event is derived from `ref.listen` on `sourcesProvider`,
   `queueProvider`, `qualityProvider` and `estimateCacheProvider`. Being on
   the UI isolate, its calls interleave with the mouse's in order, with no
   locking.
3. **The command** (`bin/vidctrl_client.dart`, built with `dart build cli`,
   importing only `lib/core`): parses arguments, finds or starts the app,
   sends one request (or subscribes), prints the answer, exits with a code.

### Transport

- Loopback TCP on `127.0.0.1`, a port the system picks, newline-delimited
  JSON in the shape of JSON-RPC 2.0 (requests with ids, responses,
  notifications for events). The same on Linux, Windows and macOS; Dart's
  Unix domain sockets do not cover Windows, and one transport means one set
  of tests.
- **Endpoint file** written by the app at start, removed when it closes:
  `{ "port", "token", "pid", "version", "protocol" }`. Readable only by the
  user (mode 0600 on Linux and macOS; on Windows the per-user folder is
  enough). Location, computed in `lib/core/control/` so the command needs no
  `path_provider`: Linux `$XDG_RUNTIME_DIR/vidctrl/control.json` (falling
  back to `~/.cache/vidctrl/`), macOS `~/Library/Application
  Support/app.camctrl.vidctrl/control.json`, Windows
  `%LOCALAPPDATA%\VidCtrl\control.json`.
- The first message on a connection must be `hello` with the token and the
  protocol version, or the server closes it. A browser can post to a
  loopback port but cannot read the file, so it cannot pass the token; a
  first line that is not JSON closes the connection too.
- A stale file (missing or damaged, the port refuses, or no such process)
  means "not running". A window whose port accepts and whose process runs
  but that refuses `hello` or does not answer it in time is not stale: the
  client exits 2 and starts no other window, and a newcomer does not take
  over.

### One window

The Linux runner is `G_APPLICATION_NON_UNIQUE`, so two windows can run.
The first one to start owns the endpoint; a later one sees a live endpoint
and does not serve (it still works as a window). If the owner's file is
stale, the newcomer takes over.

### Starting the app

When there is no live endpoint, any command except `status` (which just says
"not running") starts the app detached and waits for the server to answer
`ready`, up to 30 s (the capability probe takes a few seconds), showing
"Starting VidCtrl…" on stderr. Where the app is:

- next to the command in a release (Linux bundle `vidctrl`, Windows
  `vidctrl.exe`, macOS the enclosing `VidCtrl.app`, opened with `open` so it
  behaves like a Finder launch);
- `VIDCTRL_APP=<path>` overrides it, for development
  (`build/linux/x64/debug/bundle/vidctrl`). With `flutter run` already up,
  the command simply finds its endpoint.
- `--no-start` turns starting off: exit code 2 when not running.

The server answers before FFmpeg is found; `status` says `starting`,
`ready` or `ffmpeg-missing`, and every other method waits for `ready`
(or fails with `ffmpeg-missing`, as the window shows its "engine missing"
screen).

### Closing

Closing the window is unchanged (it asks while converting). Its shutdown
path (`WindowCloseGuard` → `QueueController.shutDown()`,
`EstimateCache.stopMeasuring()`) also stops the server: it sends an
`APP_CLOSING` event to subscribers, closes connections and deletes the
endpoint file. A `wait` or `events` that was running exits with code 4.

## Commands

Ids: videos and jobs carry the session's integer ids (`SourceVideo.id`,
`QueueJob.id`); they are not stable across restarts, and the queue is not
kept across restarts either. Wherever a video id is accepted, a path is
too.

Goals are named by preset id (`archive.master`), or by scenario id
(`archive`) where the scenario has one preset. Options by the preset's
option ids and choice ids (`--opt speed=fast`), exactly what
`tool/convert.dart --list` prints today. An unknown goal, option or choice
is an error that lists the valid ones.

| Command | What the window does | Notes |
|---|---|---|
| `status` | — | running or not, version, FFmpeg state, queue summary (running, paused, counts per status) |
| `goals` | the goal tiles and their rows | ids, English title and subtitle from the ARB, options with choices and the default, the hint (`choiceHint`) per choice |
| `add <paths…>` | dropping files | same expansion of folders as a drop (`expandDroppedPaths`), same "each path once"; waits until each is probed (`--no-wait` skips); prints each video's id and whether it is readable |
| `videos [--goal g] [--opt …]` | the video list | path, size, duration, resolution, codecs, HDR; with a goal: what the plan would be (skip, remux, encode, unsupported, kept as is) and the expected size and closeness if known |
| `estimate <videos…> --goal g [--opt …]` | selecting videos, which measures them | runs `EstimateCache.measure` only while the queue is idle, as the preview does; the result lands in the shared cache, so the list shows it too |
| `details <video\|job> [--raw]` | "Video details" | `--raw` gives the whole ffprobe report |
| `remove <videos…>` | removing from the list | off the list only; the file stays on disk, and the output says so |
| `queue` | the queue pane | each job: id, video, goal and options, sample or not, status, progress and time left, "checking the quality… try N", output path, chosen quality and outcome |
| `queue add <videos…> [--goal g] [--opt k=v]… [--sample start\|middle] [--out next\|<folder>] [--subfolder Name]` | Add to queue | paths not in the list yet are added first; an identical pending job is reported as already queued, not added; without `--goal` the panel's current goal and options are used (like the button) and the output says which; without `--sample` the whole video, whatever the panel's sample choice; without `--out` the panel's output setting (remembered, maybe a custom folder) |
| `queue remove <jobs…>`, `queue move <job> <position>`, `queue retry <job>`, `queue clear-finished` | the job's ⋯ menu, dragging, "Clear finished" | `remove` and `clear-finished` take jobs out of the queue; finished results stay on disk |
| `pause`, `resume` | the pause button | explicit, not a toggle, so a script can repeat them |
| `cancel [job]` | cancel | the running one by default |
| `queue convert-anyway <job>`, `queue convert-whole <job>` | "Convert anyway", "Convert the whole video" | |
| `job <job>` | a finished job's row and (i) window | result path and size, chosen quality, outcome (`BELOW_TARGET` gives the `-check` name and says "look at it"), poorest piece's scores; `--command` adds "Show the command" (`forDisplay: true`) |
| `compare <job> [--no-wait]` | "Compare with the original" | waits for the result by default; words from `closenessOf` plus VMAF and XPSNR |
| `wait [jobs…] [--timeout s]` | — | see below |
| `events [--since-now]` | — | see below |

### wait

Without ids it waits until no job is pending (waiting, running or paused);
with ids, until those are. A paused queue keeps it waiting (the owner may
resume) and it says so once on stderr. It prints each job's outcome.

Which jobs count: those pending when the wait starts, plus any added while
it waits (by the command or the mouse). Jobs already finished, failed or
cancelled before it started do not count, so one old failure does not make
every later `wait` return 1. A counted job that is removed (by "remove" or
"Clear finished") is reported as removed and does not count as a failure;
one cancelled during the wait does. With nothing pending at the start it
returns 0 at once.

Exit codes, shared by every command:

| Code | Meaning |
|---|---|
| 0 | done (done or skipped, `needsALook` included: it is flagged in the output) |
| 1 | at least one job failed or was cancelled |
| 2 | the app is not running and could not be started, or the endpoint refused |
| 3 | `--timeout` passed |
| 4 | the app closed while waiting |
| 5 | bad arguments (unknown goal, option, id) |
| 6 | FFmpeg missing |

### events

JSON lines on stdout until the app closes, each `{ "event", "time", … }`,
the event named by its code:
`VIDEO_ADDED`, `VIDEO_READY`, `VIDEO_UNREADABLE`, `VIDEO_REMOVED`,
`JOB_ADDED`, `JOB_CHECKING` (attempt N), `JOB_STARTED`, `JOB_PROGRESS` (at
most once a second per job), `JOB_FINISHED` (status, output path, size,
quality outcome), `JOB_REMOVED`, `QUEUE_PAUSED`, `QUEUE_RESUMED`,
`QUEUE_IDLE`, `COMPARE_FINISHED`, `APP_CLOSING`. Without `--since-now` it
first prints the current state as `SNAPSHOT`, so a reader that starts late
misses nothing. This is what an agent runs in the background to say "the
first three are done" while the rest converts.

### Words

Plain words lead in the command's text output too ("Looks the same", "Kept
as it is: converting would hardly make it smaller"), with the technical
names beside, in English. `--json` is for programs (the owner's call): it
carries ids, numbers, paths and, for every value that is one of a few, a
code in SCREAMING_SNAKE_CASE, and no words (no `...Text` fields; only an
error's `message`, beside its `code`, is for people). Goal, option and
choice ids stay as `--goal` and `--opt` take them (`archive.master`,
`speed=fast`), so input and output share one spelling. The codes are
listed once, in `lib/core/control/codes.dart`; a Dart enum's value becomes
its code by `codeOf` (`audioOnly` is `AUDIO_ONLY`), and the manual
explains each one:

- Job status: `WAITING`, `RUNNING`, `PAUSED`, `DONE`, `SKIPPED`,
  `FAILED`, `CANCELLED`; how a job ended (`wait`) may also be `REMOVED`.
- Video status: `PROBING`, `READY`, `UNREADABLE`.
- Plan: `SKIP`, `REMUX`, `AUDIO_ONLY`, `ENCODE`, `UNSUPPORTED`,
  `KEPT_AS_IS`.
- Closeness: `SAME`, `VERY_CLOSE`, `DIFFERS`.
- Quality outcome: `STANDARD`, `RAISED`, `BELOW_TARGET`, `NOT_WORTH_IT`.
- Window state: `STARTING`, `READY`, `FFMPEG_MISSING`.
- Adding a path, and why `queue add` skipped one: `ADDED`, `KNOWN`,
  `NOT_FOUND`, `UNREADABLE`.
- Sample: `START`, `MIDDLE` (the flag stays `--sample start|middle`).
- Comparison: `MEASURED`, `FAILED`.
- Events: as listed under events.
- Errors (`data.kind` on the wire, `{"error": {"code", "message"}}` from
  the client): `BAD_ARGUMENT`, `NOT_FOUND`, `BUSY`, `UNKNOWN_METHOD`,
  `FFMPEG_MISSING`, `UNAUTHORIZED`, `NOT_RUNNING`, `APP_CLOSED`, and the
  client's own `TIMEOUT` and `UNEXPECTED`.

### The manual

`vidctrl-client manual` prints, in one go, everything an agent needs to use
the app without having seen it: the agent runs it first and is ready. The
owner asked for this. It is Markdown on stdout, works without the app
running and starts nothing.

- **What the app is and how to think about it:** videos list, goals, queue,
  jobs as snapshots; the window shows everything the command does; nothing
  converts without the window; originals are never touched; output names
  carry the settings; samples go to `Samples/`.
- **Every command:** what it does, its arguments, an example, what it prints
  with and without `--json` (the JSON fields, with types), and its errors.
- **Every goal:** id, what it is for in plain words, its options and
  choices with the default and what each trades away (`choiceHint`), which
  videos it skips or leaves as they are. Ids and choices come from
  `registry.dart` at build time, so the list cannot fall behind; the words
  come from the English ARB.
- **What the outcomes mean**, so an agent can tell the owner: done,
  skipped, kept as it is (and "Convert anyway"), `BELOW_TARGET` (the `-check`
  name: tell the owner to look at it by eye), failed, cancelled.
- **What the app never does**, said plainly near the top: it deletes no file;
  "remove" takes a video off the list or a job out of the queue, and the
  file on disk stays.
- **Exit codes, `wait` rules and the event list.**
- **Recipes**, worked end to end: "queue every video over 2 GB in ~/Videos
  and tell me when done" (with `find`, `queue add`, `wait`); "report each
  file as it finishes" (`events`); "make samples first, compare, then
  convert the whole"; "what would Archive do with these, and how big?"
  (`videos --goal`, `estimate`).
- **Limits:** same user and desktop, no sandbox, no FFmpeg parameters, no
  closing the window.

`vidctrl-client --help` stays a short list of commands and ends with "Run
`vidctrl-client manual` for the full guide"; `help <command>` prints that
command's part of the manual. `manual --json` gives the same as data
(commands, arguments, goals, exit codes) for a program that builds on
it.

The manual's text lives in one place in `lib/core/control/`, built into the
command, and `docs/CLIENT.md` is generated from it (a test fails when they
differ). Tests also check that every command the parser knows and every
goal and option in `registry.dart` appear in it, so a new goal or command
cannot ship undocumented, and that neither the manual nor any text the
command prints speaks of deleting a file (a list of words, like the
technical terms in `home_screen_test.dart`). The window's own
`qualityCheckByEye` ("Check by eye before deleting the original") is not
reused: the command words `BELOW_TARGET` as "worth a look by eye".

## What changes in the window

Showing what the command did needs nothing new: the window already renders
the notifiers' state. One choice follows from "like a drop": videos added by
`add` become the selection, as dropped ones do, so the panel's preview
measures them (see the calls below).

### "Use with an AI agent"

The owner asked for this: a person who has never heard of `vidctrl-client`
must find it in the window and get an agent working in one paste.

- **Where:** a button in the header, beside About, look and language, with
  an icon and the tooltip "Use with an AI agent". It is on every screen
  except "engine missing", where there is nothing for an agent to do. Also
  an item of the same name in the About menu.
- **It opens a small window** (like "More options…"), plain words first:
  one or two sentences on what it is for ("Let an AI agent such as Claude
  add videos and start conversions for you. You keep watching here."), then
  the prompt in a box with **Copy** beside it, and Close; nothing else (the
  owner had the program's location and the lines on kinds of agent taken
  out: the path is in the prompt). Nothing here changes a setting; it only
  copies text.
- **The prompt** is filled in at run time with the real, absolute path of
  `vidctrl-client` beside the running app (from `Platform.resolvedExecutable`;
  this lands in the person's clipboard only, never in a file). In the
  owner's words it says only what the tool is and to read the manual:
  - VidCtrl is open on this computer and the person watches its window;
    this program controls it (the path, quoted).
  - Run `"<path>" manual` first; it explains every command, the goals and
    what the results mean. Read output with `--json`.
  - On Windows, with a quoted path: PowerShell needs `&` before it.
  Everything else is in the manual's quick start, before its commands:
  finding videos is the agent's job; conversions run one at a time and can
  take hours, so run `wait` in the background (or follow `events`) and tell
  the person what came of each; never delete, move or rename any file, and
  "remove" only takes a video off the list or a job out of the queue. So
  the prompt cannot go out of date: what changes with a release is in the
  manual, which the agent reads from the same program.
- **Language:** the window's words and the prompt follow the app's
  language (the prompt's texts are in the ARB files, with the path as a
  placeholder; the English one is the client's quick start). Command
  names, `manual` and `--json` stay as they are; the manual and the
  program's answers are in English.
- **The program is looked for each time the window opens**, so one built
  while the app runs is found without a restart.
- **When the program is missing** (a development build without it): the
  window says so and gives the exact command that builds it beside the
  running app, `tool/build_client.sh <the app's folder>` (on macOS
  `Contents/MacOS`), in a fixed-width box with its own Copy, then says to
  open the window again; Copy for the prompt is disabled.
- **Discoverability elsewhere:** the README's features and a short section
  "Use with an AI agent" showing the same prompt; `vidctrl-client` with no
  arguments prints the same quick start as the prompt and points to
  `manual`; the manual opens with that quick start too.
- **UI rules hold:** texts in both ARB files; "AI agent" goes
  through `TechnicalText` where they are technical names on the main
  screen; the header still ends where the panel does at the smallest window
  (`no_scrolling_test.dart`, the header test); both looks; a screenshot of
  the new window per look. A test checks that the prompt contains the path,
  `manual` and `--json`, in both languages, and nothing about deleting
  (the same word list as the manual's); another that the manual's top
  holds `wait` and the rule about files.

## Shipping

- The release workflow compiles the command on each system
  (`tool/build_client.sh`, which runs `dart build cli --target
  bin/vidctrl_client.dart`) and puts it beside the app: Linux in the bundle
  beside `vidctrl`, Windows beside `vidctrl.exe`, macOS in
  `Contents/MacOS/`. CI checks it is there and runs `--help`, as it checks
  FFmpeg. `dart compile exe` cannot be used: it refuses a package whose
  dependencies have build hooks, and the app's `path_provider` brings
  `objective_c`, which has one. `dart build cli` runs the hooks and writes
  `bundle/bin/vidctrl_client` with `bundle/lib/` for the libraries they
  make. The only one is `objective_c.dylib`, made on macOS and loaded only
  by Objective-C interop, which the client (importing only `lib/core/`)
  never calls; so the program alone is copied, and the script stops if
  `lib/` ever holds anything else.
- **macOS signing.** `dart build cli` writes a native Mach-O (the Dart
  runtime with the compiled program inside, made so that `codesign` accepts
  it, signed ad hoc by the compiler). `tool/package_macos.sh` re-signs it
  like `ffmpeg` and `ffprobe`: Developer ID, `--options runtime`,
  `--timestamp`, before the app itself (inside out). It is then part of the
  app's notarization and stapled ticket, so a notarized download runs it
  from a terminal with no warning. Without the Apple secrets everything is
  signed ad hoc, as now, and the release notes' way of opening the app
  (removing the quarantine from the whole `.app`) covers the client too.
  **Not yet known:** whether a Dart program runs under the hardened runtime
  with no entitlements (one report on Apple's forums of an AOT binary in an
  app bundle failing there). So a spike on a Mac (the plan's Task 0) settles
  it: the client as `tool/build_client.sh` builds it, signed with
  `--options runtime`, run from
  `Contents/MacOS/`, notarized; if it needs an entitlement, the client gets
  its own entitlements file with only that.
- **Windows:** the client is unsigned like the app for now; started from a
  terminal or by an agent it is not stopped by SmartScreen, which checks
  programs opened from Explorer. Signing on Windows, already on the
  roadmap, signs both.
- Reaching it from a terminal: until there are installers, the README says
  how to link it onto the `PATH` (`ln -s …/vidctrl-client ~/.local/bin/`;
  macOS `/usr/local/bin`). An installer can do that later.
- `docs/CLIENT.md` is the manual's text (see "The manual"), so it can be read on
  the web too.

## Testing

- `lib/core/control/`: protocol encoding, endpoint file reading, stale
  detection, client against a fake server.
- Control server: plain `ProviderContainer` tests with `FakeEnvironment`
  (not widget tests: real sockets escape the fake clock), over a real
  loopback socket. Each command is checked against what the same button
  does: e.g. `queue add` and `addSelected()` produce equal jobs; a duplicate
  is refused both ways; `cancel` and the cancel button leave the same state.
- Events: a fake job finishing produces `JOB_FINISHED`, a closing container
  produces `APP_CLOSING`.
- The command: argument parsing and exit codes against a fake server; one
  test that starts it as a process (`dart run bin/vidctrl_client.dart`)
  against a server in the test.
- A widget test that an `add` from the server shows in the video list and a
  `queue add` in the queue pane.

## Order of work

0. The macOS signing spike (see "Shipping"): it decides nothing else, but
   a surprise there is cheapest found first.
1. Protocol, endpoint file, server with `status`, `goals`, `add`, `videos`,
   `queue`, `queue add`, `wait`, `events`, and the `manual` for them.
   Usable by an agent end to end.
2. The rest of the queue operations, `job`, `compare`, `details`,
   `estimate`.
3. Shipping: compile and bundle on three systems, signing, CI check,
   `docs/CLIENT.md` generated from the manual, and the "Use with an AI
   agent" window (it needs the program beside the app to show a real path).

## Later

- A mark in the queue for jobs that came from the command line, if
  watching shows it is wanted.
- A finish notification of the desktop's own, already on the roadmap
  ("Comfort"), would serve both the mouse and the command.

## Calls made by the designer

Not discussed with the owner; each can be changed without changing the rest.

- **A separate console program**, not a mode of the window's: a Windows GUI
  program cannot print to a terminal or be waited for there.
- **"Use with an AI agent" in the header and the About menu**, a small
  window with the prompt, in the app's language.
- **TCP on loopback with a token**, not Unix sockets and named pipes: one
  transport on three systems.
- **`queue add` without `--goal` uses the panel's goal**, like the button;
  a script should pass `--goal`, and the output always names it.
- **`queue add` without `--sample` converts the whole video**, even when
  the panel is set to samples: an agent's plain `queue add` must not
  quietly make 10-second pieces. Without `--out` it writes where the panel
  would, as the button does.
- **`wait` counts** jobs pending at its start and those added during it;
  earlier failures and removed jobs do not make it fail.
- **Same user, same desktop, unsandboxed callers only**; AppImage and
  Flathub are left for later.
- **`add` changes the selection** like a drop. The alternative, leaving the
  owner's selection alone, would make an agent's videos appear unselected.
- **First window serves**, a second one does not.
- **The command waits for probing** in `add` by default, so the next command
  sees ready videos.
- English only in the command's output.
