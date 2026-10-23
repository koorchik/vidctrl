import '../quality/quality_meter.dart' show Closeness;
import '../quality/quality_search.dart' show QualityOutcome;
import '../scenarios/registry.dart';
import '../scenarios/scenario.dart';
import 'manual_commands.dart';
import 'manual_words.g.dart';
import 'protocol.dart';
import 'words.dart';

// The manual of vidctrl-client, for an agent that has never seen the window:
// `manual` prints it, `help <command>` one command's part, and
// docs/CLIENT.md is a copy written by tool/make_manual.dart. Each command
// has one `CommandDoc` in `commandDocs` (manual_commands.dart); a new
// command adds its own. The goals come from the registry, their words from
// the English texts (manual_words.g.dart). Nothing here speaks of deleting a file (see
// `speaksOfDeleting`).

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

/// [client] as it is typed in a shell: a plain name as it is, a path in
/// quotes.
String shellWord(String client) =>
    RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(client) ? client : '"$client"';

/// What an agent needs before anything else, with [client] as the command
/// that runs this program: the manual's first section, what the client
/// prints with no arguments, and the prompt the window gives to copy.
String quickStart(String client) {
  final c = shellWord(client);
  return '''
VidCtrl is open on this computer, and the person watches its window. The program `$c` controls it: it adds videos to the window's list and queues conversions there.

- Run `$c manual` first: it explains every command, the goals and what the results mean. Add `--json` to a command to read its answer as JSON.
- Finding the videos is your job (with `find`, `du` or the like). Give their paths to `$c add`, or straight to `$c queue add --goal <goal>`.
- The window converts one video at a time, and that can take hours. To know when it ends, run `$c wait` in the background (or follow `$c events`), and tell the person when it returns: each result, and any marked "worth a look by eye".
- $filesRule "Remove" only takes a video off the list or a job out of the queue.
''';
}

/// The short list `--help` prints.
String usage({String client = 'vidctrl-client'}) {
  final c = shellWord(client);
  final docs = commandDocs(c);
  final width = docs
      .map((d) => _synopsis(d).length)
      .reduce((a, b) => a > b ? a : b);
  return [
    '$c adds videos to the open VidCtrl window and follows its queue.',
    '',
    'Usage: $c <command> [arguments] [options]',
    '',
    for (final area in CommandArea.values)
      if (docs.any((d) => d.area == area)) ...[
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

/// One command's part of the manual, with the shapes its JSON answer is
/// made of. [command] is one of `clientCommands`.
String commandHelp(String command, {String client = 'vidctrl-client'}) {
  final c = shellWord(client);
  final doc = commandDocs(c).where((d) => d.name == command).firstOrNull;
  if (doc == null) throw ArgumentError.value(command, 'command');
  final text = [
    _commandSection(c, doc),
    for (final shape in _shapes.keys)
      if (doc.shapes.contains(shape)) _shapeSection(shape),
  ].join('\n');
  return '${text.trimRight()}\n';
}

/// The whole manual, in Markdown.
String manual({
  required String client,
  Map<String, GoalWords> words = manualGoalWords,
}) {
  final c = shellWord(client);
  return [
    '# vidctrl-client',
    '',
    '`vidctrl-client` controls the open VidCtrl window from a terminal, a '
        'script or an AI agent. `$c manual` prints this guide; '
        '`$c help <command>` prints one command\'s part.',
    '',
    '## Quick start',
    '',
    quickStart(client),
    _about(c),
    _never(c),
    _commandsPart(c, words),
    _goalsPart(words),
    _resultsPart(),
    _waitingPart(c),
    _recipes(c),
    _limits(c),
  ].join('\n');
}

/// The manual as data, for a program that builds on it.
Map<String, Object?> manualJson({
  Map<String, GoalWords> words = manualGoalWords,
}) => {
  'commands': [
    for (final doc in commandDocs('vidctrl-client'))
      {
        'name': doc.name,
        'arguments': doc.arguments,
        'description': doc.summary,
        'options': [
          for (final (flag, text) in doc.options)
            {'name': flag, 'description': text},
        ],
      },
  ],
  'goals': [
    for (final scenario in scenarios)
      for (final preset in scenario.presets)
        goalJson(scenario, preset, words[preset.id]),
  ],
  'exitCodes': {for (final (code, meaning) in _exitCodes) '$code': meaning},
  'events': [
    for (final (name, fields, meaning) in _events)
      {'name': name, 'fields': fields, 'description': meaning},
  ],
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

VidCtrl converts videos by goal: "Archive" makes camera videos far smaller while they look the same, "Save space" smaller still, "Edit in DaVinci Resolve" makes them open there, and so on. It is a window on this computer; `$c` is a client of that window. It changes what the window shows, exactly as if the person had done it with the mouse.

- **Videos.** The window keeps a list of videos. Adding one (`$c add`) is like dropping it on the window: VidCtrl reads it to learn its size, length, picture and sound. Each file is in the list once. Videos just added become the window's selection, as dropped ones do.
- **Goals.** What to make of a video, each with a few options (see "Goals"). They are the goals and options of the window's panel, by id; nothing finer, such as FFmpeg settings or quality numbers, can be given.
- **The queue and its jobs.** Queuing a video with a goal (`$c queue add`) makes a job. A job is a snapshot: it keeps the video's details, the goal, its options and the output folder as they were when it was queued, so later changes to the list or the panel do not touch it; taking its video off the list leaves it in the queue. The queue starts by itself and converts one job at a time, in order.
- **The window shows everything.** Every video and job this program adds appears in the window. The person may act there too (pause the queue, add videos, take jobs out), and this program sees it.
- **Nothing converts without the window.** This program never converts anything itself. When no window is open, every command but `status`, `manual` and `help` opens one first ("Starting VidCtrl…" on stderr; it can take up to 30 seconds). Closing the window stops its conversions.
- **The originals stay as they are.** A result is a new file, by default in a folder named `Converted` beside its video. Its name carries the settings: `beach.mov` becomes `Converted/beach_av1-crf35.mp4`, and a second result with the same name gets ` (2)`. A result is written under a hidden name ending in `.part` and gets its own name only once complete, so a file with a result's name is always whole.
- **Samples.** A sample job converts 10 seconds of a video, from its start or its middle, with the same settings as the whole would get, into a `Samples` folder inside the output folder: `Converted/Samples/beach_av1-crf35_sample10s.mp4` (`_sample10s-mid` from the middle).
- **Ids.** Videos and jobs are numbered from 0, each in the order they were added. The numbers, the list and the queue last while the window is open; a new window starts again from 0, with an empty list and queue.
''';

String _never(String c) =>
    '''
## What VidCtrl never does

$neverDeletes

- Results are new files. No command changes, moves or renames a file that is there, original or result. "Remove", here as in the window, takes a video off the list (`$c remove`) or a job out of the queue; every file stays where it is.
- No command overrules the person: none closes the window, changes the goal shown in its panel, its remembered settings, its look or its language.
- $filesRule Leave every file to the person.
''';

// ---- Commands ------------------------------------------------------------

String _synopsis(CommandDoc doc) =>
    [doc.name, if (doc.arguments.isNotEmpty) doc.arguments].join(' ');

String _commandsPart(String c, Map<String, GoalWords> words) => [
  '## Commands',
  '',
  'How every command works:',
  '',
  '- `$c <command> [arguments] [options]`; options may come before or '
      'after the arguments.',
  '- `--json` prints the answer as one JSON document on stdout (`events`: '
      'one per line). Without it, lines for people. The JSON has ids and '
      'numbers, and English words beside the ids in fields ending in '
      '`Text`. A value that is not known is left out, never `null`; only '
      '`cancel` answers `null`, when nothing was cancelled.',
  '- `--no-start`: do not open the window when it is not open; exit 2 '
      'instead.',
  '- `--help` prints the command\'s part of this guide.',
  '- Videos are given by id or by path, jobs by id. A reference made only '
      'of digits is an id: a file named `3` in the current folder is given '
      'as `./3`.',
  '- Paths may be relative or start with `~`: the client makes them '
      'absolute from the current folder before sending them.',
  '- A goal is given by its id (`--goal archive`), its options with '
      '`--opt option=choice`, once for each (`--opt codec=hevc --opt '
      'speed=gpu`). An unknown goal, option or choice is refused with the '
      'valid ones named. So is an option this computer does not offer '
      '(`$c goals` lists those it does), unless its choice is the one the '
      'goal makes here anyway: `--opt speed=cpu` where the graphics card '
      'cannot encode, `--opt codec=hevc` where FFmpeg cannot make AV1. A '
      'script may name the defaults on every computer.',
  '- Errors go to stderr, as a line for people, or with `--json` as '
      '`{"error": {"kind": "...", "message": "..."}}`; the exit code tells '
      'what kind (see "Exit codes"). The kinds:',
  for (final (kind, meaning) in _errorKinds) '  - `$kind`: $meaning',
  '- Start the window before running commands side by side: two commands '
      'started at the same moment with no window open can each open one. '
      'Any command but `status` opens it, for example `$c queue`; then run '
      '`$c events` in the background beside the others.',
  '',
  for (final doc in commandDocs(c, words)) _commandSection(c, doc),
  '### What `--json` gives',
  '',
  'The shapes the answers and events are made of. Each field is named with '
      'its JSON type; one marked "optional" is left out when not known.',
  '',
  for (final shape in _shapes.keys) _shapeSection(shape),
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

const _errorKinds = [
  (
    'badArgument',
    'a command, goal, option, choice or value that is not '
        'valid (exit 5).',
  ),
  ('notFound', 'no such video or job (exit 5).'),
  ('busy', 'the window cannot do that right now (exit 5).'),
  (
    'unknownMethod',
    'the open window is of another version and does not '
        'know the request (exit 5).',
  ),
  (
    'ffmpegMissing',
    'the window could not find FFmpeg and shows what to do '
        '(exit 6).',
  ),
  ('unauthorized', 'the window refused the connection (exit 2).'),
  ('notRunning', 'the window is not open and could not be opened (exit 2).'),
  ('appClosed', 'the window closed meanwhile (exit 4).'),
  ('timeout', '`--timeout` passed; the jobs go on in the window (exit 3).'),
  (
    'unexpected',
    'the client itself went wrong; the message says how '
        '(exit 5).',
  ),
];

// ---- Shapes ----------------------------------------------------------------

String _shapeSection(String name) => '#### $name\n\n${_shapes[name]}';

/// The shapes, each in Markdown: what it is, then each field with its JSON
/// type.
const _shapes = {
  'Status': '''
How the window stands.

- `state` (string): `starting`, `ready` or `ffmpegMissing`.
- `version` (string): VidCtrl's version; empty in a development build.
- `busy` (bool): the queue is working through jobs.
- `paused` (bool): the queue is paused in the window.
- `jobs` (object): how many jobs there are in each status, as `{"waiting": 2, "done": 1}`.
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
- `status` (string): `probing` (being read), `ready` or `unreadable`; `statusText` (string) in words.
- `sizeBytes` (int, optional).
- `durationSeconds` (number, optional).
- `width` (int, optional), `height` (int, optional): the picture.
- `videoCodec` (string, optional): the picture's format, as `hevc`.
- `audioCodecs` (list of string): one per sound track.
- `hdr` (bool).
- `preview` (Preview, optional): with `videos --goal`.
''',
  'Preview': '''
What a goal would do to a video, as the list shows it.

- `goal` (string): the goal's full id.
- `plan` (string): what it would do, see "Plans"; `planText` (string) in words.
- `expectedBytes` (int, optional): the result's expected size.
- `measured` (bool): the size was measured by encoding pieces, not calculated.
- `measuring` (bool): the window is measuring it now.
- `closeness` (string, optional): how close the result would look, see "Closeness"; `closenessText` (string) in words.
''',
  'Job': '''
A job in the queue.

- `id` (int).
- `videoId` (int): the video it was made from, which may be off the list by now.
- `path` (string): that video's file.
- `goal` (string): the goal's full id.
- `options` (object): every option of the goal and the choice it really makes on this computer: `codec` is `hevc` where FFmpeg cannot make AV1, `speed` is `cpu` where the graphics card cannot encode. Tell the person these, not what was asked.
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
''',
  'Quality': '''
How a job's quality was chosen: Archive measures each video before converting it and compares pieces of the result with the original.

- `outcome` (string): see "Quality outcomes"; `outcomeText` (string) in words.
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
- `status` (string): `done`, `skipped`, `failed`, `cancelled` or `removed`; `statusText` (string) in words.
- `outputPath` (string, optional): the result, when done.
- `needsALook` (bool): worth a look by eye, see `belowTarget`.
''',
};

// ---- Goals -----------------------------------------------------------------

/// What a goal leaves as it is, by its kind's id.
const _leaves = {
  'archive':
      'Every video is converted, its quality chosen by measuring (see '
      '"Quality outcomes"). One whose result would keep over 80% of the '
      'original\'s size is kept as it is: its job ends `skipped` with the '
      'outcome `notWorthIt`. A sample is made all the same.',
  'space': 'Every video with a picture is converted.',
  'resolve':
      'A video Resolve already opens is left as it is (plan `skip`); often '
      'only the sound needs converting (`audioOnly`).',
  'audio':
      'Takes the first sound track; a video without sound is `unsupported`. '
      'Sound that fits the file type is copied as it is.',
  'privacy':
      'Each result is a new copy without the hidden notes; the original '
      'stays as it is. `quick` copies picture and sound as they are '
      '(`remux`), `thorough` converts them again (`encode`). Sound files are '
      'taken too.',
  'remux':
      'A video already of that file type is left as it is (`skip`); sound '
      'the new type cannot hold is converted (`audioOnly`); the picture '
      'never is.',
};

String _goalsPart(Map<String, GoalWords> words) {
  final lines = [
    '## Goals',
    '',
    'Each goal, by the name `--goal` takes, with its options and their '
        'choices. The full id (as `archive.master`) is taken too. An option '
        'is offered only where it makes a difference on this computer: '
        '`vidctrl-client goals` shows which are here; another is taken only '
        'with the choice the goal makes here anyway. A file with no picture '
        'is `unsupported` by every goal but "Get the sound" and "Remove '
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
        '### $title: `--goal $name`',
        '',
        if (name != preset.id) 'Full id: `${preset.id}`.',
        if (name != preset.id) '',
        if (goal != null && goal.hint.isNotEmpty) ...[goal.hint, ''],
        if (_leaves[scenario.id] case final leaves?) ...[leaves, ''],
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

// ---- What the results mean -----------------------------------------------

/// Job statuses, and what to make of each.
const _jobStatuses = [
  ('waiting', 'In the queue, its turn not come yet.'),
  ('running', 'Being converted now, or its quality being chosen (`attempt`).'),
  ('paused', 'Under way, held because the queue is paused in the window.'),
  (
    'done',
    'The result is at `outputPath`. Tell the person, and say so when '
        '`needsALook` is true.',
  ),
  (
    'skipped',
    'Nothing was written: the video already met the goal, the goal can do '
        'nothing with it (plan `unsupported`), or converting would hardly '
        'make it smaller (outcome `notWorthIt`). Counts as finished, not as '
        'a failure.',
  ),
  (
    'failed',
    'It could not be converted; `errorLines` says why. The person '
        'can try it again in the window, as `queue retry <job>` does.',
  ),
  (
    'cancelled',
    'Stopped before it was done, in the window or by `cancel`. `wait` '
        'counts it as a failure; `queue retry <job>` tries it again.',
  ),
  (
    'removed',
    'Only in `wait`, for a job taken out of the queue while it waited. Not '
        'a failure.',
  ),
];

const _videoStatuses = [
  ('probing', 'Being read.'),
  ('ready', 'Read; it can be queued.'),
  ('unreadable', 'Not a video FFmpeg can open; it cannot be queued.'),
];

const _planNotes = {
  'skip': 'Queued, the job ends `skipped` and writes no file.',
  'remux': 'Quick: the picture and sound are copied.',
  'audioOnly': 'Quick: the picture is copied.',
  'encode': 'The picture is converted: this takes time.',
  'unsupported':
      'For example, a goal for pictures given a sound file. Queued, the job '
      'ends `skipped`.',
  'keptAsIs': 'Archive only; the job ends `skipped`.',
};

const _closenessNotes = {
  'same': 'VMAF 95 or more on the poorest piece.',
  'veryClose': 'VMAF 93 or more.',
  'differs': 'Below that: worth a look.',
};

const _outcomeNotes = {
  'standard': 'The goal\'s usual quality was enough to look the same.',
  'raised':
      'A better quality than usual was needed, and the file is larger '
      'for it.',
  'belowTarget':
      'Converted anyway, and the result\'s name ends in `-check`. '
      'Tell the person to look at it by eye beside the original. The job is '
      '`done` and `needsALook` is true; `wait` still exits 0.',
  'notWorthIt':
      'The job ends `skipped` and nothing is written. In the '
      'window, "Convert anyway" in the job\'s ⋯ menu converts it all the '
      'same, as `queue convert-anyway <job>` does.',
};

String _resultsPart() => [
  '## What the results mean',
  '',
  'Each id and its words (the `...Text` fields in JSON), then what to make '
      'of it.',
  '',
  '### Job statuses',
  '',
  for (final (id, note) in _jobStatuses) '- `$id`: ${statusWords(id)}. $note',
  '',
  '### Video statuses',
  '',
  for (final (id, note) in _videoStatuses) '- `$id`: $note',
  '',
  '### Plans',
  '',
  'What a goal would do to a video (Preview `plan`):',
  '',
  for (final id in [...PlanKind.values.map((k) => k.name), 'keptAsIs'])
    '- `$id`: ${planWords(id)}.${_note(_planNotes[id])}',
  '',
  '### Closeness',
  '',
  'How close a result looks to its original (Preview `closeness`):',
  '',
  for (final id in Closeness.values.map((c) => c.name))
    '- `$id`: ${closenessWords(id)}.${_note(_closenessNotes[id])}',
  '',
  '### Quality outcomes',
  '',
  'How a job\'s quality was chosen (Quality `outcome`):',
  '',
  for (final id in QualityOutcome.values.map((o) => o.name))
    '- `$id`: ${outcomeWords(id)}.${_note(_outcomeNotes[id])}',
  '',
].join('\n');

String _note(String? note) => note == null ? '' : ' $note';

// ---- Waiting and events ----------------------------------------------------

const _exitCodes = [
  (
    ExitCode.ok,
    'Done. For `wait`: every job ended done or skipped, those '
        'worth a look by eye included (flagged in the output).',
  ),
  (ExitCode.jobsFailed, 'At least one job failed or was cancelled.'),
  (
    ExitCode.notRunning,
    'VidCtrl is not open and could not be opened (or '
        '`--no-start` was given), or it refused the connection.',
  ),
  (ExitCode.timeout, '`--timeout` passed; the jobs go on in the window.'),
  (ExitCode.appClosed, 'The window closed while waiting or following.'),
  (
    ExitCode.badArguments,
    'Bad arguments: an unknown command, goal, option, '
        'choice, video or job; or the client itself went wrong.',
  ),
  (
    ExitCode.ffmpegMissing,
    'VidCtrl could not find FFmpeg; the window says '
        'what to do.',
  ),
];

/// Each event, its fields and what it means.
const _events = [
  (
    Events.snapshot,
    '`videos` (list of Video), `jobs` (list of Job), '
        '`paused` (bool), `busy` (bool)',
    'How everything stands; first, '
        'unless `--since-now`.',
  ),
  (Events.videoAdded, 'a Video', 'A video came into the list.'),
  (Events.videoReady, 'a Video', 'It has been read.'),
  (Events.videoUnreadable, 'a Video', 'It is not a video FFmpeg can open.'),
  (
    Events.videoRemoved,
    '`video` (int)',
    'It was taken off the list; its '
        'file stays on disk.',
  ),
  (Events.jobAdded, 'a Job', 'A job came into the queue.'),
  (
    Events.jobChecking,
    '`job` (int), `attempt` (int)',
    'Choosing its '
        'quality: this try.',
  ),
  (Events.jobStarted, 'a Job', 'Converting it begins.'),
  (
    Events.jobProgress,
    '`job` (int), `fraction` (number, 0 to 1), '
        '`remainingSeconds` (number, optional)',
    'How far it is; at most once '
        'a second for each job.',
  ),
  (
    Events.jobFinished,
    'a Job',
    'It ended: `done`, `skipped`, `failed` or '
        '`cancelled`.',
  ),
  (
    Events.jobRemoved,
    '`job` (int)',
    'It was taken out of the queue; any '
        'result stays on disk.',
  ),
  (
    Events.queuePaused,
    'none',
    'The queue was paused, in the window or by '
        '`pause`.',
  ),
  (Events.queueResumed, 'none', 'It goes on again.'),
  (Events.queueIdle, 'none', 'The queue has nothing more to do.'),
  (
    Events.compareFinished,
    '`job` (int), `status` (`measured` or '
        '`failed`), `closeness`, `closenessText`, `vmaf` (optional), `xpsnr`; '
        'or `errorLines`',
    '"Compare with the original" in the window ended.',
  ),
  (
    Events.appClosing,
    'none',
    'The window is closing; `events` and `wait` '
        'exit 4.',
  ),
];

String _waitingPart(String c) => [
  '## Waiting and events',
  '',
  '### Waiting',
  '',
  '- `$c wait` without ids waits until no job is waiting, converting or '
      'paused; with ids, until those have ended.',
  '- The jobs it counts are those not yet ended when it starts, and any '
      'added or tried again while it waits, by this program or the person. '
      'Jobs that ended before it started do not count, so an old failure '
      'does not make every later `wait` exit 1.',
  '- With nothing waiting when it starts, it exits 0 at once.',
  '- A job taken out of the queue while it waits is told as `removed`, '
      'not as a failure; one cancelled is a failure.',
  '- A paused queue keeps it waiting, as the person may continue it; it '
      'says so once on stderr.',
  '- It may run for hours: run it in the background and tell the person '
      'when it returns.',
  '',
  '### Exit codes',
  '',
  'The same for every command:',
  '',
  '| Code | Meaning |',
  '|---|---|',
  for (final (code, meaning) in _exitCodes) '| $code | $meaning |',
  '',
  '### Events',
  '',
  '`$c events` tells these, each with `event` and, but on `app-closing`, '
      '`time`:',
  '',
  '| Event | Fields | Meaning |',
  '|---|---|---|',
  for (final (name, fields, meaning) in _events)
    '| `$name` | $fields | $meaning |',
  '',
].join('\n');

// ---- Recipes and limits ----------------------------------------------------

String _recipes(String c) =>
    '''
## Recipes

### Queue every video over 2 GB in ~/Videos, and tell me when it is done

Find them yourself, leaving out earlier results, and look at the list first:

```sh
find ~/Videos -type f -size +2G \\( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.mts' -o -iname '*.mkv' \\) \\
  -not -path '*/Converted/*'
```

If it lists nothing, tell the person no video was found, and stop. Otherwise queue them with a goal:

```sh
find ~/Videos -type f -size +2G \\( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.mts' -o -iname '*.mkv' \\) \\
  -not -path '*/Converted/*' -print0 | xargs -0 $c queue add --goal archive --json
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

### Report each file as it finishes

```sh
$c queue                          # opens the window first, if it is not open
$c events --since-now --json      # in the background
```

Read its lines as they come. On each `job-finished`, tell the person about that job: its `status`, `outputPath`, `outputBytes`, `quality.outcome` and `needsALook`. On `queue-idle` the queue has nothing more to do: stop following. On `app-closing` the window closed.

### Make samples first, then convert the whole

```sh
$c queue add ~/Videos/beach.mov ~/Videos/party.mov --goal archive --sample middle --json
$c wait --json
$c queue --json
```

Each sample job's `outputPath` is a 10-second piece in `Converted/Samples/`; its `quality` tells how the whole video will come out: `vmaf` and `xpsnr` of the poorest piece, and `share`, the expected size as a share of the original's. Tell the person where the samples are, so they can look at them. Once they agree, convert each whole video with its sample's settings, by the sample jobs' ids from `added`:

```sh
$c queue convert-whole 0 --json
$c queue convert-whole 1 --json
$c wait --json
```

Each answer's `added` holds the new job. For other settings, queue the whole videos with `$c queue add` and the goal and options wanted.

### Hold the conversions for a while

When the person needs the computer for something else:

```sh
$c pause
$c resume                         # when the person says so
```

`pause` holds the job under way and starts nothing new; `resume` goes on where it was. To stop the job under way for good, `$c cancel` (it can be tried again with `$c queue retry <job>`); to take waiting jobs out of the queue, `$c queue remove <jobs…>`. The files stay as they are.

### What would Archive do with these videos, and how big would they be?

```sh
$c add ~/Videos/trip --json
$c videos --goal archive --json
```

Each video's `preview` gives the `plan` (`planText` in words), the `expectedBytes` once known (`measured` when measured by encoding pieces) and the `closeness`. While `measuring` is true, ask again a little later. The window measures sizes with the goal its panel shows; for another goal, queue a sample of a video or two (as above): with Archive, its `quality.share` is the expected size as a share of the original's.
''';

String _limits(String c) =>
    '''
## Limits

- It runs as the person logged in, on the same computer and desktop as the window: not over SSH, not from WSL on Windows or a container. A sandboxed agent must run `$c` outside its sandbox: it needs the loopback network, the person's own folders and, to open the window, the desktop.
- No FFmpeg settings and no quality numbers: only the goals and options listed here. That is what keeps their promises (Archive looks the same).
- It does not look for files: find them yourself and pass their paths.
- It cannot close the window, change the goal shown in its panel, its remembered settings, its look or its language.
- The window converts one job at a time. The list, the queue and their ids last while the window is open.
- Its words are English, whatever language the window shows.
''';
