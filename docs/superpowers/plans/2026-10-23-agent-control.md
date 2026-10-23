# vidctrl-client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A console program, `vidctrl-client`, through which an agent or a
script adds videos to the running VidCtrl window, queues them with a goal,
controls and watches the queue, and waits for the results, while the window
shows all of it; plus a window in the app that hands an agent a ready prompt.

**Architecture:** The app runs a small JSON-RPC server on loopback TCP
inside its UI isolate (`lib/app/control/`), whose every method calls the same
notifiers as the buttons. The wire format, endpoint file, socket plumbing,
views and the client itself are plain Dart in `lib/core/control/`;
`bin/vidctrl_client.dart` compiles to a native program with
`dart compile exe`. The release puts it beside the app on each system.

**Tech Stack:** Dart 3 / Flutter, Riverpod 3 notifiers, `dart:io`
`ServerSocket`/`Socket`, `package:args` (new dependency) for the client's
arguments.

**Spec:** `docs/superpowers/specs/2026-10-23-agent-control-design.md`.
Read it before starting; this plan argues from it and does not repeat its
reasons.

## Global Constraints

- Work happens in the worktree `../vidctrl-agent-control` on the branch
  `agent-control`, branched from `main` at 7bcc2ea.
- `lib/core/` never imports Flutter; the client imports only `lib/core/`
  (`flutter analyze` and `dart compile exe` both prove it).
- Every server method goes through the notifiers the buttons use
  (`SourcesController`, `QueueController`, `EstimateCache`,
  `QualityController`); none edits their state or runs FFmpeg itself.
- No method deletes, moves or renames a file. No text the client prints,
  the manual and the agent prompt included, speaks of deleting a file.
  "Remove" takes a video off the list or a job out of the queue, and every
  removing command says the file stays on disk.
- No FFmpeg arguments or quality numbers can be passed in; goals and options
  are the panel's ids (`archive`, `archive.master`, `--opt speed=fast`).
- No way to close the window, change the panel's goal, the remembered
  settings, the look or the language.
- Loopback only (`InternetAddress.loopbackIPv4`); the first message on a
  connection is `hello` with the token, or the connection is closed.
- Endpoint file `{port, token, pid, version, protocol}`, mode 0600 on Linux
  and macOS, at: Linux `$XDG_RUNTIME_DIR/vidctrl/control.json` (else
  `$HOME/.cache/vidctrl/control.json`), macOS `$HOME/Library/Application
  Support/app.camctrl.vidctrl/control.json`, Windows
  `%LOCALAPPDATA%\VidCtrl\control.json`.
- Exit codes: 0 done, 1 a job failed or was cancelled, 2 not running and
  could not start (or refused), 3 timeout, 4 the app closed while waiting,
  5 bad arguments, 6 FFmpeg missing.
- Client output is English. Text for people by default, `--json` on every
  command.
- App texts in both ARB files (`flutter gen-l10n` after editing, generated
  files committed); plain words first, technical names through
  `TechnicalText`; `no_scrolling_test.dart` and both looks hold.
- No personal data in files: tests use placeholder paths (`/videos/a.mp4`,
  `/home/alice/...`), never the real home folder or username.
- `dart format lib test tool bin` clean; `flutter analyze` clean; fast tests
  pass: `flutter test --exclude-tags "ffmpeg || screenshots"`.
- Commits: on the `agent-control` branch only (its own worktree), one or
  more per task, without asking each time: the owner reviews the branch
  before anything reaches `main`. Never commit to `main`, never push. No
  `Co-Authored-By`, `Claude-Session` or other Claude attribution. Subjects are plain sentences, like the history ("Keep a
  video's expected size when its default is chosen again"), because
  release notes are made of them.

## Review Focus

1. **Relative paths and `~`.** An agent passes `clip.mov`, `./Videos` or
   `"~/Videos"` (quoted, so the shell did not expand it); the app's working
   folder is not the client's. The client makes every path absolute
   (expanding a leading `~/`) before sending. Test in Task 8.
2. **A path that does not exist, or is not a video.** It is reported per
   path (`notFound`, `unreadable`) and the others still go in; nothing is
   silently dropped. Exit 5 only when no path could be added. Tests in
   Tasks 5 and 8.
3. **The app closes or crashes during `wait` or `events`.** The client
   exits 4 promptly when the socket ends, with or without the
   `app-closing` notification; it never hangs. Tests in Tasks 6 and 8.
4. **A stale endpoint after a crash.** The file is left behind; its port
   refuses, or another program now answers there and fails `hello`. Both
   count as "not running": the client starts the app, a new window takes
   the endpoint over. Tests in Tasks 1, 5 and 8.
5. **A command while the app is still starting, or without FFmpeg.**
   Methods wait for the environment; with FFmpeg missing they fail at once
   with exit 6, not after the 30 s start timeout. Tests in Tasks 5 and 8.

---

## Files

```
lib/core/control/
  protocol.dart        wire format, error kinds, exit codes, method names
  endpoint.dart        Endpoint, endpointPath(), EndpointFile, newToken()
  listener.dart        ControlListener: ServerSocket, hello, dispatch, notify
  connection.dart      ControlConnection (client side), connectIfLive()
  views.dart           VideoView, GoalPreview, JobView, QualityView,
                       StatusView, GoalView, JobOutcome, ControlEvent (JSON)
  words.dart           English words for statuses, plans and outcomes
  launcher.dart        AppLauncher: find and start the window
  client.dart          runClient(): arguments, commands, printing, exit codes
  manual.dart          the manual, help texts, quick start
  manual_words.g.dart  goal and option words from the English ARB (generated)
lib/app/control/
  control_controller.dart  controlProvider: start/stop, endpoint ownership
  handlers.dart            one function per method, over the notifiers
  events.dart              queueEvents(), sourceEvents(): state diffs
  waiter.dart              WaitTracker
  agent_prompt.dart        clientExecutable(), agentPrompt()
lib/app/home/widgets/
  agent_button.dart        header button + AgentDialog
bin/vidctrl_client.dart    main() → runClient()
tool/make_manual.dart      writes manual_words.g.dart and docs/CLIENT.md
tool/build_client.sh       dart compile exe into a given folder
docs/CLIENT.md             generated from the manual
```

---

## Task 0: macOS signing spike (on a Mac, throwaway) — DEFERRED

Deferred by the owner: there is no Apple developer account yet. Not part of
this run; until it is done, macOS builds are signed ad hoc as now (Task 12),
and the spec's "Not yet known" stays open.

Settles the open point in the spec's "Shipping" before anything depends on
it. Nothing from it is kept but the finding.

- [ ] **Step 1:** On a Mac with the Developer ID identity, write
  `hello.dart` (`print('ok')`), `dart compile exe hello.dart -o hello`.
- [ ] **Step 2:** Copy it into a built `VidCtrl.app/Contents/MacOS/`, sign
  as `tool/package_macos.sh` signs `ffmpeg`:
  `codesign --force --sign "$identity" --options runtime --timestamp hello`,
  then sign the app as the script does.
  Expected: `codesign --verify --deep --strict --verbose=2` passes.
- [ ] **Step 3:** Run `VidCtrl.app/Contents/MacOS/hello` from Terminal.
  Expected: prints `ok`. If it is killed or fails, retry with an
  entitlements file holding only `com.apple.security.cs.allow-jit`, then
  `allow-unsigned-executable-memory`; note which one was needed.
- [ ] **Step 4:** Notarize the disk image (`tool/package_macos.sh` with the
  secrets), download it on another Mac or quarantine it
  (`xattr -w com.apple.quarantine ...`), copy the app, run `hello`.
  Expected: runs with no Gatekeeper dialog.
- [ ] **Step 5:** Write the finding into the spec's "Shipping" paragraph
  (replacing "Not yet known") and, if an entitlement was needed, into
  Task 12's signing step. Commit the spec change after the owner's OK.

---

## Phase 1: usable end to end

### Task 1: Wire format and endpoint file

**Files:**
- Create: `lib/core/control/protocol.dart`, `lib/core/control/endpoint.dart`
- Test: `test/core/control/protocol_test.dart`, `test/core/control/endpoint_test.dart`

**Interfaces:**
- Produces (`protocol.dart`):
  - `const controlProtocol = 1;`
  - `enum ControlErrorKind { badArgument, notFound, busy, unknownMethod, ffmpegMissing, unauthorized, notRunning, appClosed }` with `int get exitCode`: the first four → 5, `ffmpegMissing` → 6, `unauthorized` and `notRunning` → 2, `appClosed` → 4.
  - `class ControlError implements Exception { const ControlError(this.kind, this.message); final ControlErrorKind kind; final String message; }`
  - `abstract final class ExitCode { static const ok = 0, jobsFailed = 1, notRunning = 2, timeout = 3, appClosed = 4, badArguments = 5, ffmpegMissing = 6; }`
  - `sealed class ControlMessage` with `ControlRequest(int id, String method, Map<String, Object?> params)`, `ControlResponse(int id, {Object? result, ControlError? error})`, `ControlNotification(String method, Map<String, Object?> params)`.
  - `String encodeMessage(ControlMessage m)` — one line of JSON-RPC 2.0, no newline inside, `"jsonrpc":"2.0"`; an error is `{"code": <kind index + 1000>, "message", "data": {"kind": kind.name}}`.
  - `ControlMessage decodeMessage(String line)` — throws `FormatException` for anything that is not one of the three shapes.
  - `abstract final class Methods` with the method names as constants: `hello, status, goals, videosAdd = 'videos.add', videosList = 'videos.list', videosRemove, videosDetails, videosEstimate, queueList, queueAdd, queueRemove, queueMove, queueRetry, queueClearFinished, queuePause, queueResume, queueCancel, queueConvertAnyway, queueConvertWhole, jobGet = 'job.get', jobCompare, wait, subscribe`; and `abstract final class Events` with `appClosing = 'app-closing'` and the event names from the spec.
- Produces (`endpoint.dart`):
  - `class Endpoint { const Endpoint({required int port, required String token, required int pid, required String version, required int protocol}); Map<String, Object?> toJson(); static Endpoint? fromJson(Object? json); }` — `fromJson` returns null for anything malformed.
  - `String endpointPath({required String os, required Map<String, String> environment})` — `os` is a `Platform.operatingSystem` value.
  - `class EndpointFile { EndpointFile(this.path); final String path; Future<Endpoint?> read(); Future<void> write(Endpoint e); Future<void> delete(); static EndpointFile forThisUser(); }` — `write` creates the folder, writes a temporary file beside and renames it over, then on Linux and macOS runs `chmod 600`; `read` returns null when missing or malformed; `delete` ignores a missing file.
  - `String newToken()` — 32 bytes from `Random.secure()`, base64url without padding.

- [ ] **Step 1: Write the failing tests**

```dart
// protocol_test.dart
test('a request survives encoding and decoding', () {
  final line = encodeMessage(const ControlRequest(7, 'queue.add', {'goal': 'archive'}));
  expect(line, isNot(contains('\n')));
  final back = decodeMessage(line) as ControlRequest;
  expect((back.id, back.method, back.params), (7, 'queue.add', {'goal': 'archive'}));
});
test('an error carries its kind', () {
  final line = encodeMessage(const ControlResponse(3,
      error: ControlError(ControlErrorKind.ffmpegMissing, 'no FFmpeg')));
  final back = decodeMessage(line) as ControlResponse;
  expect(back.error!.kind, ControlErrorKind.ffmpegMissing);
  expect(back.error!.kind.exitCode, ExitCode.ffmpegMissing);
});
test('a line that is not JSON-RPC is refused', () {
  expect(() => decodeMessage('POST / HTTP/1.1'), throwsFormatException);
  expect(() => decodeMessage('{"jsonrpc":"2.0"}'), throwsFormatException);
});

// endpoint_test.dart
test('the endpoint lives in the runtime folder on Linux', () {
  expect(endpointPath(os: 'linux', environment: {'XDG_RUNTIME_DIR': '/run/user/1000', 'HOME': '/home/alice'}),
      '/run/user/1000/vidctrl/control.json');
  expect(endpointPath(os: 'linux', environment: {'HOME': '/home/alice'}),
      '/home/alice/.cache/vidctrl/control.json');
});
test('on macOS and Windows it lives in the per-user app folder', () {
  expect(endpointPath(os: 'macos', environment: {'HOME': '/Users/alice'}),
      '/Users/alice/Library/Application Support/app.camctrl.vidctrl/control.json');
  expect(endpointPath(os: 'windows', environment: {'LOCALAPPDATA': r'C:\Users\alice\AppData\Local'}),
      r'C:\Users\alice\AppData\Local\VidCtrl\control.json');
});
test('a written endpoint reads back and only its owner can read it', () async {
  final dir = await Directory.systemTemp.createTemp('endpoint');
  addTearDown(() => dir.delete(recursive: true));
  final file = EndpointFile(p.join(dir.path, 'sub', 'control.json'));
  const e = Endpoint(port: 4242, token: 't', pid: 1, version: '', protocol: 1);
  await file.write(e);
  expect((await file.read())!.port, 4242);
  if (!Platform.isWindows) {
    expect(FileStat.statSync(file.path).modeString(), 'rw-------');
  }
  await file.delete();
  expect(await file.read(), isNull);
});
test('a malformed endpoint file reads as none', () async { /* write "{" → read() is null */ });
test('tokens differ and are long', () {
  expect(newToken(), isNot(newToken()));
  expect(newToken().length, greaterThanOrEqualTo(43));
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/control/`
Expected: FAIL, the libraries do not exist.

- [ ] **Step 3: Implement `protocol.dart` and `endpoint.dart`** with the
  interfaces above; `endpointPath` joins with `p.posix` or `p.windows` by
  `os`, not by the machine the test runs on.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/control/`
Expected: PASS.

- [ ] **Step 5: Commit** (after the owner's OK): "Describe how the client
  and the window talk, and where the window says it listens"

### Task 2: Socket plumbing: listener and connection

**Files:**
- Create: `lib/core/control/listener.dart`, `lib/core/control/connection.dart`
- Test: `test/core/control/listener_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces (`listener.dart`):
  - `typedef ControlHandler = Future<Object?> Function(String method, Map<String, Object?> params, ControlPeer peer);`
  - `abstract interface class ControlPeer { void notify(String method, Map<String, Object?> params); Future<void> get closed; }`
  - `class ControlListener { static Future<ControlListener> bind({required String token, required ControlHandler handler}); int get port; Future<void> close({bool farewell = true}); }`
  - Behaviour: binds `127.0.0.1` port 0. Per connection, lines are decoded; until `hello` with the right token and `protocol == controlProtocol` succeeds, any other message (or a bad line, or a wrong token) closes the socket after an `unauthorized` error. After that, each request runs the handler concurrently (a long `wait` does not hold up others) and its result or `ControlError` goes back with the request's id; any other exception becomes `badArgument` with its text. A protocol mismatch answers `badArgument` with "This vidctrl-client speaks protocol N, the app speaks M; use the vidctrl-client that came with this VidCtrl." `close(farewell: true)` sends `app-closing` to every authorised peer, then closes all sockets and the server.
- Produces (`connection.dart`):
  - `class ControlConnection { static Future<ControlConnection> open(Endpoint endpoint, {Duration timeout = const Duration(seconds: 2)}); Future<Object?> call(String method, [Map<String, Object?> params = const {}]); Stream<ControlNotification> get notifications; Future<void> get done; Future<void> close(); }` — `open` connects and sends `hello`, throwing `ControlError(unauthorized)` when refused; `call` throws the response's `ControlError`, and throws `ControlError(appClosed, 'VidCtrl was closed.')` for calls pending when the socket ends; `done` completes when the socket ends for any reason.
  - `Future<ControlConnection?> connectIfLive(EndpointFile file)` — null when the file is missing, the port refuses, or `hello` fails (a stale file, or another program on that port).

- [ ] **Step 1: Write the failing tests**

```dart
test('a call reaches the handler and its answer comes back', () async {
  final listener = await ControlListener.bind(token: 't',
      handler: (method, params, peer) async => {'echo': method, ...params});
  addTearDown(listener.close);
  final c = await ControlConnection.open(_endpoint(listener.port, 't'));
  expect(await c.call('status', {'x': 1}), {'echo': 'status', 'x': 1});
});
test('a wrong token is refused and the connection closed', () async {
  // open(...'wrong') throws ControlError with kind unauthorized
});
test('a line that is not JSON closes the connection at once', () async {
  // raw Socket.connect, write 'GET / HTTP/1.1\r\n\r\n', expect the socket
  // to end without the handler being called
});
test('a slow call does not hold up a quick one', () async {
  // handler: 'slow' awaits a Completer, 'quick' answers at once;
  // call slow (not awaited), await quick → answered; then complete slow
});
test('an error from the handler arrives with its kind', () async {
  // handler throws ControlError(notFound, 'no job 9') → call throws, kind notFound
});
test('closing says goodbye to every client', () async {
  // two connections; listener.close() → each sees a notification
  // 'app-closing', then `done` completes
});
test('a stale endpoint file is not live', () async {
  // write an Endpoint with a port nothing listens on → connectIfLive is null;
  // with a listener whose token differs → null
});
```

- [ ] **Step 2: Run to see them fail** — `flutter test test/core/control/listener_test.dart`, FAIL.
- [ ] **Step 3: Implement** both files as specified; split incoming bytes
  with `utf8.decoder` and `const LineSplitter()`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** (after OK): "Let the client and the window talk over a local connection only they share"

### Task 3: Views and words

**Files:**
- Create: `lib/core/control/views.dart`, `lib/core/control/words.dart`
- Test: `test/core/control/views_test.dart`

**Interfaces:**
- Produces (`views.dart`), each with `Map<String, Object?> toJson()` and `factory X.fromJson(Map<String, Object?>)`; JSON keys are the field names; absent values are omitted, not null:
  - `VideoView {int id; String path; String status /* probing|ready|unreadable */; int? sizeBytes; double? durationSeconds; int? width; int? height; String? videoCodec; List<String> audioCodecs; bool hdr; GoalPreview? preview;}`
  - `GoalPreview {String goal /* preset id */; String plan /* skip|remux|audioOnly|encode|unsupported|keptAsIs */; int? expectedBytes; bool measured; bool measuring; String? closeness /* same|veryClose|differs */;}`
  - `JobView {int id; int videoId; String path; String goal; Map<String, String> options; String? sample /* start|middle */; String status /* JobStatus.name */; double? fraction; double? remainingSeconds; int? attempt; String? outputPath; int? outputBytes; QualityView? quality; bool needsALook; List<String> errorLines;}`
  - `QualityView {String outcome /* QualityOutcome.name */; int? value; int? standardValue; double? vmaf; double? xpsnr; double share;}`
  - `StatusView {String state /* starting|ready|ffmpegMissing */; String version; bool busy; bool paused; Map<String, int> jobs /* by status */;}`
  - `GoalView {String id; String scenario; String title; String subtitle; List<OptionView> options;}`, `OptionView {String id; String title; String defaultChoice; bool advanced; List<ChoiceView> choices;}`, `ChoiceView {String id; String label; String hint;}`
  - `JobOutcome {int jobId; String path; String status /* done|skipped|failed|cancelled|removed */; String? outputPath; bool needsALook;}`
- Produces (`words.dart`): `String statusWords(String status)`, `String planWords(String plan)`, `String closenessWords(String closeness)`, `String outcomeWords(String outcome)`, and the guard every text test uses:
  - `const filesRule = 'Never delete, move or rename any file.';` and `const neverDeletes = 'VidCtrl deletes no file: "remove" takes a video off the list or a job out of the queue, and the file stays on disk.';` — the only two sentences allowed to name deleting, both forbidding it.
  - `bool speaksOfDeleting(String text)` — true when, after taking out every `filesRule` and `neverDeletes`, the lower-cased text matches any of `delet`, `\brm\b`, `\bunlink`, `\btrash`, `\berase`, `clean(ing)? up`, `remove the original`, `the original can go`.
  Copy, exactly:
  - statuses: waiting "Waiting", running "Converting", paused "Paused", done "Done", skipped "Nothing to do", failed "Failed", cancelled "Cancelled", removed "Taken out of the queue (the file stays on disk)".
  - plans: skip "Already fine: nothing to do", remux "Moved to a new file type, untouched", audioOnly "Only the sound is converted", encode "Converted", unsupported "This goal cannot do anything with it", keptAsIs "Kept as it is: converting would hardly make it smaller".
  - closeness: same "Looks the same as the original", veryClose "Very close to the original", differs "Differences may be visible" (the ARB's words).
  - outcomes: standard "Usual quality", raised "Raised quality: needed to look the same", belowTarget "Worth a look by eye: even the best quality falls a little short somewhere", notWorthIt "Kept as it is: converting would hardly make it smaller".

- [ ] **Step 1: Failing tests**

```dart
test('every view survives JSON', () {
  final job = JobView(id: 3, videoId: 1, path: '/videos/a.mov', goal: 'archive.master',
      options: {'speed': 'fast'}, status: 'done', outputPath: '/videos/Converted/a_av1-crf35.mp4',
      outputBytes: 10, quality: QualityView(outcome: 'belowTarget', value: 20, share: .4),
      needsALook: true, errorLines: const []);
  expect(JobView.fromJson(jsonDecode(jsonEncode(job.toJson()))).toJson(), job.toJson());
  // the same for VideoView with a GoalPreview, StatusView, GoalView, JobOutcome
});
test('absent values are left out of the JSON', () {
  expect(VideoView(id: 0, path: '/videos/a.mov', status: 'probing', audioCodecs: const [], hdr: false)
      .toJson().containsKey('sizeBytes'), isFalse);
});
test('no word the client prints speaks of deleting', () {
  final all = [for (final s in ['waiting','running','paused','done','skipped','failed','cancelled','removed']) statusWords(s),
      for (final s in ['skip','remux','audioOnly','encode','unsupported','keptAsIs']) planWords(s),
      for (final s in ['standard','raised','belowTarget','notWorthIt']) outcomeWords(s)];
  for (final text in all) {
    expect(speaksOfDeleting(text), isFalse, reason: text);
  }
});
test('the guard catches deleting but lets the two rules through', () {
  expect(speaksOfDeleting('Delete the original when done.'), isTrue);
  expect(speaksOfDeleting('then rm the source'), isTrue);
  expect(speaksOfDeleting('Confirm the format. $filesRule $neverDeletes'), isFalse);
});
```

- [ ] **Step 2: Run, FAIL.** `flutter test test/core/control/views_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, PASS.**
- [ ] **Step 5: Commit** (after OK): "Give the client the words and shapes for what the window shows"

### Task 4: Controller entry points the server needs

**Files:**
- Modify: `lib/app/sources/sources_controller.dart` (`addPaths`)
- Modify: `lib/app/queue/queue_controller.dart` (`_add`, new `addVideos`, `pause`, `resume`)
- Test: `test/app/workspace_test.dart` (add cases)

**Interfaces:**
- Produces:
  - `Future<List<int>> SourcesController.addPaths(Iterable<String> paths)` — now returns the ids of every file the paths stand for, in order, those already in the list included; behaviour otherwise unchanged (existing callers ignore the result).
  - `({List<QueueJob> added, List<int> alreadyQueued}) QueueController.addVideos(List<SourceVideo> videos, {required Recipe recipe, required OutputSettings output})` — what `_add` did, for any recipe and output; `alreadyQueued` holds the video ids skipped as duplicates. `addSelected()` and `addAll()` call it with the panel's recipe and output.
  - `void QueueController.pause()` / `void QueueController.resume()` — do what `togglePause()` does only when not already in that state.

- [ ] **Step 1: Failing tests** (in `workspace_test.dart`, using its `start()`, `sources()`, `queue()`):

```dart
test('queuing with given settings makes the job the button makes', () async {
  await sources().addPaths(['/videos/a.mp4']);
  queue().addSelected();
  final byButton = jobs().single;
  await queue().remove(byButton.id);
  final result = queue().addVideos(sourceState().ready,
      recipe: container.read(recipeProvider).recipe, output: container.read(recipeProvider).output);
  final byCommand = result.added.single;
  expect((byCommand.recipe, byCommand.plan.nameSuffix, byCommand.outputPath, byCommand.sample),
      (byButton.recipe, byButton.plan.nameSuffix, byButton.outputPath, byButton.sample));
});
test('a job waiting with the same settings is not queued twice either way', () async {
  // addSelected(); then addVideos(same recipe/output) → added empty,
  // alreadyQueued == [video id]
});
test('adding paths tells which videos they are, those already listed included', () async {
  final first = await sources().addPaths(['/videos/a.mp4']);
  final again = await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
  expect(again, [first.single, video('b.mp4').id]);
});
test('pause and resume can be repeated', () async {
  queue().pause(); queue().pause();
  expect(queueState().paused, isTrue);
  queue().resume(); queue().resume();
  expect(queueState().paused, isFalse);
});
```

- [ ] **Step 2: Run, FAIL.** `flutter test test/app/workspace_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the file and the whole fast suite, PASS.**
  `flutter test --exclude-tags "ffmpeg || screenshots"`
- [ ] **Step 5: Commit** (after OK): "Let the queue take videos with settings of their own"

### Task 5: The control server: status, goals, videos, queue add

**Files:**
- Create: `lib/app/control/control_controller.dart`, `lib/app/control/handlers.dart`
- Test: `test/app/control/control_server_test.dart`, `test/support/control.dart` (helper)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `final controlProvider = NotifierProvider<ControlController, ControlState>(ControlController.new);`
  - `class ControlState { const ControlState({this.port}); final int? port; bool get serving => port != null; }`
  - `class ControlController extends Notifier<ControlState> { Future<void> start({EndpointFile? file}); Future<void> stop(); }` — `start`: if `connectIfLive(file)` finds another window, stays not serving; otherwise binds a `ControlListener` with `newToken()`, writes the endpoint (`pid`, `version` from `buildInfoProvider`, `controlProtocol`), sets `port`. Default file `EndpointFile.forThisUser()`. `stop`: `listener.close(farewell: true)`, deletes the file only if it still holds this window's token.
  - `handlers.dart`: `Future<Object?> handleControl(Ref ref, String method, Map<String, Object?> params, ControlPeer peer)`; this task covers `status`, `goals`, `videos.add`, `videos.list`, `videos.remove`, `queue.list`, `queue.add`; unknown methods throw `unknownMethod`.
  - Readiness: every method but `status` first awaits `ref.read(environmentProvider.future)`; on `FfmpegMissing` it throws `ControlError(ffmpegMissing, 'VidCtrl could not find FFmpeg; the window says what to do.')`. `status` answers at once with `state` `starting`, `ready` or `ffmpegMissing`.
  - Params and results:
    - `goals` → `{goals: [GoalView]}` — words from `lookupAppLocalizations(const Locale('en'))` through `scenarioTitle`, `scenarioSubtitle`, `optionTitle`, `choiceLabel`, `choiceHint`; options shown as `optionVisible` decides for this machine's capabilities.
    - `videos.add {paths: [String]}` (absolute) → `{videos: [{path, id?, result: added|known|notFound|unreadable}]}`; a path that does not exist is not passed on; the rest go through `addPaths` (folders expand there), then the handler awaits `sources.settled` unless `wait: false`; throws `badArgument` when nothing could be added.
    - `videos.list {goal?, options?}` → `{videos: [VideoView]}`, with `preview` when a goal is given: the plan from `preset.plan(info, values, capabilities)`, the estimate from `estimateWithoutEncoding(info, plan) ?? cache.estimates[estimateKey(path, recipe)]`, `keptAsIs` when its choice does not convert.
    - `videos.remove {videos: [id|path]}` → `{removed: [id]}` via `SourcesController.remove`.
    - `queue.list` → `{paused, busy, jobs: [JobView]}`.
    - `queue.add {videos: [id|path], goal?, options?, sample?, out?, subfolder?}` → `{goal, options, added: [JobView], alreadyQueued: [videoId], skipped: [{video, reason}]}`. Paths not in the list are added first (as `videos.add`). Recipe: `goal` (preset id, or scenario id with one preset) and `options` validated against the preset (unknown goal, option or choice → `badArgument` listing the valid ones); without `goal`, the panel's `recipe.presetId` and `values`. `sample` `start|middle`, default none whatever the panel says. `out`: absent → the panel's `output`; `next` → `OutputSettings()` with `subfolder` as `subfolderName` when given; a folder path → `OutputMode.customFolder`. Videos still probing are awaited; unreadable ones go to `skipped`.
  - `test/support/control.dart`: `Future<(ProviderContainer, ControlConnection)> startControlled(FakeEnvironment env, {Directory? dir})` — container with `env.overrides`, `controlProvider.start(file: EndpointFile(<temp>/control.json))`, an open connection; tear-downs registered.

- [ ] **Step 1: Failing tests**

```dart
test('a video added by the client appears in the list and is selected', () async {
  env.ffprobe.add('/videos/a.mp4');
  final (container, client) = await startControlled(env);
  final answer = await client.call('videos.add', {'paths': ['/videos/a.mp4']}) as Map;
  final id = container.read(sourcesProvider).videos.single.id;
  expect(answer['videos'], [{'path': '/videos/a.mp4', 'id': id, 'result': 'added'}]);
  expect(container.read(sourcesProvider).selectedIds, {id});
});
test('a missing path is reported and the others still go in', () async {
  // '/videos/nope.mp4' does not exist on disk: use a temp folder with one real
  // file registered in env.ffprobe → results [added, notFound]
});
test('nothing addable is a bad argument', () async { /* only missing paths → ControlError badArgument */ });
test('queue add with a goal makes the job the button would, and leaves the panel alone', () async {
  // panel left on archive; call queue.add {videos:[id], goal:'remux', options:{}}
  // → one job with recipe.presetId 'remux.container'; recipeProvider unchanged
});
test('queue add without a goal uses the panel and says which', () async {
  // answer['goal'] == container.read(recipeProvider).recipe.presetId
});
test('queue add makes whole videos even when the panel makes samples', () async {
  // recipe().setSample(SampleChoice.start); queue.add without sample → job.sample == null
});
test('an unknown goal or choice lists the valid ones', () async {
  // goal 'zip' → badArgument whose message contains 'archive'
  // options {'speed': 'warp'} → badArgument whose message names the valid choices
});
test('the same job twice is reported as already queued', () async {});
test('status answers while FFmpeg is still being looked for', () async {
  // environmentProvider overridden with a Completer's future: status → state 'starting';
  // a queue.list sent meanwhile completes after the completer does
});
test('without FFmpeg every method but status fails with ffmpegMissing', () async {
  // environmentProvider throws FfmpegMissing → status 'ffmpegMissing',
  // videos.list throws kind ffmpegMissing, promptly
});
test('a second window does not take over a live endpoint', () async {
  // two containers on the same EndpointFile: first serving, second not;
  // the file still holds the first's port
});
test('a window takes over a stale endpoint', () async {
  // file holds a dead port → start() serves and rewrites it
});
test('stopping removes the endpoint file only if it is its own', () async {});
```

- [ ] **Step 2: Run, FAIL.** `flutter test test/app/control/`
- [ ] **Step 3: Implement** `control_controller.dart` and the handlers of
  this task. Ids are `int`; a `String` in `videos` is a path, matched
  against `SourceVideo.path` after `p.normalize`.
- [ ] **Step 4: Run, PASS.**
- [ ] **Step 5: Commit** (after OK): "Let a client add videos and queue them in the open window"

### Task 6: Events and wait

**Files:**
- Create: `lib/app/control/events.dart`, `lib/app/control/waiter.dart`
- Modify: `lib/app/control/handlers.dart` (`subscribe`, `wait`), `lib/app/control/control_controller.dart` (listeners)
- Test: `test/app/control/events_test.dart`, `test/app/control/waiter_test.dart`, `test/app/control/control_server_test.dart`

**Interfaces:**
- Consumes: Tasks 3, 5.
- Produces:
  - `class ControlEvent { const ControlEvent(this.name, this.data); final String name; final Map<String, Object?> data; }`
  - `List<ControlEvent> queueEvents(QueueState before, QueueState after)` — `job-added` (JobView), `job-checking` (`{job, attempt}`) when `attempt` changes, `job-started` (status becomes running from waiting), `job-progress` (`{job, fraction, remainingSeconds}`), `job-finished` (`JobView`, when status becomes done, skipped, failed or cancelled), `job-removed` (`{job}`), `queue-paused`, `queue-resumed`, `queue-idle` (`busy` true → false).
  - `List<ControlEvent> sourceEvents(SourcesState before, SourcesState after)` — `video-added`, `video-ready`, `video-unreadable`, `video-removed`, each with the `VideoView` or `{video}`.
  - `compare-finished` comes from `qualityProvider` going to `QualityMeasured`/`QualityFailed` for a job (Task 11 adds the comparisons; the event is wired here).
  - The controller listens (after the environment is ready) to `queueProvider`, `sourcesProvider`, `qualityProvider`; sends each event to peers that subscribed, as a notification named after the event with `{time: ISO-8601, ...data}`; `job-progress` at most once a second per job and peer.
  - `subscribe {snapshot: bool}` → returns `{}` and, when `snapshot` is true (default), first sends a `snapshot` notification `{videos: [VideoView], jobs: [JobView], paused, busy}`.
  - `class WaitTracker { WaitTracker(QueueState start, {Set<int>? jobs}); bool get finished; List<JobOutcome> get outcomes; bool get paused; void update(QueueState s); }` — counts jobs pending at start (or the given ids), plus jobs added later when no ids were given; a counted job that vanishes becomes `removed`; finished when no counted job is pending. With nothing to count it is finished at once.
  - `wait {jobs?: [int]}` → `{outcomes: [JobOutcome]}` once finished; unknown ids → `notFound`. Pausing sends the waiting peer one `queue-paused` notification.

- [ ] **Step 1: Failing tests**

```dart
// waiter_test.dart (pure; build QueueStates by hand)
test('jobs finished before the wait do not count', () {
  final t = WaitTracker(QueueState(jobs: [failedJob(1), waitingJob(2)]));
  t.update(QueueState(jobs: [failedJob(1), doneJob(2)]));
  expect(t.finished, isTrue);
  expect(t.outcomes.map((o) => (o.jobId, o.status)), [(2, 'done')]);
});
test('a job added during the wait is waited for', () {});
test('a removed job is reported as removed, not failed', () {});
test('a job cancelled during the wait counts as cancelled', () {});
test('with nothing pending the wait is over at once', () {
  expect(WaitTracker(const QueueState()).finished, isTrue);
});
test('given ids, only those count', () {});

// events_test.dart (pure)
test('a job going from waiting to done gives started then finished', () {});
test('a measuring attempt gives job-checking with its number', () {});
test('the queue running out gives queue-idle', () {});

// control_server_test.dart (real sockets)
test('a client sees each job finish while the rest still converts', () async {
  // two jobs; subscribe; env.executor.handles.first.finish() → notification
  // 'job-finished' for job 1 arrives while job 2 is running
});
test('wait returns when the queue is done, with each outcome', () async {});
test('a wait ends with app-closing when the window closes', () async {
  // container's controlProvider.stop() while a wait is pending → the
  // connection receives 'app-closing' and `done` completes
});
test('a peer whose socket drops is forgotten', () async {
  // close the client mid-subscribe; a later event does not throw in the app
});
```

- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, PASS.**
- [ ] **Step 5: Commit** (after OK): "Let a client follow the queue and wait for its results"

### Task 7: Wire the server into the app

**Files:**
- Modify: `lib/main.dart`, `lib/app/window_close_guard.dart`, `CLAUDE.md`
- Test: `test/app/control/control_window_test.dart`

**Interfaces:**
- Consumes: Task 5's `controlProvider`.
- Produces: the app starts the server once the first frame is up
  (`ProviderScope` → a `ControlHost` widget, or `ProviderContainer` built in
  `main` and passed to `UncontrolledProviderScope`, then
  `container.read(controlProvider.notifier).start()`; the latter is the
  simpler: `main` already builds the scope). `WindowCloseGuard` calls
  `controlProvider.notifier.stop()` first in its leaving path (before
  `shutDown()`), guarded by `ref.exists(controlProvider)`.

- [ ] **Step 1: Failing widget test**

```dart
testWidgets('what a client adds and queues shows in the window', (tester) async {
  // pumpApp(...) with env; start controlProvider on a temp EndpointFile inside
  // tester.runAsync; client calls videos.add then queue.add (inside runAsync);
  // pump; expect find.text('a.mp4') in the videos pane and a queue row for it
});
```

- [ ] **Step 2: Run, FAIL.** `flutter test test/app/control/control_window_test.dart`
- [ ] **Step 3: Implement** the start in `main.dart` and the stop in
  `WindowCloseGuard`; add `lib/app/control/` and `lib/core/control/` to
  CLAUDE.md's architecture (one paragraph: what the server is, that it goes
  through the notifiers, the endpoint file, `vidctrl-client`), and the
  commands (`dart run bin/vidctrl_client.dart …`, `VIDCTRL_APP`) to its
  Commands block.
- [ ] **Step 4: Run, PASS; then `flutter run -d linux`, check that
  `control.json` appears in `$XDG_RUNTIME_DIR/vidctrl/` and is gone after
  closing the window.**
- [ ] **Step 5: Commit** (after OK): "Open the window to vidctrl-client while it runs"

### Task 8: The client program

**Files:**
- Create: `lib/core/control/client.dart`, `lib/core/control/launcher.dart`, `bin/vidctrl_client.dart`
- Modify: `pubspec.yaml` (`flutter pub add args`)
- Test: `test/core/control/client_test.dart`, `test/core/control/launcher_test.dart`, `test/core/control/client_process_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3, 6 (method and event names, views).
- Produces:
  - `class ClientIo { ClientIo({required StringSink out, required StringSink err, required Map<String, String> environment, required String workingDirectory, required String executable /* resolved */, AppLauncher? launcher, EndpointFile? endpoint}); }`
  - `Future<int> runClient(List<String> args, ClientIo io)` — returns the exit code; `bin/vidctrl_client.dart` is `exit(await runClient(args, ClientIo(out: stdout, ..., executable: Platform.resolvedExecutable)))`.
  - Commands in this task: `status`, `goals`, `add <paths…> [--no-wait]`, `videos [--goal g] [--opt k=v]…`, `remove <videos…>`, `queue` (list), `queue add <videos…> [--goal] [--opt]… [--sample start|middle] [--out next|<folder>] [--subfolder Name]`, `wait [jobs…] [--timeout s]`, `events [--since-now]`; global flags `--json`, `--no-start`. `manual` and `help` arrive in Task 9; no arguments prints the quick start (Task 9) — until then the usage list.
  - Paths: every path argument (and `--out` folder) is made absolute against `workingDirectory`, a leading `~/` expanded from `HOME` (`USERPROFILE` on Windows), then `p.normalize`d.
  - Connecting: `connectIfLive(endpoint)`; when null and the command is not `status`: with `--no-start` exit 2; else `launcher.start()`, print "Starting VidCtrl…" to `err`, poll `connectIfLive` every 250 ms up to 30 s, then wait for `status.state != 'starting'`; `ffmpegMissing` → print the reason, exit 6. `status` when not running prints "VidCtrl is not running." / `{"running": false}`, exit 0.
  - Output: with `--json` the method's result as one JSON document (or one JSON line per event for `events`), otherwise lines for people built from `words.dart`. Errors go to `err` (`{"error": {kind, message}}` with `--json`) and exit with `kind.exitCode`.
  - `wait`: prints each outcome as it is known; exit 0, or 1 if any outcome is failed or cancelled; `--timeout` passed → 3; the connection ends before the answer → 4. A `queue-paused` notification prints once "The queue is paused in the window; still waiting." to `err`.
  - `events`: subscribe (`snapshot: !sinceNow`), print each notification until `done` → exit 4 after `app-closing`, 4 too when the socket just ends.
  - `class AppLauncher { AppLauncher({required String os, required String clientExecutable, required Map<String, String> environment}); String? get appPath; Future<void> start(); }` — `appPath`: `VIDCTRL_APP` if set; Linux `<dir>/vidctrl`, Windows `<dir>\vidctrl.exe`, macOS the `*.app` enclosing `<dir>` when `<dir>` ends in `.app/Contents/MacOS`; null when that file is missing. `start`: macOS `open <app>`; others `Process.start(appPath, [], mode: ProcessStartMode.detached)`; no app → `ControlError(notRunning, 'VidCtrl was not found next to vidctrl-client; start it, or set VIDCTRL_APP.')` (exit 2).

- [ ] **Step 1: Failing tests** (a `ControlListener` with a scripted handler stands in for the app; `io.out`/`io.err` are `StringBuffer`s)

```dart
test('relative and ~ paths are sent absolute', () async {
  // workingDirectory '/home/alice/work', HOME '/home/alice';
  // runClient(['add', 'clip.mov', '~/Videos', './x/../y.mp4'])
  // → handler saw paths ['/home/alice/work/clip.mov', '/home/alice/Videos', '/home/alice/work/y.mp4']
});
test('queue add sends goal, options, sample and folder as given', () async {
  // ['queue','add','3','--goal','archive','--opt','speed=fast','--sample','middle','--out','/out']
  // → params {videos:[3], goal:'archive', options:{'speed':'fast'}, sample:'middle', out:'/out'}
});
test('--json prints the answer as JSON', () async {});
test('a bad argument exits 5 with the message', () async {
  // handler throws ControlError(badArgument, 'Goals: archive, …') → exit 5, err contains 'archive'
});
test('wait exits 1 when a job failed and 0 when all are done', () async {});
test('wait exits 4 when the app goes away', () async {
  // handler for 'wait' never answers; listener.close(farewell: false) → exit 4, no hang
  // (test timeout 5 s)
});
test('wait --timeout exits 3', () async {});
test('events prints each event as a JSON line and ends with the app', () async {});
test('without a running app, --no-start exits 2', () async {});
test('without a running app, it starts the window and goes on', () async {
  // fake AppLauncher whose start() binds a listener and writes the endpoint
  // → command succeeds; err contains 'Starting VidCtrl'
});
test('FFmpeg missing exits 6 without waiting for the start timeout', () async {});
test('status without a running app says so and exits 0', () async {});

// launcher_test.dart
test('the app is found beside the client on each system', () {
  // temp dir with 'vidctrl' → linux appPath; 'vidctrl.exe' → windows;
  // '/tmp/x/VidCtrl.app/Contents/MacOS/vidctrl-client' → '/tmp/x/VidCtrl.app' (dir created)
});
test('VIDCTRL_APP wins', () {});

// client_process_test.dart
test('the compiled entry point runs as a process', () async {
  // a ControlListener in the test answering status; write its endpoint to a temp
  // file; Process.run('dart', ['run', 'bin/vidctrl_client.dart', 'status', '--json'],
  //   environment: {'VIDCTRL_ENDPOINT': <temp file>}) → exit 0, stdout parses as JSON
});
```

`VIDCTRL_ENDPOINT=<file>` overrides `EndpointFile.forThisUser()` (for tests
and for two copies side by side in development); add it to `endpoint.dart`.

- [ ] **Step 2: Run, FAIL.** `flutter test test/core/control/`
- [ ] **Step 3: Implement** with `package:args` (`ArgParser` with one
  sub-command parser per command; `queue` has its own sub-commands).
- [ ] **Step 4: Run, PASS; then by hand:** `flutter run -d linux`, and in
  another terminal `dart run bin/vidctrl_client.dart add <a test clip>`,
  `… queue add <id> --goal remux`, `… wait`; the window shows each step and
  `wait` exits 0.
- [ ] **Step 5: Commit** (after OK): "Add vidctrl-client, to add and queue videos in the open window from a terminal or an agent"

### Task 9: The manual

**Files:**
- Create: `lib/core/control/manual.dart`, `tool/make_manual.dart`, `lib/core/control/manual_words.g.dart` (generated), `docs/CLIENT.md` (generated)
- Modify: `lib/core/control/client.dart` (`manual`, `help`, no arguments, `--help`)
- Test: `test/core/control/manual_test.dart`

**Interfaces:**
- Produces:
  - `manual_words.g.dart`: `const manualGoalWords = <String, ({String title, String subtitle, String hint, Map<String, ({String title, Map<String, ({String label, String hint})> choices})> options})>{...}` keyed by preset id, written by `tool/make_manual.dart` (run as `flutter test tool/make_manual.dart`, like `make_icons.dart`) from `lookupAppLocalizations(const Locale('en'))` and `scenario_texts.dart`.
  - `String quickStart(String client)` — the dozen lines of the spec's "The prompt", with `client` as the quoted command; shared with the agent prompt (Task 13).
  - `String manual({required String client})` — Markdown, sections in this order: Quick start; What VidCtrl is (videos, goals, queue, jobs as snapshots, the window shows all, nothing converts without it, output names carry the settings, samples in `Samples/`); What it never does (deletes no file; remove only takes off the list or out of the queue); Commands (each: what it does, arguments, an example, text and `--json` output with field names and types from `views.dart`, errors); Goals (from `registry.dart` + `manualGoalWords`: id, words, options, choices, default, hint); What the results mean (statuses and outcomes from `words.dart`); Waiting and events (the `wait` rules, exit codes table, event list); Recipes (the four of the spec); Limits.
  - `String commandHelp(String command)` — that command's section.
  - `Map<String, Object?> manualJson()` — `{commands: [{name, arguments, description}], goals: [GoalView-like], exitCodes: {...}, events: [...]}`.
  - Client: `manual [--json]`, `help [command]`, `--help` (usage list ending "Run `vidctrl-client manual` for the full guide."), no arguments → `quickStart`. None of these connects to the app.

- [ ] **Step 1: Failing tests**

```dart
test('the manual covers every command the client knows', () {
  for (final c in clientCommands) { // exported from client.dart: the parser's command names
    expect(manual(client: 'vidctrl-client'), contains('vidctrl-client $c'), reason: c);
  }
});
test('the manual lists every goal, option and choice', () {
  for (final s in scenarios) for (final preset in s.presets) {
    expect(manual(client: 'x'), contains(preset.id));
    for (final o in preset.options) for (final c in o.choices) {
      expect(manual(client: 'x'), contains('$c'));
    }
  }
});
test('the manual, help and quick start never speak of deleting files', () {
  final texts = [manual(client: 'x'), quickStart('x'), for (final c in clientCommands) commandHelp(c)];
  for (final t in texts) {
    expect(speaksOfDeleting(t), isFalse);
  }
});
test('the manual says plainly that remove leaves the file on disk', () {
  expect(manual(client: 'x'), contains(neverDeletes));
  expect(quickStart('x'), contains(filesRule));
});
test('docs/CLIENT.md is the manual as it is now', () {
  expect(File('docs/CLIENT.md').readAsStringSync(), manual(client: 'vidctrl-client'));
});
test('the goal words are up to date with the English texts', () {
  // regenerate in memory with the same function make_manual.dart uses and
  // compare with manual_words.g.dart's content
});
test('manual and help need no running app', () async {
  // runClient(['manual']) with an endpoint file that does not exist → exit 0, no start
});
```

The generator's function lives in `tool/make_manual.dart` as
`String manualWordsSource()`; the test imports it (flutter test can import
from `tool/`).

- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement; run `flutter test tool/make_manual.dart` to
  write the generated files.**
- [ ] **Step 4: Run, PASS. Read `dart run bin/vidctrl_client.dart manual`
  in full as an agent would: can every recipe be followed from it alone?**
- [ ] **Step 5: Commit** (after OK): "Give vidctrl-client a manual an agent can read first"

---

## Phase 2: the rest of the window's abilities

### Task 10: The rest of the queue

**Files:**
- Modify: `lib/app/control/handlers.dart`, `lib/core/control/client.dart`, `lib/core/control/manual.dart`
- Test: `test/app/control/control_server_test.dart`, `test/core/control/client_test.dart`

**Interfaces:**
- Produces (method → notifier call → result):
  - `queue.remove {jobs: [int]}` → `QueueController.remove` each → `{removed: [int]}`; text: "Taken out of the queue; any finished file stays on disk."
  - `queue.move {job, position /* 1-based */}` → `reorder(index, position - 1)`; position clamped to the list; → `{jobs: [JobView]}`.
  - `queue.retry {job}` → `retry`; not failed or cancelled → `badArgument`.
  - `queue.clearFinished` → `clearFinished` → `{removed: [int]}`.
  - `queue.pause` / `queue.resume` → Task 4's `pause()` / `resume()` → `{paused}`.
  - `queue.cancel {job?}` → `cancelActive()`; a `job` that is not the active one → `badArgument` "Job N is not converting; `vidctrl-client queue remove N` takes it out of the queue."; nothing active → `{cancelled: null}`.
  - `queue.convertAnyway {job}`, `queue.convertWhole {job}` → the controller's methods → `{added: [JobView], alreadyQueued: bool}`; not applicable (not kept as is / not a sample) → `badArgument`.
  - Client: `queue remove|move|retry|clear-finished|convert-anyway|convert-whole`, top-level `pause`, `resume`, `cancel [job]`; manual sections for each.

- [ ] **Step 1: Failing tests** — one per method, each against the button's
  effect: e.g. `queue.cancel` while a fake job runs leaves the job
  `cancelled` exactly as `cancelActive()` from the UI does; `queue.move`
  of the last job to position 1 puts it first; `queue.remove` of a done job
  leaves the (fake) output path untouched on disk (temp file still exists).
- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, PASS** (and `docs/CLIENT.md` regenerated: its test
  fails otherwise).
- [ ] **Step 5: Commit** (after OK): "Let vidctrl-client pause, cancel, reorder and retry like the queue's buttons"

### Task 11: Job details, comparing, video details, estimates

**Files:**
- Modify: `lib/app/control/handlers.dart`, `lib/core/control/client.dart`, `lib/core/control/manual.dart`
- Test: `test/app/control/control_server_test.dart`, `test/core/control/client_test.dart`

**Interfaces:**
- Produces:
  - `job.get {job, command?: bool}` → `{job: JobView, command?: String}`; `command` from `QueueController.commandFor(job)` through `singleLineCommand` for the client's system's shell (`ShellStyle`), null for one that runs nothing.
  - `job.compare {job, wait?: bool = true}` → starts `QualityController.compare(job)`; not `canCompare` → `badArgument` saying why (not done, resized or retimed, no `xpsnr`); another comparison running → `busy`; with `wait`, answers `{closeness, closenessText, vmaf?, xpsnr}` from `QualityMeasured` (or the failure's lines as `badArgument`); without, `{started: true}` and the `compare-finished` event follows.
  - `videos.details {video?|job?, raw?: bool}` → `{info: VideoView, details: [{title, rows: [[label, value]]}]}` from `encodingDetails(raw)`; with `raw`, `{raw: MediaInfo.raw}`; for a job, its result file is probed with `env.ffprobe` (not found → `notFound`).
  - `videos.estimate {videos: [id|path], goal?, options?}` → while the queue is busy: `busy` "Videos are being converted; the window measures when the queue is idle." Otherwise `EstimateCache.measure(key, info, plan, raise:)` for each, awaited, then `{videos: [VideoView with preview]}`.
  - Client: `job <id> [--command]`, `compare <job> [--no-wait]`, `details <video|job> [--raw]`, `estimate <videos…> --goal g [--opt …]`; manual sections.

- [ ] **Step 1: Failing tests** — `job.get` of a `belowTarget` job has
  `needsALook` and `quality.outcome == 'belowTarget'`, and its text says
  "Worth a look by eye"; `job.compare` on a running job is `badArgument`;
  `job.compare` with `FakeQualityMeter` finishing at 43 dB gives `same`;
  `videos.estimate` while a job runs is `busy`; `videos.estimate` puts the
  estimate in `estimateCacheProvider` (the list's preview shows it);
  `job.get --command` contains no option that the shown command lacks.
- [ ] **Step 2–4:** FAIL, implement, PASS (regenerate `docs/CLIENT.md`).
- [ ] **Step 5: Commit** (after OK): "Let vidctrl-client show results, compare them and measure videos like the window"

---

## Phase 3: shipping and finding it

### Task 12: Build the client into every release

**Files:**
- Create: `tool/build_client.sh`
- Modify: `.github/workflows/ci.yml`, `tool/package_macos.sh`, `README.md`

**Interfaces:**
- Produces: `tool/build_client.sh <folder>` → `dart compile exe bin/vidctrl_client.dart -o <folder>/vidctrl-client` (`vidctrl-client.exe` on Windows, detected by `uname`/`$OS`), failing loudly.

- [ ] **Step 1:** Write `tool/build_client.sh`; run `tool/build_client.sh
  build/linux/x64/release/bundle` after `flutter build linux --release`.
  Expected: `build/linux/x64/release/bundle/vidctrl-client status` prints
  "VidCtrl is not running." and exits 0; with the bundle's `vidctrl`
  running it prints the queue summary.
- [ ] **Step 2:** In `ci.yml` after Build: Linux and Windows run
  `tool/build_client.sh` into the bundle folder before packaging; macOS
  passes the client to `package_macos.sh`, which copies it into
  `Contents/MacOS/` and signs it with `ffmpeg` and `ffprobe` (same `sign`
  call, ad hoc without the Apple secrets; Task 0, when done, may add an
  entitlement). Extend "Check the FFmpeg
  inside the app" to check the client is there and runs `vidctrl-client
  --help` (exit 0).
- [ ] **Step 3:** `format` and `analyze` steps include `bin`
  (`dart format ... lib test tool bin`); update CLAUDE.md's command to match.
- [ ] **Step 4:** README: a feature line and a section "Use with an AI
  agent": what it is, the button in the window, the quick start, and how to
  put the program on the `PATH` (`ln -s <bundle>/vidctrl-client
  ~/.local/bin/`, macOS `/usr/local/bin`, Windows: add the folder to
  `PATH`), and that a sandboxed agent must be allowed to run it outside its
  sandbox.
- [ ] **Step 5:** Push a branch; CI green on the three systems; download
  each artifact and run `vidctrl-client --help` from it.
- [ ] **Step 6: Commit** (after OK): "Ship vidctrl-client beside the app on Linux, Windows and macOS"

### Task 13: "Use with an AI agent"

**Files:**
- Create: `lib/app/control/agent_prompt.dart`, `lib/app/home/widgets/agent_button.dart`
- Modify: `lib/app/home/widgets/app_header.dart`, `lib/app/home/widgets/about_button.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_uk.arb` (then `flutter gen-l10n`), `test/screenshots/screenshots_test.dart`, `docs/ROADMAP.md`
- Test: `test/app/agent_button_test.dart`

**Interfaces:**
- Consumes: Task 9's `quickStart`.
- Produces:
  - `String? clientExecutable({required String appExecutable, required String os, required bool Function(String) exists})` — `<dir of appExecutable>/vidctrl-client` (`.exe` on Windows; on macOS the same `Contents/MacOS/` folder); null when missing. A provider `clientExecutableProvider` gives it for `Platform.resolvedExecutable`; tests override it.
  - `String agentPrompt({required String clientPath, required String languageName})` — `quickStart('"$clientPath"')` plus "Answer me in $languageName." when the language is not English.
  - `AgentButton` (ConsumerWidget, in the header between `NewVersionTag`'s spacer and `AboutButton`): an `IconButton` with `Icons.smart_toy_outlined`, size 20, compact, a hue from `look.hues` not used elsewhere in the header, falling back to `scheme.onSurfaceVariant`, tooltip `l10n.agentTitle`; hidden (SizedBox.shrink) unless `environmentProvider` has a value. About menu gets an item with the same title. Both open `AgentDialog`.
  - `AgentDialog`: title `agentTitle`; `agentIntro`; the prompt (fixed-width, selectable, in a bordered box) with a Copy button (`Clipboard.setData`, then "Copied" for 2 s); the program's path with Copy and `revealInFileManager`; three lines `agentKindCommands`, `agentKindChat`, `agentKindSandbox`. With `clientExecutable` null: `agentMissing` instead of the prompt, Copy disabled.
  - ARB keys and copy (English / Ukrainian):
    - `agentTitle`: "Use with an AI agent" / "Робота з ШІ-агентом"
    - `agentIntro`: "Let an AI agent such as Claude add videos and start conversions for you. You keep watching here." / "Нехай ШІ-агент, наприклад Claude, додає відео й запускає конвертацію за вас. А ви стежите тут."
    - `agentPromptLabel`: "Paste this into your agent" / "Вставте це у свого агента"
    - `agentCopy`: "Copy" / "Копіювати"; `agentCopied`: "Copied" / "Скопійовано"
    - `agentProgramLabel`: "The program the agent uses" / "Програма, якою користується агент"
    - `agentShowInFolder`: "Show in folder" / "Показати в теці"
    - `agentKindCommands`: "Agents that run commands (Claude Code, Codex, a terminal): paste the text above." / "Агенти, що запускають команди (Claude Code, Codex, термінал): вставте текст вище."
    - `agentKindChat`: "A chat that cannot run commands cannot use VidCtrl; use an agent that can." / "Чат, який не запускає команд, не зможе працювати з VidCtrl; візьміть агента, що вміє."
    - `agentKindSandbox`: "If your agent runs in a sandbox, let it run this program outside it." / "Якщо агент працює в пісочниці, дозвольте йому запускати цю програму поза нею."
    - `agentMissing`: "This build has no vidctrl-client beside it. Build it with tool/build_client.sh." / "Поруч із цією збіркою немає vidctrl-client. Зберіть його через tool/build_client.sh."

- [ ] **Step 1: Failing tests**

```dart
test('the prompt names the program, the manual, waiting and the rule about files', () {
  final text = agentPrompt(clientPath: '/opt/vidctrl/vidctrl-client', languageName: 'English');
  expect(text, contains('"/opt/vidctrl/vidctrl-client" manual'));
  expect(text, contains('wait'));
  expect(text, contains(filesRule));
  expect(speaksOfDeleting(text), isFalse);
});
```

```dart
test('in Ukrainian the agent is asked to answer in Ukrainian', () {});
test('the program is found beside the app, or reported missing', () {});
testWidgets('the header button opens the window and Copy copies the prompt', (tester) async {
  // pumpApp with clientExecutableProvider overridden to '/opt/vidctrl/vidctrl-client';
  // tap tooltip 'Use with an AI agent'; tap 'Copy'; Clipboard holds agentPrompt(...)
});
testWidgets('no button on the engine-missing screen', (tester) async {});
testWidgets('without the program the window says how to build it and cannot copy', (tester) async {});
testWidgets('the About menu opens the same window', (tester) async {});
```

- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement; `flutter gen-l10n`.**
- [ ] **Step 4: Run the fast suite (the header and no-scrolling tests
  included) at the smallest window in both looks and both languages, PASS.
  Add the dialog to `screenshots_test.dart` (`6_agent_cozy.png`,
  `6_agent_pro.png`), run `flutter test --tags screenshots`, look at the
  PNGs; the main screen gained a header icon, so redraw the README's
  pictures (`flutter test tool/make_screenshots.dart`).**
- [ ] **Step 5:** ROADMAP: move "vidctrl-client and the agent window" into
  Done in one sentence.
- [ ] **Step 6: Commit** (after OK): "Offer a ready prompt to let an AI agent work with VidCtrl"

---

## Before handing over

- [ ] `flutter test --exclude-tags "ffmpeg || screenshots"`, `flutter analyze`,
  `dart format --output=none --set-exit-if-changed lib test tool bin`: clean.
- [ ] `flutter test --tags ffmpeg` once (the engine was touched only through
  the controllers' signatures, but `addVideos` replaced `_add`).
- [ ] With a release build of the app and the client on the `PATH`, give
  Claude Code the prompt from the window and ask: "Find videos over 500 MB
  in <a test folder>, archive them and tell me when it's done." Watch the
  window; note what the agent stumbled on and fix the manual.
