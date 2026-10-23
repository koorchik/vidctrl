# vidctrl-client

`vidctrl-client` controls the open VidCtrl window from a terminal, a script or an AI agent. `vidctrl-client manual` prints this guide; `vidctrl-client help <command>` prints one command's part.

## Quick start

VidCtrl is open on this computer, and the person watches its window. The program `vidctrl-client` controls it: it adds videos to the window's list and queues conversions there.

- Run `vidctrl-client manual` first: it explains every command, the goals and what the results mean. Add `--json` to a command to read its answer as JSON.
- Finding the videos is your job (with `find`, `du` or the like). Give their paths to `vidctrl-client add`, or straight to `vidctrl-client queue add --goal <goal>`.
- The window converts one video at a time, and that can take hours. To know when it ends, run `vidctrl-client wait` in the background (or follow `vidctrl-client events`), and tell the person when it returns: each result, and any marked "worth a look by eye".
- Never delete, move or rename any file. "Remove" only takes a video off the list or a job out of the queue.

## What VidCtrl is

VidCtrl converts videos by goal: "Archive" makes camera videos far smaller while they look the same, "Save space" smaller still, "Edit in DaVinci Resolve" makes them open there, and so on. It is a window on this computer; `vidctrl-client` is a client of that window. It changes what the window shows, exactly as if the person had done it with the mouse.

- **Videos.** The window keeps a list of videos. Adding one (`vidctrl-client add`) is like dropping it on the window: VidCtrl reads it to learn its size, length, picture and sound. Each file is in the list once. Videos just added become the window's selection, as dropped ones do.
- **Goals.** What to make of a video, each with a few options (see "Goals"). They are the goals and options of the window's panel, by id; nothing finer, such as FFmpeg settings or quality numbers, can be given.
- **The queue and its jobs.** Queuing a video with a goal (`vidctrl-client queue add`) makes a job. A job is a snapshot: it keeps the video's details, the goal, its options and the output folder as they were when it was queued, so later changes to the list or the panel do not touch it; taking its video off the list leaves it in the queue. The queue starts by itself and converts one job at a time, in order.
- **The window shows everything.** Every video and job this program adds appears in the window. The person may act there too (pause the queue, add videos, take jobs out), and this program sees it.
- **Nothing converts without the window.** This program never converts anything itself. When no window is open, every command but `status`, `manual` and `help` opens one first ("Starting VidCtrl…" on stderr; it can take up to 30 seconds). Closing the window stops its conversions.
- **The originals stay as they are.** A result is a new file, by default in a folder named `Converted` beside its video. Its name carries the settings: `beach.mov` becomes `Converted/beach_av1-crf35.mp4`, and a second result with the same name gets ` (2)`. A result is written under a hidden name ending in `.part` and gets its own name only once complete, so a file with a result's name is always whole.
- **Samples.** A sample job converts 10 seconds of a video, from its start or its middle, with the same settings as the whole would get, into a `Samples` folder inside the output folder: `Converted/Samples/beach_av1-crf35_sample10s.mp4` (`_sample10s-mid` from the middle).
- **Ids.** Videos and jobs are numbered from 0, each in the order they were added. The numbers, the list and the queue last while the window is open; a new window starts again from 0, with an empty list and queue.

## What VidCtrl never does

VidCtrl deletes no file: "remove" takes a video off the list or a job out of the queue, and the file stays on disk.

- Results are new files. No command changes, moves or renames a file that is there, original or result. "Remove", here as in the window, takes a video off the list (`vidctrl-client remove`) or a job out of the queue; every file stays where it is.
- No command overrules the person: none closes the window, changes the goal shown in its panel, its remembered settings, its look or its language.
- Never delete, move or rename any file. Leave every file to the person.

## Commands

How every command works:

- `vidctrl-client <command> [arguments] [options]`; options may come before or after the arguments.
- `--json` prints the answer as one JSON document on stdout (`events`: one per line). Without it, lines for people. The JSON has ids and numbers, and English words beside the ids in fields ending in `Text`. A value that is not known is left out, never `null`; only `cancel` answers `null`, when nothing was cancelled.
- `--no-start`: do not open the window when it is not open; exit 2 instead.
- `--help` prints the command's part of this guide.
- Videos are given by id or by path, jobs by id. A reference made only of digits is an id: a file named `3` in the current folder is given as `./3`.
- Paths may be relative or start with `~`: the client makes them absolute from the current folder before sending them.
- A goal is given by its id (`--goal archive`), its options with `--opt option=choice`, once for each (`--opt codec=hevc --opt speed=gpu`). An unknown goal, option or choice is refused with the valid ones named. So is an option this computer does not offer (`vidctrl-client goals` lists those it does), unless its choice is the one the goal makes here anyway: `--opt speed=cpu` where the graphics card cannot encode. A script may name the defaults on every computer.
- Errors go to stderr, as a line for people, or with `--json` as `{"error": {"kind": "...", "message": "..."}}`; the exit code tells what kind (see "Exit codes"). The kinds:
  - `badArgument`: a command, goal, option, choice or value that is not valid (exit 5).
  - `notFound`: no such video or job (exit 5).
  - `busy`: the window cannot do that right now (exit 5).
  - `unknownMethod`: the open window is of another version and does not know the request (exit 5).
  - `ffmpegMissing`: the window could not find FFmpeg and shows what to do (exit 6).
  - `unauthorized`: the window refused the connection (exit 2).
  - `notRunning`: the window is not open and could not be opened (exit 2).
  - `appClosed`: the window closed meanwhile (exit 4).
  - `timeout`: `--timeout` passed; the jobs go on in the window (exit 3).
  - `unexpected`: the client itself went wrong; the message says how (exit 5).
- Start the window before running commands side by side: two commands started at the same moment with no window open can each open one. Any command but `status` opens it, for example `vidctrl-client queue`; then run `vidctrl-client events` in the background beside the others.

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

With `--json`: `videos` (list): for each video found, and each path where nothing was, `path` (string), `id` (int, optional: absent when nothing was found) and `result` (string): `added`, `known` (in the list already), `unreadable` (in the list, but not a video FFmpeg can open) or `notFound`.

```json
{"videos":[{"path":"/home/alice/Videos/beach.mov","id":0,"result":"added"},{"path":"/home/alice/Videos/party.mov","id":1,"result":"known"},{"path":"/home/alice/Videos/notes.mov","id":3,"result":"unreadable"},{"path":"/home/alice/Videos/missing.mov","result":"notFound"}]}
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
{"videos":[{"id":0,"path":"/home/alice/Videos/beach.mov","status":"ready","statusText":"Ready","sizeBytes":4200000000,"durationSeconds":754.2,"width":3840,"height":2160,"videoCodec":"hevc","audioCodecs":["aac"],"hdr":false,"preview":{"goal":"archive.master","plan":"encode","planText":"Converted","expectedBytes":610000000,"measured":true,"measuring":false,"closeness":"same","closenessText":"Looks the same as the original"}}]}
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

With `--json`: `info` (Video): the video; for a job, its result, with the `id` of the video it was made from. `details` (list): for each track and the file, `title` (string) and `rows` (list of [label, value], both strings). With `--raw`, `raw` (object) instead of `details`: ffprobe's report as it gave it.

```json
{"info":{"id":0,"path":"/home/alice/Videos/beach.mov","status":"ready","statusText":"Ready","sizeBytes":4200000000,"durationSeconds":754.2,"width":3840,"height":2160,"videoCodec":"hevc","audioCodecs":["aac"],"hdr":false},"details":[{"title":"Video track 1","rows":[["Codec","H.265 / HEVC (High Efficiency Video Coding) · Main 10 · level 5.1"],["Resolution","3840×2160"],["Frame rate","25 fps (25/1)"],["Bit depth","10-bit"],["Chroma subsampling","4:2:0"]]},{"title":"Audio track 1","rows":[["Codec","AAC (Advanced Audio Coding) · LC"],["Channels","2 (stereo)"],["Sample rate","48 kHz"]]},{"title":"File","rows":[["Container","QuickTime / MOV"],["Size","4.20 GB"]]}]}
```

Errors:

- A video that is not in the list, a job that is not done, or a result that cannot be read where it was written: exit 5 (`notFound`). A video FFmpeg cannot open: exit 5.

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
{"videos":[{"id":0,"path":"/home/alice/Videos/beach.mov","status":"ready","statusText":"Ready","sizeBytes":4200000000,"durationSeconds":754.2,"width":3840,"height":2160,"videoCodec":"hevc","audioCodecs":["aac"],"hdr":false,"preview":{"goal":"archive.master","plan":"encode","planText":"Converted","expectedBytes":610000000,"measured":true,"measuring":false,"closeness":"same","closenessText":"Looks the same as the original"}}]}
```

Errors:

- While the queue converts, or when converting starts before it has measured them all: `busy`, exit 5 ("Videos are being converted; the window measures when the queue is idle."). Measure before queuing, or after `vidctrl-client wait`.
- A video that is not in the list (`vidctrl-client add` it first), one FFmpeg cannot open, or an unknown goal, option or choice: exit 5.

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

With `--json`: `goal` (string): the goal's id; `options` (object): every option of the goal and the choice made on this computer, as in Job; `added` (list of Job): the new jobs; `alreadyQueued` (list of int): the videos that were queued already; `skipped` (list): `video` (int or string, as given) and `reason` (string: `unreadable` or `notFound`).

```json
{"goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"added":[{"id":2,"videoId":2,"path":"/home/alice/Videos/dog.mp4","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"waiting","statusText":"Waiting","needsALook":false,"errorLines":[]}],"alreadyQueued":[0],"skipped":[{"video":3,"reason":"unreadable"}]}
```

Errors:

- An unknown goal, option or choice, a choice of an option this computer does not offer other than the one made here anyway, a video id not in the list, or a `--subfolder` that is not one folder's name: exit 5, with the valid ones named.

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
{"job":{"id":2,"videoId":2,"path":"/home/alice/Videos/dog.mp4","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"waiting","statusText":"Waiting","needsALook":false,"errorLines":[]}}
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

For a job that ended `skipped` with the outcome `notWorthIt`: Archive found that converting would hardly make the file smaller. A new job converts it all the same, at the quality found for it, with the same goal, options and folder. Ask the person first: the result is nearly as large as the original.

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
{"added":[{"id":4,"videoId":3,"path":"/home/alice/Videos/trip.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"waiting","statusText":"Waiting","needsALook":false,"errorLines":[]}],"alreadyQueued":false}
```

Errors:

- A job that is not in the queue, or one that was not kept as it is: exit 5.

### `vidctrl-client queue convert-whole <job>`

Queues the whole video after a sample, as the window's button does.

For a sample job, as "Convert the whole video" under it in the window: a new job converts the whole video the sample was taken from, with the same goal, options and folder, into the output folder rather than `Samples`.

Example:

```sh
vidctrl-client queue convert-whole 3 --json
```

It prints, for example:

```
Job 4: Queued. /home/alice/Videos/trip.mov
```

With `--json`: `added` (list of Job) and `alreadyQueued` (bool), as for `queue convert-anyway`.

Errors:

- A job that is not in the queue, or not a sample: exit 5.

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

It answers once the job has stopped; the queue goes on with the next one. The job stays in the queue as `cancelled`; no result is written for it, and the original stays as it is. `vidctrl-client queue retry <job>` tries it again.

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

Its status, goal and options, its result and size once done, and how its quality was chosen: the outcome and the scores of the poorest piece. A job worth a look by eye (`needsALook`, the outcome `belowTarget`) has a name ending in `-check`: tell the person to look at it beside the original.

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
{"job":{"id":1,"videoId":1,"path":"/home/alice/Videos/party.mov","goal":"archive.master","options":{"codec":"av1","speed":"cpu"},"status":"done","statusText":"Done","outputPath":"/home/alice/Videos/Converted/party_av1-crf20-check.mp4","outputBytes":2100000000,"quality":{"outcome":"belowTarget","outcomeText":"Worth a look by eye: even the best quality falls a little short somewhere","value":20,"standardValue":35,"vmaf":93.8,"xpsnr":40.2,"share":0.52},"needsALook":true,"errorLines":[]},"command":"ffmpeg -hide_banner -i /home/alice/Videos/party.mov -map 0:v:0 -map '0:a?' -map_metadata 0 -c:v libsvtav1 -preset 5 -crf 20 -svtav1-params tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0:keyint=10s:scd=1 -pix_fmt yuv420p10le -c:a copy -movflags +faststart+use_metadata_tags -metadata major_brand= -metadata minor_version= -metadata compatible_brands= -f mp4 /home/alice/Videos/Converted/party_av1-crf20-check.mp4"}
```

Errors:

- A job that is not in the queue: exit 5.

### `vidctrl-client compare <job>`

Compares a result with its original, as the window's menu does.

As "Compare with the original" in a done job's ⋯ menu: VidCtrl compares the result with its original frame by frame (a sample with the same piece of it) and says how close it looks, by VMAF where this FFmpeg measures it, otherwise by XPSNR (see "Closeness"). It takes about as long as the video lasts, or longer, and one comparison runs at a time. The window shows it under the job, and the person may stop it there.

Offered only where each frame of the result stands for one of the original: not after the picture was made smaller, its frame rate changed or its HDR turned into SDR ("Save space" makes 4K videos 1080p). Asked again while that job is being compared, it waits for the same comparison.

Options:

- `--no-wait`: answer at once; the `compare-finished` event (`vidctrl-client events`) tells the result.

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

With `--json`: `job` (int); `status` (string): `measured`; `closeness` (string, see "Closeness") and `closenessText` (string) in words; `xpsnr` (number, in dB); `vmaf` (number, optional: where this FFmpeg measures it). With `--no-wait`, `{"started": true}`.

```json
{"job":1,"status":"measured","closeness":"veryClose","closenessText":"Very close to the original","xpsnr":40.6,"vmaf":94.1}
```

Errors:

- A job that is not done, or whose frames do not pair with the original's, or an FFmpeg without the `xpsnr` filter: exit 5, saying why.
- Another job being compared: `busy`, exit 5; ask again once it has ended.
- The comparison failed (exit 5, with FFmpeg's words), or was stopped in the window (exit 5).

### `vidctrl-client status`

Whether VidCtrl is open, and how its queue stands.

It never opens the window. A window that has just opened is `starting` while it looks for FFmpeg, then `ready`, or `ffmpegMissing` when it found none.

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
{"running":true,"state":"ready","version":"1.2.0","busy":true,"paused":false,"jobs":{"done":1,"running":1,"waiting":1}}
```

### `vidctrl-client wait [jobs…]`

Waits until the jobs are finished, and says how each ended.

Without job ids, until no job is waiting or converting; with ids, until those have ended. Jobs added meanwhile, by this program or the person, count too. The rules are under "Waiting and events". Conversions can take hours: run it in the background.

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
{"outcomes":[{"jobId":0,"path":"/home/alice/Videos/beach.mov","status":"done","statusText":"Done","outputPath":"/home/alice/Videos/Converted/beach_av1-crf35.mp4","needsALook":false},{"jobId":1,"path":"/home/alice/Videos/party.mov","status":"done","statusText":"Done","outputPath":"/home/alice/Videos/Converted/party_av1-crf20-check.mp4","needsALook":true}]}
```

Errors:

- A job id not in the queue: exit 5.

### `vidctrl-client events`

Tells what happens in the window, as it happens.

It goes on until the window closes, then exits 4: stop it yourself when you no longer need it. First it tells how everything stands (`snapshot`), so nothing is missed by starting late. The events are listed under "Waiting and events".

Options:

- `--since-now`: leave out the `snapshot`; only what happens from now on.

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

With `--json`: one JSON object per line: `event` (string), `time` (string, UTC, ISO 8601; not on `app-closing`) and the event's fields.

```json
{"event":"job-progress","time":"2026-10-23T14:05:09.120Z","job":1,"fraction":0.42,"remainingSeconds":1260.0}
```

### `vidctrl-client goals`

The goals and their options, as this computer offers them.

The same goals as "Goals" below, with only the options this computer can use: the speed of Archive, for one, is offered only where the graphics card can encode. An option left out here is refused by `queue add`, but for the choice the goal makes here anyway.

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

### `vidctrl-client manual`

Prints this guide.

It needs no window and opens none.

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

With `--json`: the same as data: `commands` (list: `name`, `arguments`, `description`, `options`), `goals` (list: like Goal, with `goal`, the name `--goal` takes, and a `hint` for each goal and option), `exitCodes` (object: code to meaning) and `events` (list: `name`, `fields`, `description`).

### `vidctrl-client help [command]`

The commands, or one command's part of this guide.

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

### What `--json` gives

The shapes the answers and events are made of. Each field is named with its JSON type; one marked "optional" is left out when not known.

#### Status

How the window stands.

- `state` (string): `starting`, `ready` or `ffmpegMissing`.
- `version` (string): VidCtrl's version; empty in a development build.
- `busy` (bool): the queue is working through jobs.
- `paused` (bool): the queue is paused in the window.
- `jobs` (object): how many jobs there are in each status, as `{"waiting": 2, "done": 1}`.

#### Goal

A goal, with the options this computer offers.

- `id` (string): the goal's full id, as `archive.master`; `--goal` takes it always.
- `scenario` (string): its kind, as `archive`; `--goal` takes it when the kind has one goal only.
- `title` (string): its name in the window.
- `subtitle` (string): what sets it apart from a like one; may be empty.
- `options` (list of Option).

#### Option

One option of a goal: `--opt <id>=<choice>`.

- `id` (string).
- `title` (string): its name in the window.
- `defaultChoice` (string): the choice made when none is given.
- `advanced` (bool): under "More options…" in the window.
- `choices` (list of Choice).

#### Choice

One choice of an option.

- `id` (string): what `--opt` takes.
- `label` (string): its name in the window.
- `hint` (string): what it trades away; may be empty.

#### Video

A video in the window's list.

- `id` (int).
- `path` (string): the file, absolute.
- `status` (string): `probing` (being read), `ready` or `unreadable`; `statusText` (string) in words.
- `sizeBytes` (int, optional).
- `durationSeconds` (number, optional).
- `width` (int, optional), `height` (int, optional): the picture.
- `videoCodec` (string, optional): the picture's format, as `hevc`.
- `audioCodecs` (list of string): one per sound track.
- `hdr` (bool).
- `preview` (Preview, optional): with `videos --goal`, and from `estimate`.

#### Preview

What a goal would do to a video, as the list shows it.

- `goal` (string): the goal's full id.
- `plan` (string): what it would do, see "Plans"; `planText` (string) in words.
- `expectedBytes` (int, optional): the result's expected size.
- `measured` (bool): the size was measured by encoding pieces, not calculated.
- `measuring` (bool): the window is measuring it now.
- `closeness` (string, optional): how close the result would look, see "Closeness"; `closenessText` (string) in words.

#### Job

A job in the queue.

- `id` (int).
- `videoId` (int): the video it was made from, which may be off the list by now.
- `path` (string): that video's file.
- `goal` (string): the goal's full id.
- `options` (object): every option of the goal and the choice it really makes on this computer: `speed` is `cpu` where the graphics card cannot encode that format. Tell the person these, not what was asked.
- `sample` (string, optional): `start` or `middle` for a sample.
- `status` (string): see "Job statuses"; `statusText` (string) in words.
- `fraction` (number, optional): how far it is, 0 to 1, while converting.
- `remainingSeconds` (number, optional): the time left, while converting.
- `attempt` (int, optional): while choosing the quality, which try this is.
- `outputPath` (string, optional): where the result goes, once known; the result is there once the job is `done`.
- `outputBytes` (int, optional): the result's size, once done.
- `quality` (Quality, optional): how its quality was chosen.
- `needsALook` (bool): worth a look by eye, see `belowTarget`.
- `errorLines` (list of string): why it failed, in FFmpeg's last words.

#### Quality

How a job's quality was chosen: Archive measures each video before converting it and compares pieces of the result with the original.

- `outcome` (string): see "Quality outcomes"; `outcomeText` (string) in words.
- `value` (int, optional): the quality number chosen (lower is better).
- `standardValue` (int, optional): the goal's usual number.
- `vmaf` (number, optional): VMAF of the poorest piece; 95 and more looks the same.
- `xpsnr` (number, optional): XPSNR of the poorest piece, in dB.
- `share` (number): the expected size as a share of the original's, 0 to 1.

#### Outcome

How a job ended, as `wait` tells it.

- `jobId` (int).
- `path` (string): the video's file.
- `status` (string): `done`, `skipped`, `failed`, `cancelled` or `removed`; `statusText` (string) in words.
- `outputPath` (string, optional): the result, when done.
- `needsALook` (bool): worth a look by eye, see `belowTarget`.

## Goals

Each goal, by the name `--goal` takes, with its options and their choices. The full id (as `archive.master`) is taken too. An option is offered only where it makes a difference on this computer: `vidctrl-client goals` shows which are here; another is taken only with the choice the goal makes here anyway. A file with no picture is `unsupported` by every goal but "Get the sound" and "Remove personal data".

### Archive, no quality loss: `--goal archive`

Full id: `archive.master`.

Camera videos take far less space and look the same as the originals. Dates, camera details, sound and colours are kept.

Every video is converted, its quality chosen by measuring (see "Quality outcomes"). One whose result would keep over 80% of the original's size is kept as it is: its job ends `skipped` with the outcome `notWorthIt`. A sample is made all the same.

- `--opt codec=…`: Format.
  - `av1`: Smallest file (the default). Plays on computers (Macs from M1) and newer devices: iPhone 15 Pro and later, TVs from about 2020.
  - `hevc`: Works everywhere. The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included.

- `--opt speed=…`: Speed.
  - `cpu`: Thorough (the default). The processor encodes: slower, and the file is the smallest.
  - `gpu`: Fast. The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger.

### Save space, good enough: `--goal space`

Full id: `space.small`.

For call recordings and other videos kept just in case: much smaller files that are still good to watch. Fine details soften. At most 1080p and 30 frames a second: larger videos are reduced.

Every video with a picture is converted.

It has no options.

### Edit in DaVinci Resolve, Resolve Studio: `--goal resolve.studio`

Makes videos open with picture and sound in Resolve on Linux. Usually only the sound needs fixing, which takes seconds.

A video Resolve already opens is left as it is (plan `skip`); often only the sound needs converting (`audioOnly`).

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

### Edit in DaVinci Resolve, Free Resolve: `--goal resolve.free`

Makes videos open with picture and sound in Resolve on Linux. The picture is converted too. Files become much larger.

A video Resolve already opens is left as it is (plan `skip`); often only the sound needs converting (`audioOnly`).

- `--opt quality=…`: File size.
  - `smallest`.
  - `smaller`.
  - `balanced`: Recommended (the default).
  - `best`: Best quality.

- `--opt codec=…`: Editing format (under "More options…").
  - `prores` (the default).
  - `dnxhr`.

### Get the sound: `--goal audio`

Full id: `audio.extract`.

Saves the sound of a video as a separate file.

Takes the first sound track; a video without sound is `unsupported`. Sound that fits the file type is copied as it is.

- `--opt format=…`: File type.
  - `original`: As it is (the default).
  - `mp3`.
  - `m4a`.
  - `wav`.
  - `flac`.

### Remove personal data: `--goal privacy`

Full id: `privacy.clean`.

Removes the hidden notes about place, date, camera and author before you share a video. What is seen and heard stays the same.

Each result is a new copy without the hidden notes; the original stays as it is. `quick` copies picture and sound as they are (`remux`), `thorough` converts them again (`encode`). Sound files are taken too.

- `--opt mode=…`: How thoroughly. Thorough rebuilds the picture and sound from scratch. It takes much longer and is the safest.
  - `quick` (the default).
  - `thorough`.

### Change file type: `--goal remux`

Full id: `remux.container`.

Puts the video into another kind of file in seconds, without touching the picture quality.

A video already of that file type is left as it is (`skip`); sound the new type cannot hold is converted (`audioOnly`); the picture never is.

- `--opt format=…`: File type.
  - `mp4` (the default).
  - `mkv`.
  - `mov`.

## What the results mean

Each id and its words (the `...Text` fields in JSON), then what to make of it.

### Job statuses

- `waiting`: Waiting. In the queue, its turn not come yet.
- `running`: Converting. Being converted now, or its quality being chosen (`attempt`).
- `paused`: Paused. Under way, held because the queue is paused in the window.
- `done`: Done. The result is at `outputPath`. Tell the person, and say so when `needsALook` is true. `compare <job>` says how close it looks to the original.
- `skipped`: Nothing to do. Nothing was written: the video already met the goal, the goal can do nothing with it (plan `unsupported`), or converting would hardly make it smaller (outcome `notWorthIt`). Counts as finished, not as a failure.
- `failed`: Failed. It could not be converted; `errorLines` says why. The person can try it again in the window, as `queue retry <job>` does.
- `cancelled`: Cancelled. Stopped before it was done, in the window or by `cancel`. `wait` counts it as a failure; `queue retry <job>` tries it again.
- `removed`: Taken out of the queue (the file stays on disk). Only in `wait`, for a job taken out of the queue while it waited. Not a failure.

### Video statuses

- `probing`: Being read.
- `ready`: Read; it can be queued.
- `unreadable`: Not a video FFmpeg can open; it cannot be queued.

### Plans

What a goal would do to a video (Preview `plan`):

- `skip`: Already fine: nothing to do. Queued, the job ends `skipped` and writes no file.
- `remux`: Moved to a new file type, untouched. Quick: the picture and sound are copied.
- `audioOnly`: Only the sound is converted. Quick: the picture is copied.
- `encode`: Converted. The picture is converted: this takes time.
- `unsupported`: This goal cannot do anything with it. For example, a goal for pictures given a sound file. Queued, the job ends `skipped`.
- `keptAsIs`: Kept as it is: converting would hardly make it smaller. Archive only; the job ends `skipped`.

### Closeness

How close a result looks to its original (Preview `closeness`):

- `same`: Looks the same as the original. VMAF 95 or more on the poorest piece.
- `veryClose`: Very close to the original. VMAF 93 or more.
- `differs`: Differences may be visible. Below that: worth a look.

### Quality outcomes

How a job's quality was chosen (Quality `outcome`):

- `standard`: Usual quality. The goal's usual quality was enough to look the same.
- `raised`: Raised quality: needed to look the same. A better quality than usual was needed, and the file is larger for it.
- `belowTarget`: Worth a look by eye: even the best quality falls a little short somewhere. Converted anyway, and the result's name ends in `-check`. Tell the person to look at it by eye beside the original. The job is `done` and `needsALook` is true; `wait` still exits 0.
- `notWorthIt`: Kept as it is: converting would hardly make it smaller. The job ends `skipped` and nothing is written. In the window, "Convert anyway" in the job's ⋯ menu converts it all the same, as `queue convert-anyway <job>` does.

## Waiting and events

### Waiting

- `vidctrl-client wait` without ids waits until no job is waiting, converting or paused; with ids, until those have ended.
- The jobs it counts are those not yet ended when it starts, and any added or tried again while it waits, by this program or the person. Jobs that ended before it started do not count, so an old failure does not make every later `wait` exit 1.
- With nothing waiting when it starts, it exits 0 at once.
- A job taken out of the queue while it waits is told as `removed`, not as a failure; one cancelled is a failure.
- A paused queue keeps it waiting, as the person may continue it; it says so once on stderr.
- It may run for hours: run it in the background and tell the person when it returns.

### Exit codes

The same for every command:

| Code | Meaning |
|---|---|
| 0 | Done. For `wait`: every job ended done or skipped, those worth a look by eye included (flagged in the output). |
| 1 | At least one job failed or was cancelled. |
| 2 | VidCtrl is not open and could not be opened (or `--no-start` was given), or it refused the connection. |
| 3 | `--timeout` passed; the jobs go on in the window. |
| 4 | The window closed while waiting or following. |
| 5 | Bad arguments: an unknown command, goal, option, choice, video or job; or the client itself went wrong. |
| 6 | VidCtrl could not find FFmpeg; the window says what to do. |

### Events

`vidctrl-client events` tells these, each with `event` and, but on `app-closing`, `time`:

| Event | Fields | Meaning |
|---|---|---|
| `snapshot` | `videos` (list of Video), `jobs` (list of Job), `paused` (bool), `busy` (bool) | How everything stands; first, unless `--since-now`. |
| `video-added` | a Video | A video came into the list. |
| `video-ready` | a Video | It has been read. |
| `video-unreadable` | a Video | It is not a video FFmpeg can open. |
| `video-removed` | `video` (int) | It was taken off the list; its file stays on disk. |
| `job-added` | a Job | A job came into the queue. |
| `job-checking` | `job` (int), `attempt` (int) | Choosing its quality: this try. |
| `job-started` | a Job | Converting it begins. |
| `job-progress` | `job` (int), `fraction` (number, 0 to 1), `remainingSeconds` (number, optional) | How far it is; at most once a second for each job. |
| `job-finished` | a Job | It ended: `done`, `skipped`, `failed` or `cancelled`. |
| `job-removed` | `job` (int) | It was taken out of the queue; any result stays on disk. |
| `queue-paused` | none | The queue was paused, in the window or by `pause`. |
| `queue-resumed` | none | It goes on again. |
| `queue-idle` | none | The queue has nothing more to do. |
| `compare-finished` | `job` (int), `status` (`measured` or `failed`), `closeness`, `closenessText`, `vmaf` (optional), `xpsnr`; or `errorLines` | "Compare with the original" ended, in the window or by `compare`. |
| `app-closing` | none | The window is closing; `events` and `wait` exit 4. |

## Recipes

### Queue every video over 2 GB in ~/Videos, and tell me when it is done

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

### Report each file as it finishes

```sh
vidctrl-client queue                          # opens the window first, if it is not open
vidctrl-client events --since-now --json      # in the background
```

Read its lines as they come. On each `job-finished`, tell the person about that job: its `status`, `outputPath`, `outputBytes`, `quality.outcome` and `needsALook`. On `queue-idle` the queue has nothing more to do: stop following. On `app-closing` the window closed.

### Make samples first, compare, then convert the whole

```sh
vidctrl-client queue add ~/Videos/beach.mov ~/Videos/party.mov --goal archive --sample middle --json
vidctrl-client wait --json
vidctrl-client compare 0 --json               # each sample job's id from `added`
vidctrl-client compare 1 --json
```

Each sample job's `outputPath` is a 10-second piece in `Converted/Samples/`. `compare` compares it with the same piece of its original and says how close it looks: `closeness` (`closenessText` in words), with `vmaf` and `xpsnr`. Each comparison takes about as long as the piece lasts, or longer. `vidctrl-client job <job> --json` gives the sample's `quality` too: the quality chosen for the whole video and `share`, its expected size as a share of the original's. Tell the person where the samples are and how close each looks, so they can look at them. Once they agree, convert each whole video with its sample's settings, by the sample jobs' ids:

```sh
vidctrl-client queue convert-whole 0 --json
vidctrl-client queue convert-whole 1 --json
vidctrl-client wait --json
```

Each answer's `added` holds the new job. For other settings, queue the whole videos with `vidctrl-client queue add` and the goal and options wanted.

### Hold the conversions for a while

When the person needs the computer for something else:

```sh
vidctrl-client pause
vidctrl-client resume                         # when the person says so
```

`pause` holds the job under way and starts nothing new; `resume` goes on where it was. To stop the job under way for good, `vidctrl-client cancel` (it can be tried again with `vidctrl-client queue retry <job>`); to take waiting jobs out of the queue, `vidctrl-client queue remove <jobs…>`. The files stay as they are.

### What would Archive do with these videos, and how big would they be?

```sh
vidctrl-client add ~/Videos/trip --json
vidctrl-client estimate 0 1 2 --goal archive --json      # the ids from `add`
```

`estimate` measures each video in turn and answers once all are measured; that takes seconds to a minute or so for each. Each video's `preview` gives the `plan` (`planText` in words), the `expectedBytes` (`measured` when measured by encoding pieces) and the `closeness`; beside its `sizeBytes`, that is how much smaller it would come out. A preview with no `expectedBytes` could not be measured. While the queue converts, `estimate` is refused (`busy`): measure before queuing, or once `vidctrl-client wait` has returned. Later, `vidctrl-client videos --goal archive --json` gives the same again.

## Limits

- It runs as the person logged in, on the same computer and desktop as the window: not over SSH, not from WSL on Windows or a container. A sandboxed agent must run `vidctrl-client` outside its sandbox: it needs the loopback network, the person's own folders and, to open the window, the desktop.
- No FFmpeg settings and no quality numbers: only the goals and options listed here. That is what keeps their promises (Archive looks the same).
- It does not look for files: find them yourself and pass their paths.
- It cannot close the window, change the goal shown in its panel, its remembered settings, its look or its language.
- The window converts one job at a time. The list, the queue and their ids last while the window is open.
- Its words are English, whatever language the window shows.
