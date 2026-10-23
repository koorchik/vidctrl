import 'dart:io' show Platform;

import '../media/media_details.dart' show DetailGroup;
import '../scenarios/registry.dart';
import '../scenarios/scenario.dart';
import 'codes.dart';
import 'manual_commands.dart';
import 'manual_words.g.dart';
import 'protocol.dart';
import 'words.dart';

// The manual of vidctrl-client, for an agent that has never seen the window.
// `manual` prints a short reference, small enough to be read in one go;
// `help <command>` prints one command's details: its examples, what it
// prints, a JSON sample, and the shapes and codes of its answer in full.
// docs/CLIENT.md, written by tool/make_manual.dart, is both
// (`manualDocument`). Each command has one `CommandDoc` in `commandDocs`
// (manual_commands.dart); a new command adds its own. The goals come from the
// registry, their words from the English texts (manual_words.g.dart).
// Nothing here speaks of deleting a file (see `speaksOfDeleting`).

typedef ChoiceWords = ({String label, String hint});
typedef OptionWords = ({
  String title,
  String hint,
  Map<String, ChoiceWords> choices,
});

/// A goal's English words, as the window's panel shows them.
typedef GoalWords = ({
  String title,
  String subtitle,
  String hint,
  Map<String, OptionWords> options,
});

/// [client] as it is typed in the terminal of [os] (`Platform.operatingSystem`)
/// to run it: a plain name as it is, a path quoted. On Linux and macOS in
/// single quotes, so a `$` in it does not expand. On Windows in double
/// quotes, which Git Bash (where Claude Code runs its commands), cmd and
/// PowerShell all read; PowerShell also needs `&` before a quoted path,
/// which [quickStart] says.
String shellWord(String client, {required String os}) {
  if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(client)) return client;
  if (os == 'windows') return '"$client"';
  return "'${client.replaceAll("'", r"'\''")}'";
}

/// Whether [client] typed on [os] needs PowerShell's `&` before it: a
/// quoted path on Windows.
bool needsCallOperator(String client, {required String os}) =>
    os == 'windows' && shellWord(client, os: os) != client;

/// What an agent needs before anything else, with [client] as the command
/// that runs this program on [os]: what the program is and to read its
/// manual. It is what the client prints with no arguments, the start of the
/// manual's quick start, and the prompt the window gives to copy in English
/// (the window's own copy in each language is in its texts).
String quickStart(String client, {required String os}) {
  final c = shellWord(client, os: os);
  final powerShell = needsCallOperator(client, os: os)
      ? '- In PowerShell, put & before a quoted path: `& $c manual`.\n'
      : '';
  return '''
VidCtrl is open on this computer, and the person watches its window. The program `$c` controls it: it adds videos to the window's list and queues conversions there.

- Run `$c manual` first: it explains every command, the goals and what the results mean. Add `--json` to a command to read its answer as JSON.
$powerShell''';
}

/// The rest of the manual's quick start: what an agent most needs once it
/// reads on, which the prompt leaves to the manual.
String _firstSteps(String c) =>
    '''
- Finding the videos is your job (with `find`, `du` or the like). Give their paths to `$c add`, or straight to `$c queue add --goal <goal>`.
- The window converts one video at a time, and that can take hours. To know when it ends, run `$c wait` in the background (or follow `$c events`), and tell the person when it returns: each result, and any marked "worth a look by eye".
- $filesRule "Remove" only takes a video off the list or a job out of the queue.
''';

/// The short list `--help` prints. Its examples are typed for [os]'s
/// terminal (this system's by default), as are [commandHelp]'s and
/// [manual]'s.
String usage({String client = 'vidctrl-client', String? os}) {
  final c = shellWord(client, os: os ?? Platform.operatingSystem);
  final docs = commandDocs(c);
  final width = docs
      .map((d) => _synopsis(d).length)
      .reduce((a, b) => a > b ? a : b);
  return [
    '$c adds videos to the open VidCtrl window and follows its queue.',
    '',
    'Usage: $c <command> [arguments] [options]',
    '',
    for (final area in CommandArea.values) ...[
      '${area.title}:',
      for (final doc in docs.where((d) => d.area == area))
        '  ${_synopsis(doc).padRight(width)}  ${doc.summary}',
    ],
    '',
    'Every command takes --json, --no-start and --help.',
    'Run `$c manual` for the full guide.',
    '',
  ].join('\n');
}

/// One command's details, as `help <command>` prints them: its part of the
/// guide, then the shapes and codes its JSON answer is made of, in full.
/// [command] is one of `clientCommands`.
String commandHelp(
  String command, {
  String client = 'vidctrl-client',
  String? os,
  Map<String, GoalWords> words = manualGoalWords,
}) {
  final c = shellWord(client, os: os ?? Platform.operatingSystem);
  final doc = commandDocs(c, words).where((d) => d.name == command).firstOrNull;
  if (doc == null) throw ArgumentError.value(command, 'command');
  final text = [
    _commandDetails(c, doc, words),
    for (final shape in _shapes.keys)
      if (doc.shapes.contains(shape)) _shapeSection(shape, '####'),
    for (final kind in _codeKindsOf(doc)) _codeKindSection(kind, '####'),
  ].join('\n');
  return '${text.trimRight()}\n';
}

/// The manual: a short reference to every command, the JSON, the codes and
/// the goals, in Markdown. Each command's details are in [commandHelp].
String manual({
  required String client,
  String? os,
  Map<String, GoalWords> words = manualGoalWords,
}) {
  os ??= Platform.operatingSystem;
  final c = shellWord(client, os: os);
  return [
    '# vidctrl-client',
    '',
    '`vidctrl-client` controls the open VidCtrl window. Below, `$c` '
        'stands for the program as you '
        'run it: by its full path when not on the `PATH`, quoted as the '
        "window's prompt has it: `'/opt/VidCtrl/vidctrl-client'`, "
        '`"C:\\…\\vidctrl-client.exe"` on Windows, '
        '`& "C:\\…\\vidctrl-client.exe"` in PowerShell.',
    '',
    '## Quick start',
    '',
    quickStart(client, os: os) + _firstSteps(c),
    _about(c),
    _never(c),
    _commandsPart(c, words),
    _jsonPart(),
    _codesPart(c),
    _goalsPart(c, words),
    _waitingPart(c),
    _recipes(c),
    _limits(c),
  ].join('\n');
}

/// docs/CLIENT.md: the manual, then every command's details, then the
/// shapes and codes they share, in full.
String manualDocument({
  required String client,
  String? os,
  Map<String, GoalWords> words = manualGoalWords,
}) {
  final c = shellWord(client, os: os ?? Platform.operatingSystem);
  return [
    manual(client: client, os: os, words: words),
    '## Command details',
    '',
    'What `$c help <command>` prints for each command; the shapes and codes '
        'it adds follow, once for all.',
    '',
    for (final doc in commandDocs(c, words)) _commandDetails(c, doc, words),
    '## What `--json` gives, in full',
    '',
    'Each field is named with its JSON type; one marked "optional" is left '
        'out when not known.',
    '',
    for (final shape in _shapes.keys) _shapeSection(shape, '###'),
    '## Codes in full',
    '',
    'Every code by where it is found, with the words the client prints for '
        'people and what it means. The events are under "Events".',
    '',
    for (final kind in codeKinds)
      if (kind.name != 'event') _codeKindSection(kind, '###'),
  ].join('\n');
}

/// The manual as data, for a program that builds on it.
Map<String, Object?> manualJson({
  Map<String, GoalWords> words = manualGoalWords,
}) => {
  'commands': [
    for (final doc in commandDocs('vidctrl-client')) commandJson(doc),
  ],
  ...manualData(words: words),
};

/// A command as `manual --json` gives it.
Map<String, Object?> commandJson(CommandDoc doc) => {
  'name': doc.name,
  'arguments': doc.arguments,
  'description': doc.summary,
  'options': [
    for (final (flag, text) in doc.options) {'name': flag, 'description': text},
  ],
};

/// What `manual --json` gives besides the commands.
Map<String, Object?> manualData({
  Map<String, GoalWords> words = manualGoalWords,
}) => {
  'goals': [
    for (final scenario in scenarios)
      for (final preset in scenario.presets)
        goalJson(scenario, preset, words[preset.id]),
  ],
  'exitCodes': {for (final (code, _, meaning) in _exitCodes) '$code': meaning},
  'events': [
    for (final (name, fields, meaning, _) in _events)
      {'name': name, 'fields': fields, 'description': meaning},
  ],
  'codes': {
    for (final kind in codeKinds)
      kind.name: [
        for (final code in kind.codes)
          {'code': code.code, 'description': code.meaning},
      ],
  },
};

/// A goal as `manual --json` gives it.
Map<String, Object?> goalJson(
  Scenario scenario,
  Preset preset,
  GoalWords? words,
) => {
  'id': preset.id,
  'scenario': scenario.id,
  'goal': _goalName(scenario, preset),
  'title': words?.title ?? preset.id,
  'subtitle': words?.subtitle ?? '',
  'hint': words?.hint ?? '',
  'options': [
    for (final option in preset.options)
      {
        'id': option.id,
        'title': words?.options[option.id]?.title ?? option.id,
        'hint': words?.options[option.id]?.hint ?? '',
        'defaultChoice': option.defaultChoice,
        'advanced': option.advanced,
        'choices': [
          for (final choice in option.choices)
            {
              'id': choice,
              'label':
                  words?.options[option.id]?.choices[choice]?.label ?? choice,
              'hint': words?.options[option.id]?.choices[choice]?.hint ?? '',
            },
        ],
      },
  ],
};

/// The shortest name `--goal` takes: the kind's when it has no other.
String _goalName(Scenario scenario, Preset preset) =>
    scenario.presets.length == 1 ? scenario.id : preset.id;

// ---- What VidCtrl is -----------------------------------------------------

String _about(String c) =>
    '''
## What VidCtrl is

A window that converts videos by goal; `$c` changes what it shows, as the person would with the mouse.

- **Videos**: the window's list. `add` is like dropping a file there; each file is listed once, and videos just added become the selection.
- **Goals**: what to make of a video, by the panel's ids (see "Goals").
- **Jobs**: `queue add` makes one per video, a snapshot of video, goal, options and folder that later changes do not touch. The queue starts by itself and goes in order.
- **The window shows everything**; the person may act there too (pause, add, take jobs out), and this program sees it.
- **Nothing converts without the window.** Every command but `status`, `manual` and `help` opens one if none is ("Starting VidCtrl…" on stderr, up to 30 s); closing it stops conversions. Two commands at once may each open one: run `$c queue` first, then `events` in the background.
- **Results** are new files, by default in `Converted` beside each video, named with the settings (`beach.mov` gives `Converted/beach_av1-crf35.mp4`, a second ` (2)`), written as a hidden `.part` until whole.
- **Samples**: 10 seconds from the start or middle, with the whole's settings, into `Samples` there (`beach_av1-crf35_sample10s.mp4`, `_sample10s-mid`).
- **Ids** count from 0, lasting, like the list and queue, while the window is open. Digits only is an id: a file named `3` is `./3`. Paths may be relative or start with `~`.
''';

String _never(String c) =>
    '''
## What VidCtrl never does

$neverDeletes

- No command changes, moves or renames a file, nor closes the window or changes its panel's goal, remembered settings, look or language.
- $filesRule Leave every file to the person.
''';

// ---- Commands ------------------------------------------------------------

String _synopsis(CommandDoc doc) =>
    [doc.name, if (doc.arguments.isNotEmpty) doc.arguments].join(' ');

/// [doc]'s synopsis with its options, as the manual's entry gives it.
String _usageLine(CommandDoc doc) => [
  _synopsis(doc),
  for (final (flag, _) in doc.options)
    if (!doc.arguments.contains(flag)) '[$flag]',
].join(' ');

String _commandsPart(String c, Map<String, GoalWords> words) => [
  '## Commands',
  '',
  '`$c <command> [arguments] [options]`. All take `--json` (one JSON '
      'document; `events`: one per line), `--no-start` (exit 2, not open the '
      'window) and `--help`. Videos by id or path, jobs by id; one `--opt` '
      'per option. A goal, option or choice unknown or not offered here (see '
      '`goals`) is refused, naming the valid ones, but for the choice the '
      'goal makes here anyway. Errors: stderr and an exit code (see '
      '"Waiting"). `→` is the `--json` answer.',
  '',
  for (final doc in commandDocs(c, words))
    '- `${_usageLine(doc)}`: ${doc.brief} → ${doc.answer}',
  '',
  '`$c help <command>` prints a command\'s examples, its text output and a '
      'JSON sample.',
  '',
].join('\n');

/// [doc]'s part in full, with what goes with it: a recipe, and for some
/// commands the rules or the lists they follow.
String _commandDetails(
  String c,
  CommandDoc doc,
  Map<String, GoalWords> words,
) => [
  _commandSection(c, doc),
  ?_recipesOf(c)[doc.name],
  ...switch (doc.name) {
    'goals' => [_goalsInFull(words)],
    'wait' => [_waitingInFull(c)],
    'events' => [_eventsInFull(c)],
    _ => const <String>[],
  },
].join('\n');

String _commandSection(String c, CommandDoc doc) => [
  '### `$c ${_synopsis(doc)}`',
  '',
  '${doc.summary[0].toUpperCase()}${doc.summary.substring(1)}.',
  '',
  for (final paragraph in doc.about) ...[paragraph, ''],
  if (doc.options.isNotEmpty) ...[
    'Options:',
    '',
    for (final (flag, text) in doc.options) '- `$flag`: $text',
    '',
  ],
  doc.examples.length == 1 ? 'Example:' : 'Examples:',
  '',
  '```sh',
  ...doc.examples,
  '```',
  '',
  'It prints, for example:',
  '',
  '```',
  ...doc.text,
  '```',
  '',
  'With `--json`: ${doc.json.first}',
  '',
  for (final line in doc.json.skip(1)) ...[line],
  if (doc.json.length > 1) '',
  if (doc.errors.isNotEmpty) ...[
    'Errors:',
    '',
    for (final error in doc.errors) '- $error',
    '',
  ],
].join('\n');

/// Each error code: its exit code with a few words, and in full.
final _errorCodes = [
  (
    ControlErrorKind.badArgument.code,
    '5, not valid',
    'a command, goal, option, choice or value that is not valid (exit 5)',
  ),
  (ControlErrorKind.notFound.code, '5', 'no such video or job (exit 5)'),
  (
    ControlErrorKind.busy.code,
    '5, not now',
    'the window cannot do that right now (exit 5)',
  ),
  (
    ControlErrorKind.unknownMethod.code,
    '5, the window is another version',
    'the open window is of another version and does not know the request '
        '(exit 5)',
  ),
  (
    ControlErrorKind.ffmpegMissing.code,
    '6',
    'the window could not find FFmpeg and shows what to do (exit 6)',
  ),
  (
    ControlErrorKind.unauthorized.code,
    '2, the window refused or did not answer',
    'the window is open but refused the connection or did not answer; no '
        'other window is started (exit 2)',
  ),
  (
    ControlErrorKind.notRunning.code,
    '2, none open and none could be',
    'the window is not open and could not be opened (exit 2)',
  ),
  (
    ControlErrorKind.appClosed.code,
    '4',
    'the window closed meanwhile (exit 4)',
  ),
  (
    ClientErrorCodes.timeout,
    '3, the jobs go on',
    '`--timeout` passed; the jobs go on in the window (exit 3)',
  ),
  (
    ClientErrorCodes.unexpected,
    '5, the client went wrong',
    'the client itself went wrong; the message says how (exit 5)',
  ),
];

// ---- Shapes ----------------------------------------------------------------

String _jsonPart() => '''
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
''';

String _shapeSection(String name, String level) =>
    '$level $name\n\n${_shapes[name]}';

/// The shapes in full, each in Markdown: what it is, then each field with
/// its JSON type.
const _shapes = {
  'Status': '''
How the window stands.

- `state` (string): `STARTING`, `READY` or `FFMPEG_MISSING`, see "Window states".
- `version` (string): VidCtrl's version; empty in a development build.
- `busy` (bool): the queue is working through jobs.
- `paused` (bool): the queue is paused in the window.
- `jobs` (object): how many jobs there are in each status, by its code, as `{"WAITING": 2, "DONE": 1}`.
''',
  'Goal': '''
A goal, with the options this computer offers.

- `id` (string): the goal's full id, as `archive.master`; `--goal` takes it always.
- `scenario` (string): its kind, as `archive`; `--goal` takes it when the kind has one goal only.
- `title` (string): its name in the window.
- `subtitle` (string): what sets it apart from a like one; may be empty.
- `options` (list of Option).
''',
  'Option': '''
One option of a goal: `--opt <id>=<choice>`.

- `id` (string).
- `title` (string): its name in the window.
- `defaultChoice` (string): the choice made when none is given.
- `advanced` (bool): under "More options…" in the window.
- `choices` (list of Choice).
''',
  'Choice': '''
One choice of an option.

- `id` (string): what `--opt` takes.
- `label` (string): its name in the window.
- `hint` (string): what it trades away; may be empty.
''',
  'Video': '''
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
''',
  'Preview': '''
What a goal would do to a video, as the list shows it.

- `goal` (string): the goal's full id.
- `plan` (string): what it would do, see "Plans".
- `expectedBytes` (int, optional): the result's expected size.
- `measured` (bool): the size was measured by encoding pieces, not calculated.
- `measuring` (bool): the window is measuring it now.
- `closeness` (string, optional): how close the result would look, see "Closeness".
''',
  'Job': '''
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
''',
  'Quality': '''
How a job's quality was chosen: Archive measures each video before converting it and compares pieces of the result with the original.

- `outcome` (string): see "Quality outcomes".
- `value` (int, optional): the quality number chosen (lower is better).
- `standardValue` (int, optional): the goal's usual number.
- `vmaf` (number, optional): VMAF of the poorest piece; 95 and more looks the same.
- `xpsnr` (number, optional): XPSNR of the poorest piece, in dB.
- `share` (number): the expected size as a share of the original's, 0 to 1.
''',
  'Outcome': '''
How a job ended, as `wait` tells it.

- `jobId` (int).
- `path` (string): the video's file.
- `status` (string): `DONE`, `SKIPPED`, `FAILED`, `CANCELLED` or `REMOVED`, see "Job statuses".
- `outputPath` (string, optional): the result, when done.
- `needsALook` (bool): worth a look by eye, see `BELOW_TARGET`.
''',
};

/// The kinds of code each shape carries, by their `codeKinds` name.
const _shapeCodes = {
  'Status': ['state', 'jobStatus'],
  'Video': ['videoStatus'],
  'Preview': ['plan', 'closeness'],
  'Job': ['jobStatus', 'sample'],
  'Quality': ['qualityOutcome'],
  'Outcome': ['jobStatus'],
};

/// The kinds of code [doc]'s answer carries, in the order of [codeKinds].
List<CodeKind> _codeKindsOf(CommandDoc doc) {
  final names = {
    for (final shape in doc.shapes) ...?_shapeCodes[shape],
    ...doc.codes,
  };
  return [
    for (final kind in codeKinds)
      if (names.contains(kind.name)) kind,
  ];
}

// ---- Codes -----------------------------------------------------------------

/// One code: a few words for the manual's list (may be none), and what it
/// means in full.
typedef Code = ({String code, String brief, String meaning});

/// One kind of code: where it is found, and its codes.
typedef CodeKind = ({
  String name,
  String title,
  String where,
  List<Code> codes,
});

/// Job statuses: a few words, and what to make of each.
const _jobStatuses = [
  (JobStatusCodes.waiting, '', 'In the queue, its turn not come yet.'),
  (
    JobStatusCodes.running,
    'converting or choosing quality',
    'Being converted now, or its quality being chosen (`attempt`).',
  ),
  (
    JobStatusCodes.paused,
    'held by a pause',
    'Under way, held because the queue is paused in the window.',
  ),
  (
    JobStatusCodes.done,
    'result at `outputPath`',
    'The result is at `outputPath`. Tell the person, and say so when '
        '`needsALook` is true. `compare <job>` says how close it looks to '
        'the original.',
  ),
  (
    JobStatusCodes.skipped,
    'nothing written; not a failure',
    'Nothing was written: the video already met the goal, the goal can do '
        'nothing with it (plan `UNSUPPORTED`), or converting would hardly '
        'make it smaller (outcome `NOT_WORTH_IT`). Counts as finished, not '
        'as a failure.',
  ),
  (
    JobStatusCodes.failed,
    'see `errorLines`',
    'It could not be converted; `errorLines` says why. The person '
        'can try it again in the window, as `queue retry <job>` does.',
  ),
  (
    JobStatusCodes.cancelled,
    'a failure for `wait`',
    'Stopped before it was done, in the window or by `cancel`. `wait` '
        'counts it as a failure; `queue retry <job>` tries it again.',
  ),
  (
    JobStatusCodes.removed,
    '`wait` only: taken out, not a failure',
    'Only in `wait`, for a job taken out of the queue while it waited. Not '
        'a failure.',
  ),
];

const _videoStatuses = [
  (
    VideoStatusCodes.probing,
    'being read',
    'VidCtrl is learning its size, length, picture and sound.',
  ),
  (VideoStatusCodes.ready, 'can be queued', 'It can be queued.'),
  (
    VideoStatusCodes.unreadable,
    'not a video FFmpeg opens',
    'It cannot be queued.',
  ),
];

const _planNotes = {
  PlanCodes.skip: (
    'already fine (`SKIPPED`)',
    'Queued, the job ends `SKIPPED` and writes no file.',
  ),
  PlanCodes.remux: (
    'copied into another file type',
    'Quick: the picture and sound are copied.',
  ),
  PlanCodes.audioOnly: (
    'only the sound converted',
    'Quick: the picture is copied.',
  ),
  PlanCodes.encode: (
    'the picture converted: slow',
    'The picture is converted: this takes time.',
  ),
  PlanCodes.unsupported: (
    'nothing the goal can do (`SKIPPED`)',
    'For example, a goal for pictures given a sound file. Queued, the job '
        'ends `SKIPPED`.',
  ),
  PlanCodes.keptAsIs: (
    'Archive: not worth it (`SKIPPED`)',
    'Archive only; the job ends `SKIPPED`.',
  ),
};

const _closenessNotes = {
  ClosenessCodes.same: (
    'looks the same (VMAF 95+ on the poorest piece)',
    'VMAF 95 or more on the poorest piece.',
  ),
  ClosenessCodes.veryClose: ('VMAF 93+', 'VMAF 93 or more.'),
  ClosenessCodes.differs: ('may visibly differ', 'Below that: worth a look.'),
};

const _outcomeNotes = {
  OutcomeCodes.standard: (
    'the usual quality',
    'The goal\'s usual quality was enough to look the same.',
  ),
  OutcomeCodes.raised: (
    'a better one was needed: larger',
    'A better quality than usual was needed, and the file is larger '
        'for it.',
  ),
  OutcomeCodes.belowTarget: (
    'short even at the best: named `…-check`, `needsALook`, still `DONE`; '
        'ask the person to look by eye',
    'Converted anyway, and the result\'s name ends in `-check`. '
        'Tell the person to look at it by eye beside the original. The job is '
        '`DONE` and `needsALook` is true; `wait` still exits 0.',
  ),
  OutcomeCodes.notWorthIt: (
    'would keep over 80% of the size: `SKIPPED` (see `queue '
        'convert-anyway`)',
    'The job ends `SKIPPED` and nothing is written. In the '
        'window, "Convert anyway" in the job\'s ⋯ menu converts it all the '
        'same, as `queue convert-anyway <job>` does.',
  ),
};

const _stateNotes = [
  (
    StateCodes.starting,
    'looking for FFmpeg',
    'The window has just opened and looks for FFmpeg.',
  ),
  (StateCodes.ready, '', 'Open and ready.'),
  (
    StateCodes.ffmpegMissing,
    'the window says what to do',
    'Open, but it found no FFmpeg; the window says what to do. Every '
        'command but `status` fails with `FFMPEG_MISSING`.',
  ),
];

const _addNotes = [
  (AddResultCodes.added, '', 'Added to the list now.'),
  (
    AddResultCodes.known,
    'listed already',
    'In the list already; not added twice.',
  ),
  (
    AddResultCodes.notFound,
    'nothing there, or no longer listed',
    'No file there, nor a folder with videos. As a `skipped` reason of '
        '`queue add`: nothing found there, or the video was taken off the '
        'list meanwhile.',
  ),
  (
    AddResultCodes.unreadable,
    'listed, not a video FFmpeg opens',
    'In the list, but not a video FFmpeg can open; it cannot be queued.',
  ),
];

const _sampleNotes = [
  (SampleCodes.start, '', 'Ten seconds from the start (`--sample start`).'),
  (SampleCodes.middle, '', 'Ten seconds from the middle (`--sample middle`).'),
];

const _comparisonNotes = [
  (
    ComparisonCodes.measured,
    '',
    'Compared: `closeness`, `xpsnr` and, where measured, `vmaf` say how '
        'close.',
  ),
  (
    ComparisonCodes.failed,
    'only in the event, with `errorLines`',
    'Only in `COMPARE_FINISHED`: it could not be compared; `errorLines` '
        'says why. `compare` exits 5 instead.',
  ),
];

/// What a section of `details` describes.
String _groupNote(DetailGroup group) => switch (group) {
  DetailGroup.file => 'The file as a whole: its type, size and length.',
  DetailGroup.video => 'A picture track.',
  DetailGroup.audio => 'A sound track.',
  DetailGroup.subtitle => 'A subtitle track.',
  DetailGroup.timecode => 'A timecode track, as cameras write.',
  DetailGroup.data => 'A data track, such as a camera\'s notes.',
  DetailGroup.attachment => 'A file carried inside, such as a font or a cover.',
  DetailGroup.chapters => 'The chapters.',
};

/// Every kind of code the JSON carries, each code with what it means, as
/// the manual's "Codes" lists them.
final List<CodeKind> codeKinds = [
  (
    name: 'jobStatus',
    title: 'Job statuses',
    where: 'Job and Outcome `status`, Status `jobs` keys',
    codes: [
      for (final (code, brief, note) in _jobStatuses)
        (code: code, brief: brief, meaning: '${statusWords(code)}. $note'),
    ],
  ),
  (
    name: 'videoStatus',
    title: 'Video statuses',
    where: 'Video `status`',
    codes: [
      for (final (code, brief, note) in _videoStatuses)
        (code: code, brief: brief, meaning: '${statusWords(code)}. $note'),
    ],
  ),
  (
    name: 'plan',
    title: 'Plans',
    where: 'Preview `plan`',
    codes: [
      for (final code in PlanCodes.all)
        (
          code: code,
          brief: _planNotes[code]!.$1,
          meaning: '${planWords(code)}. ${_planNotes[code]!.$2}',
        ),
    ],
  ),
  (
    name: 'closeness',
    title: 'Closeness',
    where: 'Preview `closeness`, `compare`',
    codes: [
      for (final code in ClosenessCodes.all)
        (
          code: code,
          brief: _closenessNotes[code]!.$1,
          meaning: '${closenessWords(code)}. ${_closenessNotes[code]!.$2}',
        ),
    ],
  ),
  (
    name: 'qualityOutcome',
    title: 'Quality outcomes',
    where: 'Quality `outcome`',
    codes: [
      for (final code in OutcomeCodes.all)
        (
          code: code,
          brief: _outcomeNotes[code]!.$1,
          meaning: '${outcomeWords(code)}. ${_outcomeNotes[code]!.$2}',
        ),
    ],
  ),
  (
    name: 'state',
    title: 'Window states',
    where: 'Status `state`',
    codes: [
      for (final (code, brief, note) in _stateNotes)
        (code: code, brief: brief, meaning: note),
    ],
  ),
  (
    name: 'addResult',
    title: 'Adding',
    where: '`add`\'s `result`, `queue add`\'s `skipped[].reason`',
    codes: [
      for (final (code, brief, note) in _addNotes)
        (code: code, brief: brief, meaning: note),
    ],
  ),
  (
    name: 'sample',
    title: 'Samples',
    where: 'Job `sample`',
    codes: [
      for (final (code, brief, note) in _sampleNotes)
        (code: code, brief: brief, meaning: note),
    ],
  ),
  (
    name: 'comparison',
    title: 'Comparisons',
    where: '`compare`\'s and `COMPARE_FINISHED`\'s `status`',
    codes: [
      for (final (code, brief, note) in _comparisonNotes)
        (code: code, brief: brief, meaning: note),
    ],
  ),
  (
    name: 'detailGroup',
    title: 'Details',
    where: '`details[].group`',
    codes: [
      for (final group in DetailGroup.values)
        (code: codeOf(group), brief: '', meaning: _groupNote(group)),
    ],
  ),
  (
    name: 'error',
    title: 'Errors',
    where: '`error.code`, with the exit code',
    codes: [
      for (final (code, brief, meaning) in _errorCodes)
        (code: code, brief: brief, meaning: '$meaning.'),
    ],
  ),
  (
    name: 'event',
    title: 'Events',
    where:
        '`events`\' `event`, with `time` but on `APP_CLOSING`, and '
        'these fields',
    codes: [
      for (final (name, _, meaning, brief) in _events)
        (code: name, brief: brief, meaning: meaning),
    ],
  ),
];

String _codesPart(String c) => [
  '## Codes',
  '',
  'Each kind, where it is found, and its codes; `$c help <command>` has '
      'them in full.',
  '',
  for (final kind in codeKinds)
    '- **${kind.title}** (${kind.where}): '
        '${[for (final code in kind.codes) _briefCode(code)].join('; ')}.',
  '',
].join('\n');

String _briefCode(Code code) =>
    code.brief.isEmpty ? '`${code.code}`' : '`${code.code}` ${code.brief}';

String _codeKindSection(CodeKind kind, String level) => [
  '$level ${kind.title}',
  '',
  '${kind.where[0].toUpperCase()}${kind.where.substring(1)}:',
  '',
  for (final code in kind.codes) '- `${code.code}`: ${code.meaning}',
  '',
].join('\n');

// ---- Goals -----------------------------------------------------------------

/// By a goal kind's id: what it is for and what it leaves as it is, in a few
/// words for the manual's line; and what it leaves, in full.
const _leaves = {
  'archive': (
    'Camera videos far smaller, looking the same; one not worth it is left '
        'as it is (`NOT_WORTH_IT`).',
    'Every video is converted, its quality chosen by measuring (see '
        '"Quality outcomes"). One whose result would keep over 80% of the '
        'original\'s size is kept as it is: its job ends `SKIPPED` with the '
        'outcome `NOT_WORTH_IT`. A sample is made all the same.',
  ),
  'space': (
    'Much smaller, still good to watch; every video is converted.',
    'Every video with a picture is converted.',
  ),
  'resolve': (
    'For Resolve on Linux; a video it opens is left as it is (`SKIP`), '
        'often only the sound is converted.',
    'A video Resolve already opens is left as it is (plan `SKIP`); often '
        'only the sound needs converting (`AUDIO_ONLY`).',
  ),
  'audio': (
    'The first sound track as a file, copied when it fits the type.',
    'Takes the first sound track; a video without sound is `UNSUPPORTED`. '
        'Sound that fits the file type is copied as it is.',
  ),
  'privacy': (
    'A copy without the hidden notes on place, date, camera and author; '
        '`quick` copies picture and sound, `thorough` converts them.',
    'Each result is a new copy without the hidden notes; the original '
        'stays as it is. `quick` copies picture and sound as they are '
        '(`REMUX`), `thorough` converts them again (`ENCODE`). Sound files '
        'are taken too.',
  ),
  'remux': (
    'Another file type in seconds; the picture is never converted.',
    'A video already of that file type is left as it is (`SKIP`); sound '
        'the new type cannot hold is converted (`AUDIO_ONLY`); the picture '
        'never is.',
  ),
};

String _goalsPart(String c, Map<String, GoalWords> words) => [
  '## Goals',
  '',
  'Which to choose: `archive` keeps the picture as it is in a smaller file, '
      'the usual choice to save space without loss; `space` also makes it '
      'at most 1080p and 30 fps, for calls, screen recordings and the like; '
      '`resolve.studio` to edit in DaVinci Resolve Studio, `resolve.free` in '
      'the free one (the picture converted too: much larger); the others by '
      'name.',
  '',
  'By name or full id; choices default first; options only where they make '
      'a difference (see `goals`). No picture: `UNSUPPORTED` but for `audio` '
      'and `privacy`. `help goals` has the words in full.',
  '',
  for (final scenario in scenarios)
    for (final preset in scenario.presets) _goalLine(scenario, preset, words),
  '',
].join('\n');

/// [preset]'s line in the manual's "Goals". A second goal of a kind leaves
/// out what the first says already: the kind's note and the options they
/// share.
String _goalLine(
  Scenario scenario,
  Preset preset,
  Map<String, GoalWords> words,
) {
  final goal = words[preset.id];
  final name = _goalName(scenario, preset);
  final title = [
    goal?.title ?? preset.id,
    if (goal != null && goal.subtitle.isNotEmpty) goal.subtitle,
  ].join(', ');
  final first = scenario.presets.first;
  bool told(PresetOption option) =>
      preset != first &&
      first.options.any(
        (o) =>
            o.id == option.id &&
            o.defaultChoice == option.defaultChoice &&
            o.choices.join() == option.choices.join(),
      );
  final shared = [
    for (final option in preset.options)
      if (told(option)) '`--opt ${option.id}=`',
  ];
  return [
    '- `--goal $name`${name == preset.id ? '' : ' (`${preset.id}`)'}: $title.',
    if (preset == first) ?_leaves[scenario.id]?.$1,
    for (final option in preset.options)
      if (!told(option))
        '`--opt ${option.id}=` '
            '${_briefChoices(option, goal?.options[option.id])}.',
    if (shared.isNotEmpty)
      '${shared.join(', ')} as for `${_goalName(scenario, first)}`.',
  ].join(' ');
}

/// [option]'s choices, the default first, each with its label where it
/// says more than its id.
String _briefChoices(PresetOption option, OptionWords? words) => [
  for (final choice in [
    option.defaultChoice,
    ...option.choices.where((c) => c != option.defaultChoice),
  ])
    [
      '`$choice`',
      if (words?.choices[choice]?.label case final label?
          when label.toLowerCase() != choice)
        label,
      if (choice == option.defaultChoice) '(default)',
    ].join(' '),
].join(', ');

String _goalsInFull(Map<String, GoalWords> words) {
  final lines = [
    'Each goal, by the name `--goal` takes, with its options and their '
        'choices. The full id (as `archive.master`) is taken too. An option '
        'is offered only where it makes a difference on this computer: '
        '`vidctrl-client goals` shows which are here; another is taken only '
        'with the choice the goal makes here anyway. A file with no picture '
        'is `UNSUPPORTED` by every goal but "Get the sound" and "Remove '
        'personal data".',
    '',
  ];
  for (final scenario in scenarios) {
    for (final preset in scenario.presets) {
      final goal = words[preset.id];
      final name = _goalName(scenario, preset);
      final title = [
        goal?.title ?? preset.id,
        if (goal != null && goal.subtitle.isNotEmpty) goal.subtitle,
      ].join(', ');
      lines.addAll([
        '#### $title: `--goal $name`',
        '',
        if (name != preset.id) 'Full id: `${preset.id}`.',
        if (name != preset.id) '',
        if (goal != null && goal.hint.isNotEmpty) ...[goal.hint, ''],
        if (_leaves[scenario.id] case (_, final leaves)) ...[leaves, ''],
        if (preset.options.isEmpty) ...['It has no options.', ''],
        for (final option in preset.options) ...[
          _optionLine(option, goal?.options[option.id]),
          for (final choice in option.choices)
            _choiceLine(option, choice, goal?.options[option.id]),
          '',
        ],
      ]);
    }
  }
  return lines.join('\n');
}

String _optionLine(PresetOption option, OptionWords? words) {
  final title = words?.title ?? option.id;
  final hint = words == null || words.hint.isEmpty ? '' : ' ${words.hint}';
  final advanced = option.advanced ? ' (under "More options…")' : '';
  return '- `--opt ${option.id}=…`: $title$advanced.$hint';
}

String _choiceLine(PresetOption option, String choice, OptionWords? words) {
  final label = words?.choices[choice]?.label ?? choice;
  final hint = words?.choices[choice]?.hint ?? '';
  final named = label.toLowerCase() == choice ? '' : ': $label';
  final standard = choice == option.defaultChoice ? ' (the default)' : '';
  return '  - `$choice`$named$standard.${hint.isEmpty ? '' : ' $hint'}';
}

// ---- Waiting and events ----------------------------------------------------

/// Each exit code: a few words, and in full.
const _exitCodes = [
  (
    ExitCode.ok,
    'done; for `wait`, every job done or skipped',
    'Done. For `wait`: every job ended done or skipped, those '
        'worth a look by eye included (flagged in the output).',
  ),
  (
    ExitCode.jobsFailed,
    'a job failed or was cancelled',
    'At least one job failed or was cancelled.',
  ),
  (
    ExitCode.notRunning,
    'no window, none could open (or `--no-start`), or it refused',
    'VidCtrl is not open and could not be opened (or '
        '`--no-start` was given), or it is open but refused the connection '
        'or did not answer.',
  ),
  (
    ExitCode.timeout,
    '`--timeout` passed; the jobs go on',
    '`--timeout` passed; the jobs go on in the window.',
  ),
  (
    ExitCode.appClosed,
    'the window closed meanwhile',
    'The window closed while waiting or following.',
  ),
  (
    ExitCode.badArguments,
    'bad arguments, or the client went wrong',
    'Bad arguments: an unknown command, goal, option, '
        'choice, video or job; or the client itself went wrong.',
  ),
  (
    ExitCode.ffmpegMissing,
    'no FFmpeg; the window says what to do',
    'VidCtrl could not find FFmpeg; the window says '
        'what to do.',
  ),
];

/// Each event: its fields, what it means, and both in a few words.
const _events = [
  (
    Events.snapshot,
    '`videos` (list of Video), `jobs` (list of Job), '
        '`paused` (bool), `busy` (bool)',
    'How everything stands; first, '
        'unless `--since-now`.',
    '`{videos: [Video], jobs: [Job], paused, busy}`, first',
  ),
  (Events.videoAdded, 'a Video', 'A video came into the list.', 'a Video'),
  (Events.videoReady, 'a Video', 'It has been read.', 'a Video'),
  (
    Events.videoUnreadable,
    'a Video',
    'It is not a video FFmpeg can open.',
    'a Video',
  ),
  (
    Events.videoRemoved,
    '`video` (int)',
    'It was taken off the list; its '
        'file stays on disk.',
    '`{video}`',
  ),
  (Events.jobAdded, 'a Job', 'A job came into the queue.', 'a Job'),
  (
    Events.jobChecking,
    '`job` (int), `attempt` (int)',
    'Choosing its '
        'quality: this try.',
    '`{job, attempt}`',
  ),
  (Events.jobStarted, 'a Job', 'Converting it begins.', 'a Job'),
  (
    Events.jobProgress,
    '`job` (int), `fraction` (number, 0 to 1), '
        '`remainingSeconds` (number, optional)',
    'How far it is; at most once '
        'a second for each job.',
    '`{job, fraction, remainingSeconds?}`',
  ),
  (
    Events.jobFinished,
    'a Job',
    'It ended: `DONE`, `SKIPPED`, `FAILED` or '
        '`CANCELLED`.',
    'a Job',
  ),
  (
    Events.jobRemoved,
    '`job` (int)',
    'It was taken out of the queue; any '
        'result stays on disk.',
    '`{job}`',
  ),
  (
    Events.queuePaused,
    'none',
    'The queue was paused, in the window or by '
        '`pause`.',
    '',
  ),
  (Events.queueResumed, 'none', 'It goes on again.', ''),
  (
    Events.queueIdle,
    'none',
    'The queue has nothing more to do.',
    'nothing more to do',
  ),
  (
    Events.compareFinished,
    '`job` (int), `status` (`MEASURED` or '
        '`FAILED`), `closeness`, `vmaf` (optional), `xpsnr`; or '
        '`errorLines`',
    '"Compare with the original" ended, in the window or by `compare`.',
    'as `compare` answers, or with `errorLines`',
  ),
  (
    Events.appClosing,
    'none',
    'The window is closing; `events` and `wait` '
        'exit 4.',
    'the window closes',
  ),
];

/// The rules `wait` keeps.
const _waitRules = [
  'The jobs it counts are those not yet ended when it starts, and any added '
      'or tried again while it waits, by this program or the person. Jobs '
      'that ended before it started do not count, so an old failure does '
      'not make every later `wait` exit 1.',
  'With nothing waiting when it starts, it exits 0 at once.',
  'A job taken out of the queue while it waits is told as `REMOVED`, not as '
      'a failure; one cancelled is a failure.',
  'A paused queue keeps it waiting, as the person may continue it; it says '
      'so once on stderr.',
];

String _waitingPart(String c) => [
  '## Waiting',
  '',
  '`$c wait [jobs…]` waits for those jobs, or until none waits, converts '
      'or is paused, maybe for hours: run it in the background. It counts '
      'jobs not ended when it starts and those added or retried meanwhile '
      '(an old failure does not count); with none, it exits 0 at once. A job '
      'taken out is `REMOVED`, not a failure; a cancelled one is. A paused '
      'queue keeps it waiting. Exit codes, of every command:',
  '',
  for (final (code, brief, _) in _exitCodes) '- $code: $brief',
  '',
].join('\n');

String _waitingInFull(String c) => [
  '#### Waiting',
  '',
  '- `$c wait` without ids waits until no job is waiting, converting or '
      'paused; with ids, until those have ended.',
  for (final rule in _waitRules) '- $rule',
  '- It may run for hours: run it in the background and tell the person '
      'when it returns.',
  '',
  '#### Exit codes',
  '',
  'The same for every command:',
  '',
  '| Code | Meaning |',
  '|---|---|',
  for (final (code, _, meaning) in _exitCodes) '| $code | $meaning |',
  '',
].join('\n');

String _eventsInFull(String c) => [
  '#### Events',
  '',
  '`$c events` tells these, each with `event`, its code, and, but on '
      '`APP_CLOSING`, `time`:',
  '',
  '| Event | Fields | Meaning |',
  '|---|---|---|',
  for (final (name, fields, meaning, _) in _events)
    '| `$name` | $fields | $meaning |',
  '',
].join('\n');

// ---- Recipes and limits ----------------------------------------------------

const _videoFind =
    "find ~/Videos -type f -size +2G \\( -iname '*.mov' -o -iname '*.mp4' "
    "-o -iname '*.mts' -o -iname '*.mkv' \\) \\\n  -not -path '*/Converted/*'";

String _recipes(String c) =>
    '''
## Recipes

Queue every video over 2 GB in ~/Videos and say when done (look at `find`'s list first; none: tell the person):

```sh
$_videoFind -print0 | xargs -0 $c queue add --goal archive --json
$c wait 0 1 2 --json   # in the background; the ids from each answer's `added`
```

Then tell the person each `outputPath` and `needsALook`, and on exit 1 each failed job's `errorLines` (`$c queue --json`).

Samples first, then the whole:

```sh
$c queue add ~/Videos/beach.mov --goal archive --sample middle --json
$c wait --json
$c compare 0 --json               # the sample's job id; tell the person
$c queue convert-whole 0 --json   # once they agree
```

More in the help of `queue add` (PowerShell too), `queue convert-whole`, `events`, `pause`, `estimate`.
''';

/// The recipes in each command's details, by command.
Map<String, String> _recipesOf(String c) => {
  'queue add':
      '''
#### Queue every video over 2 GB in ~/Videos, and tell me when it is done

Find them yourself, leaving out earlier results, and look at the list first:

```sh
$_videoFind
```

If it lists nothing, tell the person no video was found, and stop. Otherwise queue them with a goal:

```sh
$_videoFind -print0 | xargs -0 $c queue add --goal archive --json
```

For a long list `xargs` may run `queue add` more than once: each run prints one JSON answer on its own line. Take the job ids from every answer's `added` (`added[].id`); videos in `alreadyQueued` were in the queue already, and `$c queue --json` shows their jobs. Then wait for those jobs, in the background, as it can take hours:

```sh
$c wait 0 1 2 --json             # the job ids from `added`
```

On Windows, in PowerShell:

```powershell
\$files = Get-ChildItem "\$HOME\\Videos" -Recurse -File -Include *.mov,*.mp4,*.mts,*.mkv |
  Where-Object { \$_.Length -gt 2GB -and \$_.FullName -notmatch '\\\\Converted\\\\' }
\$files.Count                     # 0: tell the person no video was found, and stop
$c queue add --goal archive --json @(\$files.FullName)
$c wait 0 1 2 --json             # the job ids from `added`
```

`wait` returns when the last of those jobs has ended. Then tell the person each result (`outputPath`), and name every one with `needsALook` true: worth a look by eye. `$c queue --json` gives each job's size and quality too, and on exit 1 each failed job's `errorLines`: tell the person why it failed. Once the cause is put right, `$c queue retry <job>` tries a job again.
''',
  'events':
      '''
#### Report each file as it finishes

```sh
$c queue                          # opens the window first, if it is not open
$c events --since-now --json      # in the background
```

Read its lines as they come. On each `JOB_FINISHED`, tell the person about that job: its `status`, `outputPath`, `outputBytes`, `quality.outcome` and `needsALook`. On `QUEUE_IDLE` the queue has nothing more to do: stop following. On `APP_CLOSING` the window closed.
''',
  'queue convert-whole':
      '''
#### Make samples first, compare, then convert the whole

```sh
$c queue add ~/Videos/beach.mov ~/Videos/party.mov --goal archive --sample middle --json
$c wait --json
$c compare 0 --json               # each sample job's id from `added`
$c compare 1 --json
```

Each sample job's `outputPath` is a 10-second piece in `Converted/Samples/`. `compare` compares it with the same piece of its original and says how close it looks: `closeness`, with `vmaf` and `xpsnr`. Each comparison takes about as long as the piece lasts, or longer. `$c job <job> --json` gives the sample's `quality` too: the quality chosen for the whole video and `share`, its expected size as a share of the original's. Tell the person where the samples are and how close each looks, so they can look at them. Once they agree, convert each whole video with its sample's settings, by the sample jobs' ids:

```sh
$c queue convert-whole 0 --json
$c queue convert-whole 1 --json
$c wait --json
```

Each answer's `added` holds the new job. For other settings, queue the whole videos with `$c queue add` and the goal and options wanted.
''',
  'pause':
      '''
#### Hold the conversions for a while

When the person needs the computer for something else:

```sh
$c pause
$c resume                         # when the person says so
```

`pause` holds the job under way and starts nothing new; `resume` goes on where it was. To stop the job under way for good, `$c cancel` (it can be tried again with `$c queue retry <job>`); to take waiting jobs out of the queue, `$c queue remove <jobs…>`. The files stay as they are.
''',
  'estimate':
      '''
#### What would Archive do with these videos, and how big would they be?

```sh
$c add ~/Videos/trip --json
$c estimate 0 1 2 --goal archive --json      # the ids from `add`
```

`estimate` measures each video in turn and answers once all are measured; that takes seconds to a minute or so for each. Each video's `preview` gives the `plan`, the `expectedBytes` (`measured` when measured by encoding pieces) and the `closeness`; beside its `sizeBytes`, that is how much smaller it would come out. A preview with no `expectedBytes` could not be measured. While the queue converts, `estimate` is refused (`BUSY`): measure before queuing, or once `$c wait` has returned. Later, `$c videos --goal archive --json` gives the same again.
''',
};

String _limits(String c) =>
    '''
## Limits

- It runs as the person logged in, on the window's computer and desktop: not over SSH, from WSL or a container. A sandboxed agent must run `$c` outside its sandbox (loopback network, the person's folders, the desktop).
- It takes no FFmpeg settings or quality numbers (so Archive keeps its promise) and speaks English whatever the window's language.
''';
