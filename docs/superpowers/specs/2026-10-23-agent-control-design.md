# Controlling the running app from the command line

Status: design, not built. Written 2026-10-23.

## Why

The owner wants to hand VidCtrl work to an AI agent (Claude Code or any
other) or a script: "find the big videos on this computer, put them in the
queue, tell me when they are done". The agent does the finding itself
(`find`, `du`); what it lacks is a way to reach the app. The owner keeps
watching the window: videos appear in the list, jobs appear in the queue and
convert, exactly as if they had been dropped in by hand.

A command line was chosen over an MCP server first: it serves agents,
shell scripts and people alike, and an MCP server can be a thin wrapper over
it later (see "Later"). The owner liked working with DaVinci Resolve
through an MCP server and wants the same feeling: the agent drives, the
window shows.

## Goals

- A command, `vidctrl-cli` (name: see "Calls made by the designer"), that
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

## Decided with the owner

- The agent never clicks; the window only reflects state.
- Same abilities as the UI, no detailed compression parameters.
- Cancelling the running conversion and removing jobs need **no
  confirmation** in the window, as they need none there now.
- Closing the window from the command line: not offered.
- Monitoring and waiting are core, not extras: "wait until it's converted,
  then get the result", or get each result as it finishes.

## Constraints

- **Where the caller runs:** the same user, on the same desktop session as
  the window, not sandboxed: an ordinary terminal, a script, or Claude Code
  as the owner runs it (its Bash sandbox is off). The command needs the
  app's loopback network, its per-user folder and, to start the app, the
  desktop. A sandboxed agent (Claude Code's sandbox gives a process its own
  network), WSL on Windows, SSH and containers are not served; `docs/CLI.md`
  says to exempt `vidctrl-cli` from a sandbox.
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
3. **The command** (`bin/vidctrl_cli.dart`, built with `dart compile exe`,
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
- A stale file (no such process, or the port refuses) means "not running".

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
`app-closing` event to subscribers, closes connections and deletes the
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
| `remove <videos…>` | removing from the list | |
| `queue` | the queue pane | each job: id, video, goal and options, sample or not, status, progress and time left, "checking the quality… try N", output path, chosen quality and outcome |
| `queue add <videos…> [--goal g] [--opt k=v]… [--sample start\|middle] [--out next\|<folder>] [--subfolder Name]` | Add to queue | paths not in the list yet are added first; an identical pending job is reported as already queued, not added; without `--goal` the panel's current goal and options are used (like the button) and the output says which; without `--sample` the whole video, whatever the panel's sample choice; without `--out` the panel's output setting (remembered, maybe a custom folder) |
| `queue remove <jobs…>`, `queue move <job> <position>`, `queue retry <job>`, `queue clear-finished` | the job's ⋯ menu, dragging, "Clear finished" | |
| `pause`, `resume` | the pause button | explicit, not a toggle, so a script can repeat them |
| `cancel [job]` | cancel | the running one by default |
| `queue convert-anyway <job>`, `queue convert-whole <job>` | "Convert anyway", "Convert the whole video" | |
| `job <job>` | a finished job's row and (i) window | result path and size, chosen quality, outcome (`belowTarget` gives the `-check` name and says "look at it"), poorest piece's scores; `--command` adds "Show the command" (`forDisplay: true`) |
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

JSON lines on stdout until the app closes, each `{ "event", "time", … }`:
`video-added`, `video-ready`, `video-unreadable`, `video-removed`,
`job-added`, `job-checking` (attempt N), `job-started`, `job-progress` (at
most once a second per job), `job-finished` (status, output path, size,
quality outcome), `job-removed`, `queue-paused`, `queue-resumed`,
`queue-idle`, `compare-finished`, `app-closing`. Without `--since-now` it
first prints the current state as `snapshot`, so a reader that starts late
misses nothing. This is what an agent runs in the background to say "the
first three are done" while the rest converts.

### Words

Plain words lead in the command's text output too ("Looks the same", "Kept
as it is: converting would hardly make it smaller"), with the technical
names beside, in English. `--json` carries ids and numbers, and the same
English words as separate fields.

## What changes in the window

Nothing needs to: it already renders the notifiers' state. One choice
follows from "like a drop": videos added by `add` become the selection, as
dropped ones do, so the panel's preview measures them (see the calls below).

## Shipping

- The release workflow compiles the command on each system
  (`dart compile exe bin/vidctrl_cli.dart`) and puts it beside the app:
  Linux in the bundle beside `vidctrl`, Windows beside `vidctrl.exe`, macOS
  in `Contents/MacOS/`, where `tool/package_macos.sh` signs it inside out
  with the rest (hardened runtime, so notarization passes). CI checks it is
  there, as it checks FFmpeg.
- Reaching it from a terminal: until there are installers, the README says
  how to link it onto the `PATH` (`ln -s …/vidctrl-cli ~/.local/bin/`;
  macOS `/usr/local/bin`). An installer can do that later.
- `docs/CLI.md`, plus `vidctrl-cli help` and `help <command>`, written for
  an agent reading them cold: what each command does, ids, exit codes, and
  two worked examples ("queue every video over 2 GB in ~/Videos and tell me
  when done"; "make samples first, compare, then convert the whole").

## Testing

- `lib/core/control/`: protocol encoding, endpoint file reading, stale
  detection, client against a fake server.
- Control server: plain `ProviderContainer` tests with `FakeEnvironment`
  (not widget tests: real sockets escape the fake clock), over a real
  loopback socket. Each command is checked against what the same button
  does: e.g. `queue add` and `addSelected()` produce equal jobs; a duplicate
  is refused both ways; `cancel` and the cancel button leave the same state.
- Events: a fake job finishing produces `job-finished`, a closing container
  produces `app-closing`.
- The command: argument parsing and exit codes against a fake server; one
  test that starts it as a process (`dart run bin/vidctrl_cli.dart`)
  against a server in the test.
- A widget test that an `add` from the server shows in the video list and a
  `queue add` in the queue pane.

## Order of work

1. Protocol, endpoint file, server with `status`, `goals`, `add`, `videos`,
   `queue`, `queue add`, `wait`, `events`. Usable by an agent end to end.
2. The rest of the queue operations, `job`, `compare`, `details`,
   `estimate`.
3. Shipping: compile and bundle on three systems, signing, CI check,
   `docs/CLI.md`.
4. MCP (see "Later").

## Later

- `vidctrl-cli mcp`: an MCP server on stdio inside the same command, one tool
  per command with the same arguments and JSON, `wait` as a long call and
  events as notifications. No logic of its own.
- A mark in the queue for jobs that came from the command line, if
  watching shows it is wanted.
- A finish notification of the desktop's own, already on the roadmap
  ("Comfort"), would serve both the mouse and the command.

## Calls made by the designer

Not discussed with the owner; each can be changed without changing the rest.

- **Name `vidctrl-cli`**, a separate console program: the window's program
  is already `vidctrl` on Linux and Windows, and a Windows GUI program
  cannot print to a terminal or be waited for there.
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
