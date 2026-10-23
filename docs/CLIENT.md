# vidctrl-client

`vidctrl-client` controls the open VidCtrl window. Below, `vidctrl-client` stands for the program as you run it: by its full path when not on the `PATH`, quoted as the window's prompt has it: `'/opt/VidCtrl/vidctrl-client'`, `"C:\…\vidctrl-client.exe"` on Windows, `& "C:\…\vidctrl-client.exe"` in PowerShell.

## Quick start

VidCtrl is open on this computer, and the person watches its window. The program `vidctrl-client` controls it: it adds videos to the window's list and queues conversions there.

- Run `vidctrl-client manual` first: it explains every command, the goals and what the results mean. Add `--json` to a command to read its answer as JSON.
- Finding the videos is your job (with `find`, `du` or the like). Give their paths to `vidctrl-client add`, or straight to `vidctrl-client queue add --goal <goal>`.
- The window converts one video at a time, and that can take hours. To know when it ends, run `vidctrl-client wait` in the background (or follow `vidctrl-client events`), and tell the person when it returns: each result, and any marked "worth a look by eye".
- Never delete, move or rename any file. "Remove" only takes a video off the list or a job out of the queue.

## What VidCtrl is

A window that converts videos by goal; `vidctrl-client` changes what it shows, as the person would with the mouse.

- **Videos**: the window's list. `add` is like dropping a file there; each file is listed once, and videos just added become the selection.
- **Goals**: what to make of a video, by the panel's ids (see "Goals").
- **Jobs**: `queue add` makes one per video, a snapshot of video, goal, options and folder that later changes do not touch. The queue starts by itself and goes in order.
- **The window shows everything**; the person may act there too (pause, add, take jobs out), and this program sees it.
- **Nothing converts without the window.** Every command but `status`, `manual` and `help` opens one if none is ("Starting VidCtrl…" on stderr, up to 30 s); closing it stops conversions. Two commands at once may each open one: run `vidctrl-client queue` first, then `events` in the background.
- **Results** are new files, by default in `Converted` beside each video, named with the settings (`beach.mov` gives `Converted/beach_av1-crf35.mp4`, a second ` (2)`), written as a hidden `.part` until whole.
- **Samples**: 10 seconds from the start or middle, with the whole's settings, into `Samples` there (`beach_av1-crf35_sample10s.mp4`, `_sample10s-mid`).
- **Ids** count from 0, lasting, like the list and queue, while the window is open. Digits only is an id: a file named `3` is `./3`. Paths may be relative or start with `~`.

## What VidCtrl never does

VidCtrl deletes no file: "remove" takes a video off the list or a job out of the queue, and the file stays on disk.

- No command changes, moves or renames a file, nor closes the window or changes its panel's goal, remembered settings, look or language.
- Never delete, move or rename any file. Leave every file to the person.

## Commands

`vidctrl-client <command> [arguments] [options]`. All take `--json` (one JSON document; `events`: one per line), `--no-start` (exit 2, not open the window) and `--help`. Videos by id or path, jobs by id; one `--opt` per option. A goal, option or choice unknown or not offered here (see `goals`) is refused, naming the valid ones, but for the choice the goal makes here anyway. Errors: stderr and an exit code (see "Waiting"). `→` is the `--json` answer.

- `add <paths…> [--no-wait]`: Adds files, and the videos in folders, to the list, and waits until each is read. Results in `Converted` count too: give files, not a folder of results. → `{videos: [{path, id?, result}]}`
- `videos [--goal <goal>] [--opt <option>=<choice>]`: The list; with `--goal`, each video's `preview` (sizes measured only for the panel's goal while the queue is idle; else `estimate`). → `{videos: [Video]}`
- `details <video> | --job <job> [--raw]`: How a video, or a done job's result, is encoded, track by track; `--raw`: ffprobe's report. → `{info: Video, details: [{group, number, title, rows}]}` or `{info, raw}`
- `estimate <videos…> [--goal <goal>] [--opt <option>=<choice>]`: Measures expected size and closeness by encoding pieces, seconds to a minute each; without `--goal`, the panel's. `BUSY` while converting. → `{videos: [Video]}` with `preview`
- `remove <videos…>`: Takes videos off the list; files stay on disk, jobs in the queue. → `{removed: [int]}`
- `queue`: The jobs, in order. → `{paused: bool, busy: bool, jobs: [Job]}`
- `queue add <videos…> [--goal <goal>] [--opt <option>=<choice>] [--sample start|middle] [--out next|<folder>] [--subfolder <name>]`: Queues each readable video, adding unlisted paths (folders give their videos). Without `--goal`, the panel's: name it. `--out <folder>`: every result there; `--out next`: beside each video, in `--subfolder` (`Converted`); neither: the panel's folder. A like waiting job is not queued twice; nothing is if an argument is wrong or none can be (exit 5). → `{goal, options, added: [Job], alreadyQueued: [int], skipped: [{video, reason}]}`
- `queue remove <jobs…>`: Takes jobs out, cancelling one under way; files stay on disk. → `{removed: [int]}`
- `queue move <job> <position>`: Moves a waiting job; position 1, the top, converts next. → `{jobs: [Job]}`
- `queue retry <job>`: A `FAILED` or `CANCELLED` job waits again; read its `errorLines` first. → `{job: Job}`
- `queue clear-finished`: Takes `DONE` and `SKIPPED` jobs out; results stay on disk. → `{removed: [int]}`
- `queue convert-anyway <job>`: Converts a job `SKIPPED` as `NOT_WORTH_IT` all the same; ask the person first. → `{added: [Job], alreadyQueued: bool}`
- `queue convert-whole <job>`: Converts the whole video of a `DONE` sample job, with its settings. → `{added: [Job], alreadyQueued: bool}`
- `pause`: Holds the job under way; starts nothing new. → `{paused: true}`
- `resume`: The paused queue goes on. → `{paused: false}`
- `cancel [job]`: Stops the job under way (with `[job]`, only that one): `CANCELLED`, no result. A waiting job: `queue remove`. → `{cancelled: int or null, job?: Job}`
- `job <job> [--command]`: One job; `--command`: the FFmpeg command it runs, to show, not run. → `{job: Job, command?: string}`
- `compare <job> [--no-wait]`: Compares a `DONE` result with its original, taking about as long as the video, one at a time (`BUSY`); not after resizing, retiming or HDR to SDR. `--no-wait`: `{started: true}`, then `COMPARE_FINISHED`. → `{job: int, status, closeness, xpsnr: number, vmaf?: number}`
- `status`: Whether the window is open, and its queue; never opens it. → `{running: false}`, or `{running: true, …Status}`
- `wait [jobs…] [--timeout <seconds>]`: Waits until the jobs end (see "Waiting"). → `{outcomes: [Outcome]}` at the end
- `events [--since-now]`: Prints events as they happen (see "Codes"): a `SNAPSHOT` first (not with `--since-now`), until the window closes (exit 4). → `{event, time, …its fields}` per line
- `goals`: The goals with the options this computer offers. → `{goals: [Goal]}`
- `manual`: This guide. → `{commands, goals, exitCodes, events, codes}`
- `help [command]`: The commands, or one command's details. → text only

`vidctrl-client help <command>` prints a command's examples, its text output and a JSON sample.

## JSON

Answers hold ids, numbers, paths and codes in capitals (see "Codes"), never words; goal, option and choice ids as `--goal` and `--opt` take them. `[X]` is a list; `?` marks a field left out when not known; only `cancel` gives `null`. Untyped fields are strings.

- Video: `id` int, `path`, `status`, `sizeBytes`? int, `durationSeconds`? number, `width`? int, `height`? int, `videoCodec`?, `audioCodecs` [string], `hdr` bool, `preview`? Preview.
- Preview: `goal`, `plan`, `expectedBytes`? int, `measured` bool (by encoding pieces), `measuring` bool, `closeness`?.
- Job: `id` int, `videoId` int, `path`, `goal`, `options` {option: choice} (as made here: report these), `sample`?, `status`, `fraction`? 0-1, `remainingSeconds`? number, `attempt`? int, `outputPath`?, `outputBytes`? int, `quality`? Quality, `needsALook` bool, `errorLines` [string].
- Quality: `outcome`, `value`? int (lower is better), `standardValue`? int, `vmaf`? number, `xpsnr`? number (of the poorest piece), `share` number (expected size / original's).
- Outcome: `jobId` int, `path`, `status`, `outputPath`?, `needsALook` bool.
- Status: `state`, `version`, `busy` bool, `paused` bool, `jobs` {status: count}.
- Goal: `id` (`archive.master`), `scenario`, `title`, `subtitle`, `options` [{`id`, `title`, `defaultChoice`, `advanced` bool, `choices` [{`id`, `label`, `hint`}]}].
- Error, on stderr: `{"error": {"code", "message"}}`; read `code`, the message is for people.

## Codes

Each kind, where it is found, and its codes; `vidctrl-client help <command>` has them in full.

- **Job statuses** (Job and Outcome `status`, Status `jobs` keys): `WAITING`; `RUNNING` converting or choosing quality; `PAUSED` held by a pause; `DONE` result at `outputPath`; `SKIPPED` nothing written; not a failure; `FAILED` see `errorLines`; `CANCELLED` a failure for `wait`; `REMOVED` `wait` only: taken out, not a failure.
- **Video statuses** (Video `status`): `PROBING` being read; `READY` can be queued; `UNREADABLE` not a video FFmpeg opens.
- **Plans** (Preview `plan`): `SKIP` already fine (`SKIPPED`); `REMUX` copied into another file type; `AUDIO_ONLY` only the sound converted; `ENCODE` the picture converted: slow; `UNSUPPORTED` nothing the goal can do (`SKIPPED`); `KEPT_AS_IS` Archive: not worth it (`SKIPPED`).
- **Closeness** (Preview `closeness`, `compare`): `SAME` looks the same (VMAF 95+ on the poorest piece); `VERY_CLOSE` VMAF 93+; `DIFFERS` may visibly differ.
- **Quality outcomes** (Quality `outcome`): `STANDARD` the usual quality; `RAISED` a better one was needed: larger; `BELOW_TARGET` short even at the best: named `…-check`, `needsALook`, still `DONE`; ask the person to look by eye; `NOT_WORTH_IT` would keep over 80% of the size: `SKIPPED` (see `queue convert-anyway`).
- **Window states** (Status `state`): `STARTING` looking for FFmpeg; `READY`; `FFMPEG_MISSING` the window says what to do.
- **Adding** (`add`'s `result`, `queue add`'s `skipped[].reason`): `ADDED`; `KNOWN` listed already; `NOT_FOUND` nothing there, or no longer listed; `UNREADABLE` listed, not a video FFmpeg opens.
- **Samples** (Job `sample`): `START`; `MIDDLE`.
- **Comparisons** (`compare`'s and `COMPARE_FINISHED`'s `status`): `MEASURED`; `FAILED` only in the event, with `errorLines`.
- **Details** (`details[].group`): `FILE`; `VIDEO`; `AUDIO`; `SUBTITLE`; `TIMECODE`; `DATA`; `ATTACHMENT`; `CHAPTERS`.
- **Errors** (`error.code`, with the exit code): `BAD_ARGUMENT` 5, not valid; `NOT_FOUND` 5; `BUSY` 5, not now; `UNKNOWN_METHOD` 5, the window is another version; `FFMPEG_MISSING` 6; `UNAUTHORIZED` 2, the window refused or did not answer; `NOT_RUNNING` 2, none open and none could be; `APP_CLOSED` 4; `TIMEOUT` 3, the jobs go on; `UNEXPECTED` 5, the client went wrong.
- **Events** (`events`' `event`, with `time` but on `APP_CLOSING`, and these fields): `SNAPSHOT` `{videos: [Video], jobs: [Job], paused, busy}`, first; `VIDEO_ADDED` a Video; `VIDEO_READY` a Video; `VIDEO_UNREADABLE` a Video; `VIDEO_REMOVED` `{video}`; `JOB_ADDED` a Job; `JOB_CHECKING` `{job, attempt}`; `JOB_STARTED` a Job; `JOB_PROGRESS` `{job, fraction, remainingSeconds?}`; `JOB_FINISHED` a Job; `JOB_REMOVED` `{job}`; `QUEUE_PAUSED`; `QUEUE_RESUMED`; `QUEUE_IDLE` nothing more to do; `COMPARE_FINISHED` as `compare` answers, or with `errorLines`; `APP_CLOSING` the window closes.

## Goals

Which to choose: `archive` keeps the picture as it is in a smaller file, the usual choice to save space without loss; `space` also makes it at most 1080p and 30 fps, for calls, screen recordings and the like; `resolve.studio` to edit in DaVinci Resolve Studio, `resolve.free` in the free one (the picture converted too: much larger); the others by name.

By name or full id; choices default first; options only where they make a difference (see `goals`). No picture: `UNSUPPORTED` but for `audio` and `privacy`. `help goals` has the words in full.

- `--goal archive` (`archive.master`): Archive, no quality loss. Camera videos far smaller, looking the same; one not worth it is left as it is (`NOT_WORTH_IT`). `--opt codec=` `av1` Smallest file (default), `hevc` Works everywhere. `--opt speed=` `cpu` Thorough (default), `gpu` Fast.
- `--goal space` (`space.small`): Save space, good enough. Much smaller, still good to watch; every video is converted.
- `--goal resolve.studio`: Edit in DaVinci Resolve, Resolve Studio. For Resolve on Linux; a video it opens is left as it is (`SKIP`), often only the sound is converted. `--opt convertVideo=` `no` (default), `yes`. `--opt quality=` `balanced` Recommended (default), `smallest`, `smaller`, `best` Best quality. `--opt codec=` `prores` (default), `dnxhr`.
- `--goal resolve.free`: Edit in DaVinci Resolve, Free Resolve. `--opt quality=`, `--opt codec=` as for `resolve.studio`.
- `--goal audio` (`audio.extract`): Get the sound. The first sound track as a file, copied when it fits the type. `--opt format=` `original` As it is (default), `mp3`, `m4a`, `wav`, `flac`.
- `--goal privacy` (`privacy.clean`): Remove personal data. A copy without the hidden notes on place, date, camera and author; `quick` copies picture and sound, `thorough` converts them. `--opt mode=` `quick` (default), `thorough`.
- `--goal remux` (`remux.container`): Change file type. Another file type in seconds; the picture is never converted. `--opt format=` `mp4` (default), `mkv`, `mov`.

## Waiting

`vidctrl-client wait [jobs…]` waits for those jobs, or until none waits, converts or is paused, maybe for hours: run it in the background. It counts jobs not ended when it starts and those added or retried meanwhile (an old failure does not count); with none, it exits 0 at once. A job taken out is `REMOVED`, not a failure; a cancelled one is. A paused queue keeps it waiting. Exit codes, of every command:

- 0: done; for `wait`, every job done or skipped
- 1: a job failed or was cancelled
- 2: no window, none could open (or `--no-start`), or it refused
- 3: `--timeout` passed; the jobs go on
- 4: the window closed meanwhile
- 5: bad arguments, or the client went wrong
- 6: no FFmpeg; the window says what to do

## Recipes

Queue every video over 2 GB in ~/Videos and say when done (look at `find`'s list first; none: tell the person):

```sh
find ~/Videos -type f -size +2G \( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.mts' -o -iname '*.mkv' \) \
  -not -path '*/Converted/*' -print0 | xargs -0 vidctrl-client queue add --goal archive --json
vidctrl-client wait 0 1 2 --json   # in the background; the ids from each answer's `added`
```

Then tell the person each `outputPath` and `needsALook`, and on exit 1 each failed job's `errorLines` (`vidctrl-client queue --json`).

Samples first, then the whole:

```sh
vidctrl-client queue add ~/Videos/beach.mov --goal archive --sample middle --json
vidctrl-client wait --json
vidctrl-client compare 0 --json               # the sample's job id; tell the person
vidctrl-client queue convert-whole 0 --json   # once they agree
```

More in the help of `queue add` (PowerShell too), `queue convert-whole`, `events`, `pause`, `estimate`.

## Limits

- It runs as the person logged in, on the window's computer and desktop: not over SSH, from WSL or a container. A sandboxed agent must run `vidctrl-client` outside its sandbox (loopback network, the person's folders, the desktop).
- It takes no FFmpeg settings or quality numbers (so Archive keeps its promise) and speaks English whatever the window's language.

## Command details

What `vidctrl-client help <command>` prints for each command; the shapes and codes it adds follow, once for all.

### `vidctrl-client add <paths…>`

Adds videos to the list, as dropping them on the window does.

A folder adds the videos in it and in its folders, by their extension (.mp4, .mov, .mkv, .m4v, .avi, .mts, .m2ts, .ts, .mxf, .webm, .wmv, .flv, .3gp, .mpg, .mpeg), leaving out hidden folders. Results in its `Converted` and `Samples` folders count as videos too, so give the files rather than a folder that holds results. A file is tried whatever its extension. A video already in the list is reported with its id and not added twice. It waits until each video has been read.

Options:

- `--no-wait`: answer at once, while the videos are still being read.

Examples:

```sh
vidctrl-client add ~/Videos/beach.mov ~/Videos/trip
vidctrl-client add . --json
```

It prints, for example:

```
Video 0: Added. /home/alice/Videos/beach.mov
Video 1: In the list already. /home/alice/Videos/party.mov
Video 3: Cannot be read: not a video FFmpeg can open. /home/alice/Videos/notes.mov
Nothing found at /home/alice/Videos/missing.mov: no file, nor a folder with videos.
```

With `--json`: `videos` (list): for each video found, and each path where nothing was, `path` (string), `id` (int, optional: absent when nothing was found) and `result` (string): `ADDED`, `KNOWN` (in the list already), `UNREADABLE` (in the list, but not a video FFmpeg can open) or `NOT_FOUND`; see "Adding".

```json
{"videos":[{"path":"/home/alice/Videos/beach.mov","id":0,"result":"ADDED"},{"path":"/home/alice/Videos/party.mov","id":1,"result":"KNOWN"},{"path":"/home/alice/Videos/notes.mov","id":3,"result":"UNREADABLE"},{"path":"/home/alice/Videos/missing.mov","result":"NOT_FOUND"}]}
```

Errors:

- Nothing at all found at the paths given: exit 5.

### `vidctrl-client videos`

The videos in the list, and what a goal would do to each.

With `--goal` (and `--opt`), each video that could be read says what that goal would do to it, how large the result would be and how close it would look, where known. A size is known at once where the goal copies; a converted one is measured by encoding a few short pieces. The window measures the videos selected in its panel, with the goal the panel shows, while the queue is idle; videos just added are selected. `measuring` is true while it measures: ask again a little later. For another goal than the panel's, a size that needs measuring stays unknown until `vidctrl-client estimate` measures it.

Options:

- `--goal <goal>`: say what this goal would do to each video.
- `--opt <option>=<choice>`: an option of that goal, once for each.

Examples:

```sh
vidctrl-client videos
vidctrl-client videos --goal archive --json
```

It prints, for example:

```
Video 0: Ready. /home/alice/Videos/beach.mov
  4.20 GB, 12:34, 3840x2160, hevc, sound aac
  With archive.master: Converted. About 610.0 MB, measured. Looks the same as the original.
```

With `--json`: `videos` (list of Video), in the order of the list; with `--goal`, each readable one has a `preview` (Preview).

```json
{"videos":[{"id":0,"path":"/home/alice/Videos/beach.mov","status":"READY","sizeBytes":4200000000,"durationSeconds":754.2,"width":3840,"height":2160,"videoCodec":"hevc","audioCodecs":["aac"],"hdr":false,"preview":{"goal":"archive.master","plan":"ENCODE","expectedBytes":610000000,"measured":true,"measuring":false,"closeness":"SAME"}}]}
```

Errors:

- An unknown goal, option or choice, or `--opt` without `--goal`: exit 5.

### `vidctrl-client details <video> | --job <job>`

How a video or a result is made, as "Video details" shows it.

As "Video details" in the window: how the file is encoded, track by track (picture, then sound, then the file as a whole), in the window's words. A video still being read is waited for. With `--job`, the same for the result of a job that is done, as "Result details" in its ⋯ menu.

Options:

- `--job <job>`: the result of this job instead of a video in the list.
- `--raw`: FFmpeg's whole report on the file (ffprobe's JSON), instead of the details.

Examples:

```sh
vidctrl-client details 0
vidctrl-client details --job 1 --raw --json
```

It prints, for example:

```
Video 0: Ready. /home/alice/Videos/beach.mov
  4.20 GB, 12:34, 3840x2160, hevc, sound aac
Video track 1:
  Codec: H.265 / HEVC (High Efficiency Video Coding) · Main 10 · level 5.1
  Resolution: 3840×2160
  Frame rate: 25 fps (25/1)
  Bit depth: 10-bit
  Chroma subsampling: 4:2:0
Audio track 1:
  Codec: AAC (Advanced Audio Coding) · LC
  Channels: 2 (stereo)
  Sample rate: 48 kHz
File:
  Container: QuickTime / MOV
  Size: 4.20 GB
```

With `--json`: `info` (Video): the video; for a job, its result, with the `id` of the video it was made from. `details` (list): for each track and the file, `group` (string: what it describes, see "Details"), `number` (int: its place among those of its group, from 1), `title` (string) and `rows` (list of [label, value], both strings), in the window's words. With `--raw`, `raw` (object) instead of `details`: ffprobe's report as it gave it.

```json
{"info":{"id":0,"path":"/home/alice/Videos/beach.mov","status":"READY","sizeBytes":4200000000,"durationSeconds":754.2,"width":3840,"height":2160,"videoCodec":"hevc","audioCodecs":["aac"],"hdr":false},"details":[{"group":"VIDEO","number":1,"title":"Video track 1","rows":[["Codec","H.265 / HEVC (High Efficiency Video Coding) · Main 10 · level 5.1"],["Resolution","3840×2160"],["Frame rate","25 fps (25/1)"],["Bit depth","10-bit"],["Chroma subsampling","4:2:0"]]},{"group":"AUDIO","number":1,"title":"Audio track 1","rows":[["Codec","AAC (Advanced Audio Coding) · LC"],["Channels","2 (stereo)"],["Sample rate","48 kHz"]]},{"group":"FILE","number":1,"title":"File","rows":[["Container","QuickTime / MOV"],["Size","4.20 GB"]]}]}
```

Errors:

- A video that is not in the list, a job that is not done, or a result that cannot be read where it was written: exit 5 (`NOT_FOUND`). A video FFmpeg cannot open: exit 5.

### `vidctrl-client estimate <videos…>`

Measures how large videos would come out with a goal.

As the window does for the videos selected in its panel: it encodes a few short pieces of each video and compares them with the original, so it knows how large the result would be and how close it would look; Archive also chooses each video's quality, as before converting it. It answers once every video is measured, one after the other: seconds to a minute or so each. A size the goal knows without measuring (a copy) is given at once. When the window is already measuring as many videos as it does at once, it waits its turn.

Only while the queue is idle, as in the window: measuring and converting would share the processor. Without `--goal`, the goal shown in the window's panel. What it measured stays in the window: `vidctrl-client videos --goal <goal>` gives it again, and the window's list shows it for the goal of its panel.

Options:

- `--goal <goal>`: the goal, as `vidctrl-client goals` lists them.
- `--opt <option>=<choice>`: an option of that goal, once for each.

Example:

```sh
vidctrl-client estimate 0 1 2 --goal archive --json
```

It prints, for example:

```
Video 0: Ready. /home/alice/Videos/beach.mov
  4.20 GB, 12:34, 3840x2160, hevc, sound aac
  With archive.master: Converted. About 610.0 MB, measured. Looks the same as the original.
```

With `--json`: `videos` (list of Video), as given, each that could be read with its `preview` (Preview) for the goal.

```json
{"videos":[{"id":0,"path":"/home/alice/Videos/beach.mov","status":"READY","sizeBytes":4200000000,"durationSeconds":754.2,"width":3840,"height":2160,"videoCodec":"hevc","audioCodecs":["aac"],"hdr":false,"preview":{"goal":"archive.master","plan":"ENCODE","expectedBytes":610000000,"measured":true,"measuring":false,"closeness":"SAME"}}]}
```

Errors:

- While the queue converts, or when converting starts before it has measured them all: `BUSY`, exit 5 ("Videos are being converted; the window measures when the queue is idle."). Measure before queuing, or after `vidctrl-client wait`.
- A video that is not in the list (`vidctrl-client add` it first), one FFmpeg cannot open, or an unknown goal, option or choice: exit 5.

#### What would Archive do with these videos, and how big would they be?

```sh
vidctrl-client add ~/Videos/trip --json
vidctrl-client estimate 0 1 2 --goal archive --json      # the ids from `add`
```

`estimate` measures each video in turn and answers once all are measured; that takes seconds to a minute or so for each. Each video's `preview` gives the `plan`, the `expectedBytes` (`measured` when measured by encoding pieces) and the `closeness`; beside its `sizeBytes`, that is how much smaller it would come out. A preview with no `expectedBytes` could not be measured. While the queue converts, `estimate` is refused (`BUSY`): measure before queuing, or once `vidctrl-client wait` has returned. Later, `vidctrl-client videos --goal archive --json` gives the same again.

### `vidctrl-client remove <videos…>`

Takes videos off the list; their files stay on disk.

Only off the window's list, as its own remove button does: the files stay on disk, and jobs already queued for these videos stay in the queue.

Example:

```sh
vidctrl-client remove 0 ~/Videos/party.mov
```

It prints, for example:

```
Video 0: Off the list; its file stays on disk.
Video 1: Off the list; its file stays on disk.
```

With `--json`: `removed` (list of int): the ids taken off the list.

```json
{"removed":[0,1]}
```

Errors:

- A video that is not in the list: exit 5, and none is taken off.

### `vidctrl-client queue`

The jobs in the queue, as the queue pane shows them.

Each job with its status, progress and time left, its goal and options, its result once known, and how its quality was chosen.

Examples:

```sh
vidctrl-client queue
vidctrl-client queue --json
```

It prints, for example:

```
The queue is converting:
Job 0: Done. /home/alice/Videos/beach.mov
  archive.master, codec=av1, speed=cpu, video 0
  Result: /home/alice/Videos/Converted/beach_av1-crf35.mp4, 598.0 MB
  Usual quality (crf 35; VMAF 96.4; XPSNR 43.1 dB). Expected at 14% of the original's size.
Job 1: Converting, 42%, about 21 min left. /home/alice/Videos/party.mov
  archive.master, codec=av1, speed=cpu, video 1
  Result: /home/alice/Videos/Converted/party_av1-crf20-check.mp4
  Worth a look by eye: even the best quality falls a little short somewhere (crf 20, usual 35; VMAF 93.8; XPSNR 40.2 dB). Expected at 52% of the original's size.
Job 2: Waiting. /home/alice/Videos/dog.mp4
  archive.master, codec=av1, speed=cpu, video 2
```

With `--json`: `paused` (bool): the queue is paused in the window; `busy` (bool): it is working through jobs; `jobs` (list of Job), in queue order.

```json
{"paused":false,"busy":true,"jobs":[{"id":0,"videoId":0,"path":"/home/alice/Videos/beach.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"DONE","outputPath":"/home/alice/Videos/Converted/beach_av1-crf35.mp4","outputBytes":598000000,"quality":{"outcome":"STANDARD","value":35,"standardValue":35,"vmaf":96.4,"xpsnr":43.1,"share":0.14},"needsALook":false,"errorLines":[]},{"id":2,"videoId":2,"path":"/home/alice/Videos/dog.mp4","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"WAITING","needsALook":false,"errorLines":[]}]}
```

### `vidctrl-client queue add <videos…>`

Queues videos with a goal, as Add to queue does.

Videos given by a path that is not in the list yet are added first, as `vidctrl-client add` does; a folder gives the videos in it. Each video that can be read gets a job; one with the same goal, options, sample and folder still waiting in the queue is reported as queued already, not queued twice. Nothing is queued when any argument is wrong.

Without `--goal`, the goal and options shown in the window's panel are used, as by its Add to queue button; the answer says which. Name the goal to be sure. Without `--sample`, the whole video. Without `--out`, the folder the panel is set to: `Converted` beside each video unless the person chose another.

Options:

- `--goal <goal>`: the goal, as `vidctrl-client goals` lists them.
- `--opt <option>=<choice>`: an option of the goal, once for each; the others keep their defaults.
- `--sample start|middle`: a 10-second sample from the start or the middle instead of the whole video, into `Samples`.
- `--out next|<folder>`: `next`: a folder beside each video; or one folder for every result.
- `--subfolder <name>`: the name of the folder beside each video (`Converted` unless given); implies `--out next`.

Examples:

```sh
vidctrl-client queue add 0 1 --goal archive
vidctrl-client queue add ~/Videos/trip --goal archive --opt codec=hevc --json
vidctrl-client queue add 2 --goal archive --sample middle
```

It prints, for example:

```
Goal: archive.master, codec=av1, speed=cpu.
Job 2: Queued. /home/alice/Videos/dog.mp4
Video 0: In the queue already, with this goal and folder.
Not queued, video 3: it cannot be read.
```

With `--json`: `goal` (string): the goal's id; `options` (object): every option of the goal and the choice made on this computer, as in Job; `added` (list of Job): the new jobs; `alreadyQueued` (list of int): the videos that were queued already; `skipped` (list): `video` (int or string, as given) and `reason` (string: `UNREADABLE` or `NOT_FOUND`).

```json
{"goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"added":[{"id":2,"videoId":2,"path":"/home/alice/Videos/dog.mp4","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"WAITING","needsALook":false,"errorLines":[]}],"alreadyQueued":[0],"skipped":[{"video":3,"reason":"UNREADABLE"}]}
```

Errors:

- An unknown goal, option or choice, a choice of an option this computer does not offer other than the one made here anyway, a video id not in the list, or a `--subfolder` that is not one folder's name: exit 5, with the valid ones named.
- Nothing to queue, every path or video skipped (nothing found there, or it cannot be read): exit 5, with the reason for each.

#### Queue every video over 2 GB in ~/Videos, and tell me when it is done

Find them yourself, leaving out earlier results, and look at the list first:

```sh
find ~/Videos -type f -size +2G \( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.mts' -o -iname '*.mkv' \) \
  -not -path '*/Converted/*'
```

If it lists nothing, tell the person no video was found, and stop. Otherwise queue them with a goal:

```sh
find ~/Videos -type f -size +2G \( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.mts' -o -iname '*.mkv' \) \
  -not -path '*/Converted/*' -print0 | xargs -0 vidctrl-client queue add --goal archive --json
```

For a long list `xargs` may run `queue add` more than once: each run prints one JSON answer on its own line. Take the job ids from every answer's `added` (`added[].id`); videos in `alreadyQueued` were in the queue already, and `vidctrl-client queue --json` shows their jobs. Then wait for those jobs, in the background, as it can take hours:

```sh
vidctrl-client wait 0 1 2 --json             # the job ids from `added`
```

On Windows, in PowerShell:

```powershell
$files = Get-ChildItem "$HOME\Videos" -Recurse -File -Include *.mov,*.mp4,*.mts,*.mkv |
  Where-Object { $_.Length -gt 2GB -and $_.FullName -notmatch '\\Converted\\' }
$files.Count                     # 0: tell the person no video was found, and stop
vidctrl-client queue add --goal archive --json @($files.FullName)
vidctrl-client wait 0 1 2 --json             # the job ids from `added`
```

`wait` returns when the last of those jobs has ended. Then tell the person each result (`outputPath`), and name every one with `needsALook` true: worth a look by eye. `vidctrl-client queue --json` gives each job's size and quality too, and on exit 1 each failed job's `errorLines`: tell the person why it failed. Once the cause is put right, `vidctrl-client queue retry <job>` tries a job again.

### `vidctrl-client queue remove <jobs…>`

Takes jobs out of the queue; any finished file stays on disk.

As each job's remove in the window: a waiting job is taken out, one under way is cancelled first, and one that has ended only leaves the queue. Every file stays on disk, the original and any result.

To take out every done and skipped job at once: `vidctrl-client queue clear-finished`.

Examples:

```sh
vidctrl-client queue remove 2
vidctrl-client queue remove 0 1 --json
```

It prints, for example:

```
Job 2: Taken out of the queue; any finished file stays on disk.
```

With `--json`: `removed` (list of int): the jobs taken out.

```json
{"removed":[2]}
```

Errors:

- A job that is not in the queue: exit 5, and none is taken out.

### `vidctrl-client queue move <job> <position>`

Moves a waiting job to another place in the queue.

As dragging it in the window, where only waiting jobs can be dragged. Positions count from 1, the top of the list; one past the end is the end. The queue converts the waiting job nearest the top next, so `vidctrl-client queue move <job> 1` makes it the next.

Example:

```sh
vidctrl-client queue move 2 1
```

It prints, for example:

```
The queue, in order:
1. Job 2: Waiting. /home/alice/Videos/dog.mp4
2. Job 0: Done. /home/alice/Videos/beach.mov
3. Job 1: Converting. /home/alice/Videos/party.mov
```

With `--json`: `jobs` (list of Job): the whole queue, in its new order.

```json
{"jobs":[{"id":2,"videoId":2,"path":"/home/alice/Videos/dog.mp4","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"WAITING","needsALook":false,"errorLines":[]},{"id":0,"videoId":0,"path":"/home/alice/Videos/beach.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"DONE","outputPath":"/home/alice/Videos/Converted/beach_av1-crf35.mp4","outputBytes":598000000,"quality":{"outcome":"STANDARD","value":35,"standardValue":35,"vmaf":96.4,"xpsnr":43.1,"share":0.14},"needsALook":false,"errorLines":[]}]}
```

Errors:

- A job that is not in the queue or not waiting, or a position that is not a whole number: exit 5.

### `vidctrl-client queue retry <job>`

Tries a failed or cancelled job again, as its retry button does.

The job waits its turn again, in its place, with the same settings. Look at why it failed first: `vidctrl-client queue --json` gives its `errorLines`. Trying again rarely helps when the video itself cannot be converted; tell the person instead.

Example:

```sh
vidctrl-client queue retry 2
```

It prints, for example:

```
Job 2: Queued again. /home/alice/Videos/dog.mp4
```

With `--json`: `job` (Job): the job, waiting again.

```json
{"job":{"id":2,"videoId":2,"path":"/home/alice/Videos/dog.mp4","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"WAITING","needsALook":false,"errorLines":[]}}
```

Errors:

- A job that is not in the queue, or one that neither failed nor was cancelled: exit 5.

### `vidctrl-client queue clear-finished`

Takes the done and skipped jobs out of the queue; their files stay on disk.

As "Clear finished" in the window. Only the queue changes: each result stays where its `outputPath` said. Failed and cancelled jobs stay, to be tried again.

Example:

```sh
vidctrl-client queue clear-finished
```

It prints, for example:

```
Job 0: Taken out of the queue; any finished file stays on disk.
```

With `--json`: `removed` (list of int): the jobs taken out; empty when none had ended done or skipped.

```json
{"removed":[0]}
```

### `vidctrl-client queue convert-anyway <job>`

Converts a video kept as it is, as "Convert anyway" does.

For a job that ended `SKIPPED` with the outcome `NOT_WORTH_IT`: Archive found that converting would hardly make the file smaller. A new job converts it all the same, at the quality found for it, with the same goal, options and folder. Ask the person first: the result is nearly as large as the original.

Example:

```sh
vidctrl-client queue convert-anyway 3
```

It prints, for example:

```
Job 4: Queued. /home/alice/Videos/trip.mov
```

With `--json`: `added` (list of Job): the new job, or none when a job just like it is waiting or under way already; `alreadyQueued` (bool): that is so.

```json
{"added":[{"id":4,"videoId":3,"path":"/home/alice/Videos/trip.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"WAITING","needsALook":false,"errorLines":[]}],"alreadyQueued":false}
```

Errors:

- A job that is not in the queue, or one that was not kept as it is: exit 5.

### `vidctrl-client queue convert-whole <job>`

Queues the whole video after a sample, as the window's button does.

For a sample job that is done, as "Convert the whole video" under it in the window: a new job converts the whole video the sample was taken from, with the same goal, options and folder, into the output folder rather than `Samples`.

Example:

```sh
vidctrl-client queue convert-whole 3 --json
```

It prints, for example:

```
Job 4: Queued. /home/alice/Videos/trip.mov
```

With `--json`: `added` (list of Job) and `alreadyQueued` (bool), as for `queue convert-anyway`.

```json
{"added":[{"id":4,"videoId":3,"path":"/home/alice/Videos/trip.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"WAITING","needsALook":false,"errorLines":[]}],"alreadyQueued":false}
```

Errors:

- A job that is not in the queue, not a sample, or a sample not done yet: exit 5.

#### Make samples first, compare, then convert the whole

```sh
vidctrl-client queue add ~/Videos/beach.mov ~/Videos/party.mov --goal archive --sample middle --json
vidctrl-client wait --json
vidctrl-client compare 0 --json               # each sample job's id from `added`
vidctrl-client compare 1 --json
```

Each sample job's `outputPath` is a 10-second piece in `Converted/Samples/`. `compare` compares it with the same piece of its original and says how close it looks: `closeness`, with `vmaf` and `xpsnr`. Each comparison takes about as long as the piece lasts, or longer. `vidctrl-client job <job> --json` gives the sample's `quality` too: the quality chosen for the whole video and `share`, its expected size as a share of the original's. Tell the person where the samples are and how close each looks, so they can look at them. Once they agree, convert each whole video with its sample's settings, by the sample jobs' ids:

```sh
vidctrl-client queue convert-whole 0 --json
vidctrl-client queue convert-whole 1 --json
vidctrl-client wait --json
```

Each answer's `added` holds the new job. For other settings, queue the whole videos with `vidctrl-client queue add` and the goal and options wanted.

### `vidctrl-client pause`

Pauses the queue, as the window's pause button does.

Nothing new starts, and the job under way is held where the system allows (otherwise it finishes). A job still choosing its quality stops measuring, and measures again on `vidctrl-client resume`. Pausing a paused queue changes nothing, so a script may repeat it. The window shows the queue paused, and the person may continue it there.

Example:

```sh
vidctrl-client pause
```

It prints, for example:

```
The queue is paused: nothing new starts until it is resumed, and the job under way is held where the system allows.
```

With `--json`: `paused` (bool): true.

```json
{"paused":true}
```

#### Hold the conversions for a while

When the person needs the computer for something else:

```sh
vidctrl-client pause
vidctrl-client resume                         # when the person says so
```

`pause` holds the job under way and starts nothing new; `resume` goes on where it was. To stop the job under way for good, `vidctrl-client cancel` (it can be tried again with `vidctrl-client queue retry <job>`); to take waiting jobs out of the queue, `vidctrl-client queue remove <jobs…>`. The files stay as they are.

### `vidctrl-client resume`

Lets a paused queue go on.

The job held goes on, then the next. Resuming a queue that is not paused changes nothing.

Example:

```sh
vidctrl-client resume
```

It prints, for example:

```
The queue goes on.
```

With `--json`: `paused` (bool): false.

```json
{"paused":false}
```

### `vidctrl-client cancel [job]`

Cancels the job under way, as its cancel button does.

It answers once the job has stopped; the queue goes on with the next one. The job stays in the queue as `CANCELLED`; no result is written for it, and the original stays as it is. `vidctrl-client queue retry <job>` tries it again.

With a job id, only if that job is the one converting, so that another is not cancelled by mistake. A waiting job is taken out of the queue with `vidctrl-client queue remove <job>` instead.

Examples:

```sh
vidctrl-client cancel
vidctrl-client cancel 1 --json
```

It prints, for example:

```
Job 1: Cancelled; the queue goes on with the next one.

# When it ended before it could be cancelled:
Job 0: Not cancelled; it ended first: Done. /home/alice/Videos/beach.mov

# When no job is converting:
No job is converting; nothing was cancelled.
```

With `--json`: `cancelled` (int, or null when nothing was cancelled); `job` (Job, optional): when it ended otherwise before it could be cancelled (done, say), how it ended.

```json
{"cancelled":1}
```

Errors:

- A job that is not in the queue, or not the one converting: exit 5, and nothing is cancelled.

### `vidctrl-client job <job>`

One job, as its row and (i) window show it.

Its status, goal and options, its result and size once done, and how its quality was chosen: the outcome and the scores of the poorest piece. A job worth a look by eye (`needsALook`, the outcome `BELOW_TARGET`) has a name ending in `-check`: tell the person to look at it beside the original.

With `--command`, what "Show the command" in its ⋯ menu shows: the FFmpeg command VidCtrl runs for it, for this system's terminal (PowerShell on Windows). It is for the person to read: do not run it, the window converts. For an Archive job whose quality is not chosen yet, its quality number may still change.

Options:

- `--command`: add the FFmpeg command VidCtrl runs for it.

Examples:

```sh
vidctrl-client job 1
vidctrl-client job 1 --command --json
```

It prints, for example:

```
Job 1: Done. /home/alice/Videos/party.mov
  archive.master, codec=av1, speed=cpu, video 1
  Result: /home/alice/Videos/Converted/party_av1-crf20-check.mp4, 2.10 GB
  Worth a look by eye: even the best quality falls a little short somewhere (crf 20, usual 35; VMAF 93.8; XPSNR 40.2 dB). Expected at 52% of the original's size.
  Its name ends in -check: look at it beside the original.
The command, as "Show the command" in the window gives it:
  ffmpeg -hide_banner -i /home/alice/Videos/party.mov -map 0:v:0 -map '0:a?' -map_metadata 0 -c:v libsvtav1 -preset 5 -crf 20 -svtav1-params tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0:keyint=10s:scd=1 -pix_fmt yuv420p10le -c:a copy -movflags +faststart+use_metadata_tags -metadata major_brand= -metadata minor_version= -metadata compatible_brands= -f mp4 /home/alice/Videos/Converted/party_av1-crf20-check.mp4
```

With `--json`: `job` (Job); `command` (string, optional): with `--command`, left out for a job that runs nothing (one that ended skipped or is kept as it is).

```json
{"job":{"id":1,"videoId":1,"path":"/home/alice/Videos/party.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"DONE","outputPath":"/home/alice/Videos/Converted/party_av1-crf20-check.mp4","outputBytes":2100000000,"quality":{"outcome":"BELOW_TARGET","value":20,"standardValue":35,"vmaf":93.8,"xpsnr":40.2,"share":0.52},"needsALook":true,"errorLines":[]},"command":"ffmpeg -hide_banner -i /home/alice/Videos/party.mov -map 0:v:0 -map '0:a?' -map_metadata 0 -c:v libsvtav1 -preset 5 -crf 20 -svtav1-params tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0:keyint=10s:scd=1 -pix_fmt yuv420p10le -c:a copy -movflags +faststart+use_metadata_tags -metadata major_brand= -metadata minor_version= -metadata compatible_brands= -f mp4 /home/alice/Videos/Converted/party_av1-crf20-check.mp4"}
```

Errors:

- A job that is not in the queue: exit 5.

### `vidctrl-client compare <job>`

Compares a result with its original, as the window's menu does.

As "Compare with the original" in a done job's ⋯ menu: VidCtrl compares the result with its original frame by frame (a sample with the same piece of it) and says how close it looks, by VMAF where this FFmpeg measures it, otherwise by XPSNR (see "Closeness"). It takes about as long as the video lasts, or longer, and one comparison runs at a time. The window shows it under the job, and the person may stop it there.

Offered only where each frame of the result stands for one of the original: not after the picture was made smaller, its frame rate changed or its HDR turned into SDR ("Save space" makes 4K videos 1080p). Asked again while that job is being compared, it waits for the same comparison.

Options:

- `--no-wait`: answer at once; the `COMPARE_FINISHED` event (`vidctrl-client events`) tells the result.

Examples:

```sh
vidctrl-client compare 1
vidctrl-client compare 1 --no-wait --json
```

It prints, for example:

```
Job 1: Compared with the original. Very close to the original (VMAF 94.1; XPSNR 40.6 dB).

# With --no-wait:
Job 1: Comparing with the original; `vidctrl-client compare 1` waits for the result.
```

With `--json`: `job` (int); `status` (string): `MEASURED`; `closeness` (string, see "Closeness"); `xpsnr` (number, in dB); `vmaf` (number, optional: where this FFmpeg measures it). With `--no-wait`, `{"started": true}`.

```json
{"job":1,"status":"MEASURED","closeness":"VERY_CLOSE","xpsnr":40.6,"vmaf":94.1}
```

Errors:

- A job that is not done, or whose frames do not pair with the original's, or an FFmpeg without the `xpsnr` filter: exit 5, saying why.
- Another job being compared: `BUSY`, exit 5; ask again once it has ended.
- The comparison failed (exit 5, with FFmpeg's words), or was stopped in the window (exit 5).

### `vidctrl-client status`

Whether VidCtrl is open, and how its queue stands.

It never opens the window. A window that has just opened is `STARTING` while it looks for FFmpeg, then `READY`, or `FFMPEG_MISSING` when it found none.

Examples:

```sh
vidctrl-client status
vidctrl-client status --json
```

It prints, for example:

```
VidCtrl 1.2.0 is open and ready.
The queue is converting: 1 done, 1 converting, 1 waiting.

# When the window is not open:
VidCtrl is not running.
```

With `--json`: `{"running": false}` when the window is not open; otherwise `running` (bool, true) and a Status.

```json
{"running":true,"state":"READY","version":"1.2.0","busy":true,"paused":false,"jobs":{"DONE":1,"RUNNING":1,"WAITING":1}}
```

### `vidctrl-client wait [jobs…]`

Waits until the jobs are finished, and says how each ended.

Without job ids, until no job is waiting or converting; with ids, until those have ended. Jobs added meanwhile, by this program or the person, count too. The rules are under "Waiting". Conversions can take hours: run it in the background.

Each job is printed as soon as it ends; the last line sums up. Exit 0 when every job ended done or skipped, 1 when one failed or was cancelled, 3 after `--timeout`, 4 when the window closed.

Options:

- `--timeout <seconds>`: give up after this long, with exit 3; the jobs go on in the window.

Examples:

```sh
vidctrl-client wait
vidctrl-client wait 3 4 --timeout 600 --json
```

It prints, for example:

```
Job 0: Done. /home/alice/Videos/beach.mov
  Result: /home/alice/Videos/Converted/beach_av1-crf35.mp4, 598.0 MB
  Usual quality (crf 35; VMAF 96.4; XPSNR 43.1 dB). Expected at 14% of the original's size.
Job 1: Done. /home/alice/Videos/party.mov
  Result: /home/alice/Videos/Converted/party_av1-crf20-check.mp4, 2.10 GB
  Worth a look by eye: even the best quality falls a little short somewhere (crf 20, usual 35; VMAF 93.8; XPSNR 40.2 dB). Expected at 52% of the original's size.
All done.
```

With `--json`: `outcomes` (list of Outcome), once all have ended; nothing is printed before.

```json
{"outcomes":[{"jobId":0,"path":"/home/alice/Videos/beach.mov","status":"DONE","outputPath":"/home/alice/Videos/Converted/beach_av1-crf35.mp4","needsALook":false},{"jobId":1,"path":"/home/alice/Videos/party.mov","status":"DONE","outputPath":"/home/alice/Videos/Converted/party_av1-crf20-check.mp4","needsALook":true}]}
```

Errors:

- A job id not in the queue: exit 5.

#### Waiting

- `vidctrl-client wait` without ids waits until no job is waiting, converting or paused; with ids, until those have ended.
- The jobs it counts are those not yet ended when it starts, and any added or tried again while it waits, by this program or the person. Jobs that ended before it started do not count, so an old failure does not make every later `wait` exit 1.
- With nothing waiting when it starts, it exits 0 at once.
- A job taken out of the queue while it waits is told as `REMOVED`, not as a failure; one cancelled is a failure.
- A paused queue keeps it waiting, as the person may continue it; it says so once on stderr.
- It may run for hours: run it in the background and tell the person when it returns.

#### Exit codes

The same for every command:

| Code | Meaning |
|---|---|
| 0 | Done. For `wait`: every job ended done or skipped, those worth a look by eye included (flagged in the output). |
| 1 | At least one job failed or was cancelled. |
| 2 | VidCtrl is not open and could not be opened (or `--no-start` was given), or it is open but refused the connection or did not answer. |
| 3 | `--timeout` passed; the jobs go on in the window. |
| 4 | The window closed while waiting or following. |
| 5 | Bad arguments: an unknown command, goal, option, choice, video or job; or the client itself went wrong. |
| 6 | VidCtrl could not find FFmpeg; the window says what to do. |

### `vidctrl-client events`

Tells what happens in the window, as it happens.

It goes on until the window closes, then exits 4: stop it yourself when you no longer need it. First it tells how everything stands (`SNAPSHOT`), so nothing is missed by starting late. The events are listed under "Events".

Options:

- `--since-now`: leave out the `SNAPSHOT`; only what happens from now on.

Example:

```sh
vidctrl-client events --since-now --json
```

It prints, for example:

```
Job 1: Converting. /home/alice/Videos/party.mov
Job 1: 42%, about 21 min left.
Job 0: Done. /home/alice/Videos/beach.mov
  Result: /home/alice/Videos/Converted/beach_av1-crf35.mp4, 598.0 MB
  Usual quality (crf 35; VMAF 96.4; XPSNR 43.1 dB). Expected at 14% of the original's size.
The queue has nothing more to do.
```

With `--json`: one JSON object per line: `event` (string, the event's code), `time` (string, UTC, ISO 8601; not on `APP_CLOSING`) and the event's fields.

```json
{"event":"JOB_PROGRESS","time":"2026-10-23T14:05:09.120Z","job":1,"fraction":0.42,"remainingSeconds":1260.0}
```

#### Report each file as it finishes

```sh
vidctrl-client queue                          # opens the window first, if it is not open
vidctrl-client events --since-now --json      # in the background
```

Read its lines as they come. On each `JOB_FINISHED`, tell the person about that job: its `status`, `outputPath`, `outputBytes`, `quality.outcome` and `needsALook`. On `QUEUE_IDLE` the queue has nothing more to do: stop following. On `APP_CLOSING` the window closed.

#### Events

`vidctrl-client events` tells these, each with `event`, its code, and, but on `APP_CLOSING`, `time`:

| Event | Fields | Meaning |
|---|---|---|
| `SNAPSHOT` | `videos` (list of Video), `jobs` (list of Job), `paused` (bool), `busy` (bool) | How everything stands; first, unless `--since-now`. |
| `VIDEO_ADDED` | a Video | A video came into the list. |
| `VIDEO_READY` | a Video | It has been read. |
| `VIDEO_UNREADABLE` | a Video | It is not a video FFmpeg can open. |
| `VIDEO_REMOVED` | `video` (int) | It was taken off the list; its file stays on disk. |
| `JOB_ADDED` | a Job | A job came into the queue. |
| `JOB_CHECKING` | `job` (int), `attempt` (int) | Choosing its quality: this try. |
| `JOB_STARTED` | a Job | Converting it begins. |
| `JOB_PROGRESS` | `job` (int), `fraction` (number, 0 to 1), `remainingSeconds` (number, optional) | How far it is; at most once a second for each job. |
| `JOB_FINISHED` | a Job | It ended: `DONE`, `SKIPPED`, `FAILED` or `CANCELLED`. |
| `JOB_REMOVED` | `job` (int) | It was taken out of the queue; any result stays on disk. |
| `QUEUE_PAUSED` | none | The queue was paused, in the window or by `pause`. |
| `QUEUE_RESUMED` | none | It goes on again. |
| `QUEUE_IDLE` | none | The queue has nothing more to do. |
| `COMPARE_FINISHED` | `job` (int), `status` (`MEASURED` or `FAILED`), `closeness`, `vmaf` (optional), `xpsnr`; or `errorLines` | "Compare with the original" ended, in the window or by `compare`. |
| `APP_CLOSING` | none | The window is closing; `events` and `wait` exit 4. |

### `vidctrl-client goals`

The goals and their options, as this computer offers them.

The same goals as those below, with only the options this computer can use: the speed of Archive, for one, is offered only where the graphics card can encode. An option left out here is refused by `queue add`, but for the choice the goal makes here anyway.

Examples:

```sh
vidctrl-client goals
vidctrl-client goals --json
```

It prints, for example:

```
Archive, no quality loss: --goal archive
  Format: --opt codec=…
    Smallest file: av1 (the default). Plays on computers (Macs from M1) and newer devices: iPhone 15 Pro and later, TVs from about 2020.
    Works everywhere: hevc. The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included.
  Speed: --opt speed=…
    Thorough: cpu (the default). The processor encodes: slower, and the file is the smallest.
    Fast: gpu. The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger.
```

With `--json`: `goals` (list of Goal), in the order of the panel.

```json
{"goals":[{"id":"archive.master","scenario":"archive","title":"Archive","subtitle":"no quality loss","options":[{"id":"codec","title":"Format","defaultChoice":"av1","advanced":false,"choices":[{"id":"av1","label":"Smallest file","hint":"Plays on computers (Macs from M1) and newer devices: iPhone 15 Pro and later, TVs from about 2020."},{"id":"hevc","label":"Works everywhere","hint":"The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included."}]},{"id":"speed","title":"Speed","defaultChoice":"cpu","advanced":false,"choices":[{"id":"cpu","label":"Thorough","hint":"The processor encodes: slower, and the file is the smallest."},{"id":"gpu","label":"Fast","hint":"The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger."}]}]}]}
```

Each goal, by the name `--goal` takes, with its options and their choices. The full id (as `archive.master`) is taken too. An option is offered only where it makes a difference on this computer: `vidctrl-client goals` shows which are here; another is taken only with the choice the goal makes here anyway. A file with no picture is `UNSUPPORTED` by every goal but "Get the sound" and "Remove personal data".

#### Archive, no quality loss: `--goal archive`

Full id: `archive.master`.

Camera videos take far less space and look the same as the originals. Dates, camera details, sound and colours are kept.

Every video is converted, its quality chosen by measuring (see "Quality outcomes"). One whose result would keep over 80% of the original's size is kept as it is: its job ends `SKIPPED` with the outcome `NOT_WORTH_IT`. A sample is made all the same.

- `--opt codec=…`: Format.
  - `av1`: Smallest file (the default). Plays on computers (Macs from M1) and newer devices: iPhone 15 Pro and later, TVs from about 2020.
  - `hevc`: Works everywhere. The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included.

- `--opt speed=…`: Speed.
  - `cpu`: Thorough (the default). The processor encodes: slower, and the file is the smallest.
  - `gpu`: Fast. The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger.

#### Save space, good enough: `--goal space`

Full id: `space.small`.

For call recordings and other videos kept just in case: much smaller files that are still good to watch. Fine details soften. At most 1080p and 30 frames a second: larger videos are reduced.

Every video with a picture is converted.

It has no options.

#### Edit in DaVinci Resolve, Resolve Studio: `--goal resolve.studio`

Makes videos open with picture and sound in Resolve on Linux. Usually only the sound needs fixing, which takes seconds.

A video Resolve already opens is left as it is (plan `SKIP`); often only the sound needs converting (`AUDIO_ONLY`).

- `--opt convertVideo=…`: Also convert the picture. Turn on if videos play choppily, as they can without an NVIDIA graphics card.
  - `no` (the default).
  - `yes`.

- `--opt quality=…`: File size.
  - `smallest`.
  - `smaller`.
  - `balanced`: Recommended (the default).
  - `best`: Best quality.

- `--opt codec=…`: Editing format (under "More options…").
  - `prores` (the default).
  - `dnxhr`.

#### Edit in DaVinci Resolve, Free Resolve: `--goal resolve.free`

Makes videos open with picture and sound in Resolve on Linux. The picture is converted too. Files become much larger.

A video Resolve already opens is left as it is (plan `SKIP`); often only the sound needs converting (`AUDIO_ONLY`).

- `--opt quality=…`: File size.
  - `smallest`.
  - `smaller`.
  - `balanced`: Recommended (the default).
  - `best`: Best quality.

- `--opt codec=…`: Editing format (under "More options…").
  - `prores` (the default).
  - `dnxhr`.

#### Get the sound: `--goal audio`

Full id: `audio.extract`.

Saves the sound of a video as a separate file.

Takes the first sound track; a video without sound is `UNSUPPORTED`. Sound that fits the file type is copied as it is.

- `--opt format=…`: File type.
  - `original`: As it is (the default).
  - `mp3`.
  - `m4a`.
  - `wav`.
  - `flac`.

#### Remove personal data: `--goal privacy`

Full id: `privacy.clean`.

Removes the hidden notes about place, date, camera and author before you share a video. What is seen and heard stays the same.

Each result is a new copy without the hidden notes; the original stays as it is. `quick` copies picture and sound as they are (`REMUX`), `thorough` converts them again (`ENCODE`). Sound files are taken too.

- `--opt mode=…`: How thoroughly. Thorough rebuilds the picture and sound from scratch. It takes much longer and is the safest.
  - `quick` (the default).
  - `thorough`.

#### Change file type: `--goal remux`

Full id: `remux.container`.

Puts the video into another kind of file in seconds, without touching the picture quality.

A video already of that file type is left as it is (`SKIP`); sound the new type cannot hold is converted (`AUDIO_ONLY`); the picture never is.

- `--opt format=…`: File type.
  - `mp4` (the default).
  - `mkv`.
  - `mov`.

### `vidctrl-client manual`

Prints the guide to every command, goal and code.

It needs no window and opens none. Each command's examples, text output and JSON sample are in its help: `vidctrl-client help <command>`.

Examples:

```sh
vidctrl-client manual
vidctrl-client manual --json
```

It prints, for example:

```
# vidctrl-client
…
```

With `--json`: the same as data: `commands` (list: `name`, `arguments`, `description`, `options`), `goals` (list: like Goal, with `goal`, the name `--goal` takes, and a `hint` for each goal and option), `exitCodes` (object: code to meaning), `events` (list: `name`, `fields`, `description`) and `codes` (object: for each kind of code, as the manual's "Codes" lists them, a list of `code` and `description`). Here with one of each:

```json
{"commands":[{"name":"resume","arguments":"","description":"lets a paused queue go on","options":[]}],"goals":[{"id":"archive.master","scenario":"archive","goal":"archive","title":"Archive","subtitle":"no quality loss","hint":"Camera videos take far less space and look the same as the originals. Dates, camera details, sound and colours are kept.","options":[{"id":"codec","title":"Format","hint":"","defaultChoice":"av1","advanced":false,"choices":[{"id":"av1","label":"Smallest file","hint":"Plays on computers (Macs from M1) and newer devices: iPhone 15 Pro and later, TVs from about 2020."},{"id":"hevc","label":"Works everywhere","hint":"The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included."}]},{"id":"speed","title":"Speed","hint":"","defaultChoice":"cpu","advanced":false,"choices":[{"id":"cpu","label":"Thorough","hint":"The processor encodes: slower, and the file is the smallest."},{"id":"gpu","label":"Fast","hint":"The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger."}]}]}],"exitCodes":{"0":"Done. For `wait`: every job ended done or skipped, those worth a look by eye included (flagged in the output)."},"events":[{"name":"SNAPSHOT","fields":"`videos` (list of Video), `jobs` (list of Job), `paused` (bool), `busy` (bool)","description":"How everything stands; first, unless `--since-now`."}],"codes":{"jobStatus":[{"code":"WAITING","description":"Waiting. In the queue, its turn not come yet."}]}}
```

### `vidctrl-client help [command]`

The commands, or one command's details.

Without a command, the short list `--help` prints. It needs no window and opens none.

Example:

```sh
vidctrl-client help queue add
```

It prints, for example:

```
### `vidctrl-client queue add <videos…>`
…
```

With `--json`: the same text; `help` has no JSON.

## What `--json` gives, in full

Each field is named with its JSON type; one marked "optional" is left out when not known.

### Status

How the window stands.

- `state` (string): `STARTING`, `READY` or `FFMPEG_MISSING`, see "Window states".
- `version` (string): VidCtrl's version; empty in a development build.
- `busy` (bool): the queue is working through jobs.
- `paused` (bool): the queue is paused in the window.
- `jobs` (object): how many jobs there are in each status, by its code, as `{"WAITING": 2, "DONE": 1}`.

### Goal

A goal, with the options this computer offers.

- `id` (string): the goal's full id, as `archive.master`; `--goal` takes it always.
- `scenario` (string): its kind, as `archive`; `--goal` takes it when the kind has one goal only.
- `title` (string): its name in the window.
- `subtitle` (string): what sets it apart from a like one; may be empty.
- `options` (list of Option).

### Option

One option of a goal: `--opt <id>=<choice>`.

- `id` (string).
- `title` (string): its name in the window.
- `defaultChoice` (string): the choice made when none is given.
- `advanced` (bool): under "More options…" in the window.
- `choices` (list of Choice).

### Choice

One choice of an option.

- `id` (string): what `--opt` takes.
- `label` (string): its name in the window.
- `hint` (string): what it trades away; may be empty.

### Video

A video in the window's list.

- `id` (int).
- `path` (string): the file, absolute.
- `status` (string): `PROBING`, `READY` or `UNREADABLE`, see "Video statuses".
- `sizeBytes` (int, optional).
- `durationSeconds` (number, optional).
- `width` (int, optional), `height` (int, optional): the picture.
- `videoCodec` (string, optional): the picture's format, as `hevc`.
- `audioCodecs` (list of string): one per sound track.
- `hdr` (bool).
- `preview` (Preview, optional): with `videos --goal`, and from `estimate`.

### Preview

What a goal would do to a video, as the list shows it.

- `goal` (string): the goal's full id.
- `plan` (string): what it would do, see "Plans".
- `expectedBytes` (int, optional): the result's expected size.
- `measured` (bool): the size was measured by encoding pieces, not calculated.
- `measuring` (bool): the window is measuring it now.
- `closeness` (string, optional): how close the result would look, see "Closeness".

### Job

A job in the queue.

- `id` (int).
- `videoId` (int): the video it was made from, which may be off the list by now.
- `path` (string): that video's file.
- `goal` (string): the goal's full id.
- `options` (object): every option of the goal and the choice it really makes on this computer: `speed` is `cpu` where the graphics card cannot encode that format. Tell the person these, not what was asked.
- `sample` (string, optional): `START` or `MIDDLE` for a sample, see "Samples".
- `status` (string): see "Job statuses".
- `fraction` (number, optional): how far it is, 0 to 1, while converting.
- `remainingSeconds` (number, optional): the time left, while converting.
- `attempt` (int, optional): while choosing the quality, which try this is.
- `outputPath` (string, optional): where the result goes, once known; the result is there once the job is `DONE`.
- `outputBytes` (int, optional): the result's size, once done.
- `quality` (Quality, optional): how its quality was chosen.
- `needsALook` (bool): worth a look by eye, see `BELOW_TARGET`.
- `errorLines` (list of string): why it failed, in FFmpeg's last words.

### Quality

How a job's quality was chosen: Archive measures each video before converting it and compares pieces of the result with the original.

- `outcome` (string): see "Quality outcomes".
- `value` (int, optional): the quality number chosen (lower is better).
- `standardValue` (int, optional): the goal's usual number.
- `vmaf` (number, optional): VMAF of the poorest piece; 95 and more looks the same.
- `xpsnr` (number, optional): XPSNR of the poorest piece, in dB.
- `share` (number): the expected size as a share of the original's, 0 to 1.

### Outcome

How a job ended, as `wait` tells it.

- `jobId` (int).
- `path` (string): the video's file.
- `status` (string): `DONE`, `SKIPPED`, `FAILED`, `CANCELLED` or `REMOVED`, see "Job statuses".
- `outputPath` (string, optional): the result, when done.
- `needsALook` (bool): worth a look by eye, see `BELOW_TARGET`.

## Codes in full

Every code by where it is found, with the words the client prints for people and what it means. The events are under "Events".

### Job statuses

Job and Outcome `status`, Status `jobs` keys:

- `WAITING`: Waiting. In the queue, its turn not come yet.
- `RUNNING`: Converting. Being converted now, or its quality being chosen (`attempt`).
- `PAUSED`: Paused. Under way, held because the queue is paused in the window.
- `DONE`: Done. The result is at `outputPath`. Tell the person, and say so when `needsALook` is true. `compare <job>` says how close it looks to the original.
- `SKIPPED`: Nothing to do. Nothing was written: the video already met the goal, the goal can do nothing with it (plan `UNSUPPORTED`), or converting would hardly make it smaller (outcome `NOT_WORTH_IT`). Counts as finished, not as a failure.
- `FAILED`: Failed. It could not be converted; `errorLines` says why. The person can try it again in the window, as `queue retry <job>` does.
- `CANCELLED`: Cancelled. Stopped before it was done, in the window or by `cancel`. `wait` counts it as a failure; `queue retry <job>` tries it again.
- `REMOVED`: Taken out of the queue (the file stays on disk). Only in `wait`, for a job taken out of the queue while it waited. Not a failure.

### Video statuses

Video `status`:

- `PROBING`: Being read. VidCtrl is learning its size, length, picture and sound.
- `READY`: Ready. It can be queued.
- `UNREADABLE`: Cannot be read: not a video FFmpeg can open. It cannot be queued.

### Plans

Preview `plan`:

- `SKIP`: Already fine: nothing to do. Queued, the job ends `SKIPPED` and writes no file.
- `REMUX`: Copied into a new file type, untouched. Quick: the picture and sound are copied.
- `AUDIO_ONLY`: Only the sound is converted. Quick: the picture is copied.
- `ENCODE`: Converted. The picture is converted: this takes time.
- `UNSUPPORTED`: This goal cannot do anything with it. For example, a goal for pictures given a sound file. Queued, the job ends `SKIPPED`.
- `KEPT_AS_IS`: Kept as it is: converting would hardly make it smaller. Archive only; the job ends `SKIPPED`.

### Closeness

Preview `closeness`, `compare`:

- `SAME`: Looks the same as the original. VMAF 95 or more on the poorest piece.
- `VERY_CLOSE`: Very close to the original. VMAF 93 or more.
- `DIFFERS`: Differences may be visible. Below that: worth a look.

### Quality outcomes

Quality `outcome`:

- `STANDARD`: Usual quality. The goal's usual quality was enough to look the same.
- `RAISED`: Raised quality: needed to look the same. A better quality than usual was needed, and the file is larger for it.
- `BELOW_TARGET`: Worth a look by eye: even the best quality falls a little short somewhere. Converted anyway, and the result's name ends in `-check`. Tell the person to look at it by eye beside the original. The job is `DONE` and `needsALook` is true; `wait` still exits 0.
- `NOT_WORTH_IT`: Kept as it is: converting would hardly make it smaller. The job ends `SKIPPED` and nothing is written. In the window, "Convert anyway" in the job's ⋯ menu converts it all the same, as `queue convert-anyway <job>` does.

### Window states

Status `state`:

- `STARTING`: The window has just opened and looks for FFmpeg.
- `READY`: Open and ready.
- `FFMPEG_MISSING`: Open, but it found no FFmpeg; the window says what to do. Every command but `status` fails with `FFMPEG_MISSING`.

### Adding

`add`'s `result`, `queue add`'s `skipped[].reason`:

- `ADDED`: Added to the list now.
- `KNOWN`: In the list already; not added twice.
- `NOT_FOUND`: No file there, nor a folder with videos. As a `skipped` reason of `queue add`: nothing found there, or the video was taken off the list meanwhile.
- `UNREADABLE`: In the list, but not a video FFmpeg can open; it cannot be queued.

### Samples

Job `sample`:

- `START`: Ten seconds from the start (`--sample start`).
- `MIDDLE`: Ten seconds from the middle (`--sample middle`).

### Comparisons

`compare`'s and `COMPARE_FINISHED`'s `status`:

- `MEASURED`: Compared: `closeness`, `xpsnr` and, where measured, `vmaf` say how close.
- `FAILED`: Only in `COMPARE_FINISHED`: it could not be compared; `errorLines` says why. `compare` exits 5 instead.

### Details

`details[].group`:

- `FILE`: The file as a whole: its type, size and length.
- `VIDEO`: A picture track.
- `AUDIO`: A sound track.
- `SUBTITLE`: A subtitle track.
- `TIMECODE`: A timecode track, as cameras write.
- `DATA`: A data track, such as a camera's notes.
- `ATTACHMENT`: A file carried inside, such as a font or a cover.
- `CHAPTERS`: The chapters.

### Errors

`error.code`, with the exit code:

- `BAD_ARGUMENT`: a command, goal, option, choice or value that is not valid (exit 5).
- `NOT_FOUND`: no such video or job (exit 5).
- `BUSY`: the window cannot do that right now (exit 5).
- `UNKNOWN_METHOD`: the open window is of another version and does not know the request (exit 5).
- `FFMPEG_MISSING`: the window could not find FFmpeg and shows what to do (exit 6).
- `UNAUTHORIZED`: the window is open but refused the connection or did not answer; no other window is started (exit 2).
- `NOT_RUNNING`: the window is not open and could not be opened (exit 2).
- `APP_CLOSED`: the window closed meanwhile (exit 4).
- `TIMEOUT`: `--timeout` passed; the jobs go on in the window (exit 3).
- `UNEXPECTED`: the client itself went wrong; the message says how (exit 5).
