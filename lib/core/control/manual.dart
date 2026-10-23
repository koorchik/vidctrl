import 'dart:convert';

import '../media/video_files.dart' show videoExtensions;
import '../quality/quality_meter.dart' show Closeness;
import '../quality/quality_search.dart' show QualityOutcome;
import '../scenarios/registry.dart';
import '../scenarios/scenario.dart';
import 'client_text.dart';
import 'manual_words.g.dart';
import 'protocol.dart';
import 'views.dart';
import 'words.dart';

// The manual of vidctrl-client, for an agent that has never seen the window:
// `manual` prints it, `help <command>` one command's part, and
// docs/CLIENT.md is a copy written by tool/make_manual.dart. Each command
// has one `_CommandDoc` in `_commands`; a new command adds its own. The
// goals come from the registry, their words from the English texts
// (manual_words.g.dart). Nothing here speaks of deleting a file (see
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
  final docs = _commands(c);
  final width = docs
      .map((d) => _synopsis(d).length)
      .reduce((a, b) => a > b ? a : b);
  return [
    '$c adds videos to the open VidCtrl window and follows its queue.',
    '',
    'Usage: $c <command> [arguments] [options]',
    '',
    for (final doc in docs)
      '  ${_synopsis(doc).padRight(width)}  ${doc.summary}',
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
  final doc = _commands(c).where((d) => d.name == command).firstOrNull;
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
    for (final doc in _commands('vidctrl-client'))
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
        _goalJson(scenario, preset, words[preset.id]),
  ],
  'exitCodes': {for (final (code, meaning) in _exitCodes) '$code': meaning},
  'events': [
    for (final (name, fields, meaning) in _events)
      {'name': name, 'fields': fields, 'description': meaning},
  ],
};

Map<String, Object?> _goalJson(
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

/// One command's part of the manual.
class _CommandDoc {
  const _CommandDoc(
    this.name, {
    this.arguments = '',
    required this.summary,
    required this.about,
    this.options = const [],
    required this.examples,
    required this.text,
    required this.json,
    this.shapes = const [],
    this.errors = const [],
  });

  /// As typed: `queue add`.
  final String name;

  /// What comes after the name, options left out: `<videos…>`.
  final String arguments;

  /// One line, for `--help`.
  final String summary;

  /// Paragraphs in Markdown.
  final List<String> about;

  /// Each option and what it does, `--json` and the other global ones left
  /// out.
  final List<(String, String)> options;

  /// Command lines, with the command's name.
  final List<String> examples;

  /// What it prints for people: lines as they come out.
  final List<String> text;

  /// What `--json` gives, in Markdown.
  final List<String> json;

  /// The names of the shapes in [json], as in [_shapes].
  final List<String> shapes;

  /// How it can fail, besides the failures every command shares.
  final List<String> errors;
}

String _synopsis(_CommandDoc doc) =>
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
      '`cancel` answers `null`, when no job was converting.',
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
  for (final doc in _commands(c, words)) _commandSection(c, doc),
  '### What `--json` gives',
  '',
  'The shapes the answers and events are made of. Each field is named with '
      'its JSON type; one marked "optional" is left out when not known.',
  '',
  for (final shape in _shapes.keys) _shapeSection(shape),
].join('\n');

String _commandSection(String c, _CommandDoc doc) => [
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

// Samples for what the commands print, in the client's own words.

const _folder = '/home/alice/Videos';

const _preview = GoalPreview(
  goal: 'archive.master',
  plan: 'encode',
  expectedBytes: 610000000,
  measured: true,
  measuring: false,
  closeness: 'same',
);

const _video = VideoView(
  id: 0,
  path: '$_folder/beach.mov',
  status: 'ready',
  sizeBytes: 4200000000,
  durationSeconds: 754.2,
  width: 3840,
  height: 2160,
  videoCodec: 'hevc',
  audioCodecs: ['aac'],
  hdr: false,
);

const _options = {'codec': 'av1', 'speed': 'cpu'};

const _doneJob = JobView(
  id: 0,
  videoId: 0,
  path: '$_folder/beach.mov',
  goal: 'archive.master',
  options: _options,
  status: 'done',
  outputPath: '$_folder/Converted/beach_av1-crf35.mp4',
  outputBytes: 598000000,
  quality: QualityView(
    outcome: 'standard',
    value: 35,
    standardValue: 35,
    vmaf: 96.4,
    xpsnr: 43.1,
    share: .14,
  ),
  needsALook: false,
  errorLines: [],
);

const _runningJob = JobView(
  id: 1,
  videoId: 1,
  path: '$_folder/party.mov',
  goal: 'archive.master',
  options: _options,
  status: 'running',
  fraction: .42,
  remainingSeconds: 1260,
  outputPath: '$_folder/Converted/party_av1-crf20-check.mp4',
  quality: QualityView(
    outcome: 'belowTarget',
    value: 20,
    standardValue: 35,
    vmaf: 93.8,
    xpsnr: 40.2,
    share: .52,
  ),
  needsALook: true,
  errorLines: [],
);

const _checkedJob = JobView(
  id: 1,
  videoId: 1,
  path: '$_folder/party.mov',
  goal: 'archive.master',
  options: _options,
  status: 'done',
  outputPath: '$_folder/Converted/party_av1-crf20-check.mp4',
  outputBytes: 2100000000,
  quality: QualityView(
    outcome: 'belowTarget',
    value: 20,
    standardValue: 35,
    vmaf: 93.8,
    xpsnr: 40.2,
    share: .52,
  ),
  needsALook: true,
  errorLines: [],
);

const _waitingJob = JobView(
  id: 2,
  videoId: 2,
  path: '$_folder/dog.mp4',
  goal: 'archive.master',
  options: _options,
  status: 'waiting',
  needsALook: false,
  errorLines: [],
);

const _status = StatusView(
  state: 'ready',
  version: '1.2.0',
  busy: true,
  paused: false,
  jobs: {'done': 1, 'running': 1, 'waiting': 1},
);

final _addAnswer = {
  'videos': [
    {'path': '$_folder/beach.mov', 'id': 0, 'result': 'added'},
    {'path': '$_folder/party.mov', 'id': 1, 'result': 'known'},
    {'path': '$_folder/notes.mov', 'id': 3, 'result': 'unreadable'},
    {'path': '$_folder/missing.mov', 'result': 'notFound'},
  ],
};

final _queueAddAnswer = {
  'goal': 'archive.master',
  'options': _options,
  'added': [_waitingJob.toJson()],
  'alreadyQueued': [0],
  'skipped': [
    {'video': 3, 'reason': 'unreadable'},
  ],
};

/// A job made from job 3, a sample of trip.mov or that video kept as it is.
const _anotherJob = JobView(
  id: 4,
  videoId: 3,
  path: '$_folder/trip.mov',
  goal: 'archive.master',
  options: _options,
  status: 'waiting',
  needsALook: false,
  errorLines: [],
);

final _againAnswer = {
  'added': [_anotherJob.toJson()],
  'alreadyQueued': false,
};

final _waitAnswer = {
  'outcomes': [
    const JobOutcome(
      jobId: 0,
      path: '$_folder/beach.mov',
      status: 'done',
      outputPath: '$_folder/Converted/beach_av1-crf35.mp4',
      needsALook: false,
    ).toJson(),
    const JobOutcome(
      jobId: 1,
      path: '$_folder/party.mov',
      status: 'done',
      outputPath: '$_folder/Converted/party_av1-crf20-check.mp4',
      needsALook: true,
    ).toJson(),
  ],
};

List<String> _jsonBlock(Object? value) => ['```json', jsonEncode(value), '```'];

List<_CommandDoc> _commands(
  String c, [
  Map<String, GoalWords> words = manualGoalWords,
]) => [
  _CommandDoc(
    'status',
    summary: 'whether VidCtrl is open, and how its queue stands',
    about: [
      'It never opens the window. A window that has just opened is '
          '`starting` while it looks for FFmpeg, then `ready`, or '
          '`ffmpegMissing` when it found none.',
    ],
    examples: ['$c status', '$c status --json'],
    text: [
      ...statusText(_status),
      '',
      '# When the window is not open:',
      'VidCtrl is not running.',
    ],
    json: [
      '`{"running": false}` when the window is not open; otherwise '
          '`running` (bool, true) and a Status.',
      ..._jsonBlock({'running': true, ..._status.toJson()}),
    ],
    shapes: ['Status'],
  ),
  _CommandDoc(
    'goals',
    summary: 'the goals and their options, as this computer offers them',
    about: [
      'The same goals as "Goals" below, with only the options this computer '
          'can use: the speed of Archive, for one, is offered only where the '
          'graphics card can encode. An option left out here is refused by '
          '`queue add`, but for the choice the goal makes here anyway.',
    ],
    examples: ['$c goals', '$c goals --json'],
    text: goalsText([_goalView(_firstGoal, words)]),
    json: ['`goals` (list of Goal), in the order of the panel.'],
    shapes: ['Goal'],
  ),
  _CommandDoc(
    'add',
    arguments: '<paths…>',
    summary: 'adds videos to the list, as dropping them on the window does',
    about: [
      'A folder adds the videos in it and in its folders, by their '
          'extension (${videoExtensions.join(', ')}), leaving out hidden '
          'folders. Results in its `Converted` and `Samples` folders count '
          'as videos too, so give the files rather than a folder that holds '
          'results. A file is tried whatever its extension. A video '
          'already in the list is reported with its id and not added twice. '
          'It waits until each video has been read.',
    ],
    options: [
      ('--no-wait', 'answer at once, while the videos are still being read.'),
    ],
    examples: ['$c add ~/Videos/beach.mov ~/Videos/trip', '$c add . --json'],
    text: [for (final entry in _addAnswer['videos']!) addedText(entry)],
    json: [
      '`videos` (list): for each video found, and each path where nothing '
          'was, `path` (string), `id` (int, optional: absent when nothing was '
          'found) and `result` (string): `added`, `known` (in the list '
          'already), `unreadable` (in the list, but not a video FFmpeg can '
          'open) or `notFound`.',
      ..._jsonBlock(_addAnswer),
    ],
    errors: ['Nothing at all found at the paths given: exit 5.'],
  ),
  _CommandDoc(
    'videos',
    summary: 'the videos in the list, and what a goal would do to each',
    about: [
      'With `--goal` (and `--opt`), each video that could be read says what '
          'that goal would do to it, how large the result would be and how '
          'close it would look, where known. A size is known at once where '
          'the goal copies; a converted one is measured by encoding a few '
          'short pieces. The window measures the videos selected in its '
          'panel, with the goal the panel shows, while the queue is idle; '
          'videos just added are selected. `measuring` is true while it '
          'measures: ask again a little later. For another goal than the '
          'panel\'s, a size that needs measuring stays unknown; a sample '
          '(`$c queue add --sample middle`) shows it.',
    ],
    options: [
      ('--goal <goal>', 'say what this goal would do to each video.'),
      ('--opt <option>=<choice>', 'an option of that goal, once for each.'),
    ],
    examples: ['$c videos', '$c videos --goal archive --json'],
    text: videoText(
      VideoView.fromJson({..._video.toJson(), 'preview': _preview.toJson()}),
    ),
    json: [
      '`videos` (list of Video), in the order of the list; with `--goal`, '
          'each readable one has a `preview` (Preview).',
      ..._jsonBlock({
        'videos': [
          {..._video.toJson(), 'preview': _preview.toJson()},
        ],
      }),
    ],
    shapes: ['Video', 'Preview'],
    errors: [
      'An unknown goal, option or choice, or `--opt` without `--goal`: '
          'exit 5.',
    ],
  ),
  _CommandDoc(
    'remove',
    arguments: '<videos…>',
    summary: 'takes videos off the list; their files stay on disk',
    about: [
      'Only off the window\'s list, as its own remove button does: the files '
          'stay on disk, and jobs already queued for these videos stay in '
          'the queue.',
    ],
    examples: ['$c remove 0 ~/Videos/party.mov'],
    text: [removedText(0), removedText(1)],
    json: [
      '`removed` (list of int): the ids taken off the list.',
      ..._jsonBlock({
        'removed': [0, 1],
      }),
    ],
    errors: ['A video that is not in the list: exit 5, and none is taken off.'],
  ),
  _CommandDoc(
    'queue',
    summary: 'the jobs in the queue, as the queue pane shows them',
    about: [
      'Each job with its status, progress and time left, its goal and '
          'options, its result once known, and how its quality was chosen.',
    ],
    examples: ['$c queue', '$c queue --json'],
    text: queueText(true, false, [_doneJob, _runningJob, _waitingJob]),
    json: [
      '`paused` (bool): the queue is paused in the window; `busy` (bool): '
          'it is working through jobs; `jobs` (list of Job), in queue order.',
    ],
    shapes: ['Job', 'Quality'],
  ),
  _CommandDoc(
    'queue add',
    arguments: '<videos…>',
    summary: 'queues videos with a goal, as Add to queue does',
    about: [
      'Videos given by a path that is not in the list yet are added first, '
          'as `$c add` does; a folder gives the videos in it. Each video that can be read gets a job; one '
          'with the same goal, options, sample and folder still waiting in '
          'the queue is reported as queued already, not queued twice. '
          'Nothing is queued when any argument is wrong.',
      'Without `--goal`, the goal and options shown in the window\'s panel '
          'are used, as by its Add to queue button; the answer says which. '
          'Name the goal to be sure. Without `--sample`, the whole video. '
          'Without `--out`, the folder the panel is set to: `Converted` '
          'beside each video unless the person chose another.',
    ],
    options: [
      ('--goal <goal>', 'the goal, as `$c goals` lists them.'),
      (
        '--opt <option>=<choice>',
        'an option of the goal, once for each; '
            'the others keep their defaults.',
      ),
      (
        '--sample start|middle',
        'a 10-second sample from the start or the '
            'middle instead of the whole video, into `Samples`.',
      ),
      (
        '--out next|<folder>',
        '`next`: a folder beside each video; or one '
            'folder for every result.',
      ),
      (
        '--subfolder <name>',
        'the name of the folder beside each video '
            '(`Converted` unless given); implies `--out next`.',
      ),
    ],
    examples: [
      '$c queue add 0 1 --goal archive',
      '$c queue add ~/Videos/trip --goal archive --opt codec=hevc --json',
      '$c queue add 2 --goal archive --sample middle',
    ],
    text: queueAddText(_queueAddAnswer),
    json: [
      '`goal` (string): the goal\'s id; `options` (object): every option of '
          'the goal and its choice; `added` (list of Job): the new jobs; '
          '`alreadyQueued` (list of int): the videos that were queued '
          'already; `skipped` (list): `video` (int or string, as given) and '
          '`reason` (string: `unreadable` or `notFound`).',
      ..._jsonBlock(_queueAddAnswer),
    ],
    shapes: ['Job', 'Quality'],
    errors: [
      'An unknown goal, option or choice, a choice of an option this '
          'computer does not offer other than the one made here anyway, a '
          'video id not in the list, or a `--subfolder` that is not one '
          'folder\'s name: exit 5, with the valid ones named.',
    ],
  ),
  _CommandDoc(
    'queue remove',
    arguments: '<jobs…>',
    summary: 'takes jobs out of the queue; any finished file stays on disk',
    about: [
      'As each job\'s remove in the window: a waiting job is taken out, one '
          'under way is cancelled first, and one that has ended only leaves '
          'the queue. Every file stays on disk, the original and any result.',
      'To take out every done and skipped job at once: `$c queue '
          'clear-finished`.',
    ],
    examples: ['$c queue remove 2', '$c queue remove 0 1 --json'],
    text: [takenOutText(2)],
    json: [
      '`removed` (list of int): the jobs taken out.',
      ..._jsonBlock({
        'removed': [2],
      }),
    ],
    errors: ['A job that is not in the queue: exit 5, and none is taken out.'],
  ),
  _CommandDoc(
    'queue move',
    arguments: '<job> <position>',
    summary: 'moves a waiting job to another place in the queue',
    about: [
      'As dragging it in the window, where only waiting jobs can be dragged. '
          'Positions count from 1, the top of the list; one past the end is '
          'the end. The queue converts the waiting job nearest the top next, '
          'so `$c queue move <job> 1` makes it the next.',
    ],
    examples: ['$c queue move 2 1'],
    text: movedText([_waitingJob, _doneJob, _runningJob]),
    json: ['`jobs` (list of Job): the whole queue, in its new order.'],
    shapes: ['Job', 'Quality'],
    errors: [
      'A job that is not in the queue or not waiting, or a position that is '
          'not a whole number: exit 5.',
    ],
  ),
  _CommandDoc(
    'queue retry',
    arguments: '<job>',
    summary: 'tries a failed or cancelled job again, as its retry button does',
    about: [
      'The job waits its turn again, in its place, with the same settings. '
          'Look at why it failed first: `$c queue --json` gives its '
          '`errorLines`. Trying again rarely helps when the video itself '
          'cannot be converted; tell the person instead.',
    ],
    examples: ['$c queue retry 2'],
    text: [retriedText(_waitingJob)],
    json: [
      '`job` (Job): the job, waiting again.',
      ..._jsonBlock({'job': _waitingJob.toJson()}),
    ],
    shapes: ['Job', 'Quality'],
    errors: [
      'A job that is not in the queue, or one that neither failed nor was '
          'cancelled: exit 5.',
    ],
  ),
  _CommandDoc(
    'queue clear-finished',
    summary:
        'takes the done and skipped jobs out of the queue; their files stay '
        'on disk',
    about: [
      'As "Clear finished" in the window. Only the queue changes: each '
          'result stays where its `outputPath` said. Failed and cancelled '
          'jobs stay, to be tried again.',
    ],
    examples: ['$c queue clear-finished'],
    text: clearedText([0]),
    json: [
      '`removed` (list of int): the jobs taken out; empty when none had '
          'ended done or skipped.',
      ..._jsonBlock({
        'removed': [0],
      }),
    ],
  ),
  _CommandDoc(
    'queue convert-anyway',
    arguments: '<job>',
    summary: 'converts a video kept as it is, as "Convert anyway" does',
    about: [
      'For a job that ended `skipped` with the outcome `notWorthIt`: Archive '
          'found that converting would hardly make the file smaller. A new '
          'job converts it all the same, at the quality found for it, with '
          'the same goal, options and folder. Ask the person first: the '
          'result is nearly as large as the original.',
    ],
    examples: ['$c queue convert-anyway 3'],
    text: addedJobText(_againAnswer),
    json: [
      '`added` (list of Job): the new job, or none when a job just like it '
          'is waiting or under way already; `alreadyQueued` (bool): that '
          'is so.',
      ..._jsonBlock(_againAnswer),
    ],
    shapes: ['Job', 'Quality'],
    errors: [
      'A job that is not in the queue, or one that was not kept as it is: '
          'exit 5.',
    ],
  ),
  _CommandDoc(
    'queue convert-whole',
    arguments: '<job>',
    summary:
        'queues the whole video after a sample, as the window\'s button '
        'does',
    about: [
      'For a sample job, as "Convert the whole video" under it in the '
          'window: a new job converts the whole video the sample was taken '
          'from, with the same goal, options and folder, into the output '
          'folder rather than `Samples`.',
    ],
    examples: ['$c queue convert-whole 3 --json'],
    text: addedJobText(_againAnswer),
    json: [
      '`added` (list of Job) and `alreadyQueued` (bool), as for `queue '
          'convert-anyway`.',
    ],
    shapes: ['Job', 'Quality'],
    errors: ['A job that is not in the queue, or not a sample: exit 5.'],
  ),
  _CommandDoc(
    'pause',
    summary: 'pauses the queue, as the window\'s pause button does',
    about: [
      'Nothing new starts, and the job under way is held where the system '
          'allows (otherwise it finishes). A job still choosing its quality '
          'stops measuring, and measures again on `$c resume`. Pausing a '
          'paused queue changes nothing, so a script may repeat it. The '
          'window shows the queue paused, and the person may continue it '
          'there.',
    ],
    examples: ['$c pause'],
    text: [pausedText(paused: true)],
    json: [
      '`paused` (bool): true.',
      ..._jsonBlock({'paused': true}),
    ],
  ),
  _CommandDoc(
    'resume',
    summary: 'lets a paused queue go on',
    about: [
      'The job held goes on, then the next. Resuming a queue that is not '
          'paused changes nothing.',
    ],
    examples: ['$c resume'],
    text: [pausedText(paused: false)],
    json: [
      '`paused` (bool): false.',
      ..._jsonBlock({'paused': false}),
    ],
  ),
  _CommandDoc(
    'cancel',
    arguments: '[job]',
    summary: 'cancels the job under way, as its cancel button does',
    about: [
      'It answers once the job has stopped; the queue goes on with the next '
          'one. The job stays in the queue as `cancelled`; no result is '
          'written for it, and the original stays as it is. `$c queue retry '
          '<job>` tries it again.',
      'With a job id, only if that job is the one converting, so that '
          'another is not cancelled by mistake. A waiting job is taken out '
          'of the queue with `$c queue remove <job>` instead.',
    ],
    examples: ['$c cancel', '$c cancel 1 --json'],
    text: [
      cancelledText(1),
      '',
      '# When no job is converting:',
      cancelledText(null),
    ],
    json: [
      '`cancelled` (int, or null when no job was converting).',
      ..._jsonBlock({'cancelled': 1}),
    ],
    errors: [
      'A job that is not in the queue, or not the one converting: exit 5, '
          'and nothing is cancelled.',
    ],
  ),
  _CommandDoc(
    'wait',
    arguments: '[jobs…]',
    summary: 'waits until the jobs are finished, and says how each ended',
    about: [
      'Without job ids, until no job is waiting or converting; with ids, '
          'until those have ended. Jobs added meanwhile, by this program or '
          'the person, count too. The rules are under "Waiting and events". '
          'Conversions can take hours: run it in the background.',
      'Each job is printed as soon as it ends; the last line sums up. '
          'Exit 0 when every job ended done or skipped, 1 when one failed or '
          'was cancelled, 3 after `--timeout`, 4 when the window closed.',
    ],
    options: [
      (
        '--timeout <seconds>',
        'give up after this long, with exit 3; the jobs '
            'go on in the window.',
      ),
    ],
    examples: ['$c wait', '$c wait 3 4 --timeout 600 --json'],
    text: [
      ...finishedText(_doneJob),
      ...finishedText(_checkedJob),
      'All done.',
    ],
    json: [
      '`outcomes` (list of Outcome), once all have ended; nothing is printed '
          'before.',
      ..._jsonBlock(_waitAnswer),
    ],
    shapes: ['Outcome'],
    errors: ['A job id not in the queue: exit 5.'],
  ),
  _CommandDoc(
    'events',
    summary: 'tells what happens in the window, as it happens',
    about: [
      'It goes on until the window closes, then exits 4: stop it yourself '
          'when you no longer need it. First it tells how everything stands '
          '(`snapshot`), so nothing is missed by starting late. The events '
          'are listed under "Waiting and events".',
    ],
    options: [
      (
        '--since-now',
        'leave out the `snapshot`; only what happens from now '
            'on.',
      ),
    ],
    examples: ['$c events --since-now --json'],
    text: [
      ...eventText(Events.jobStarted, _runningJob.toJson()),
      ...eventText(Events.jobProgress, {
        'job': 1,
        'fraction': .42,
        'remainingSeconds': 1260,
      }),
      ...eventText(Events.jobFinished, _doneJob.toJson()),
      ...eventText(Events.queueIdle, const {}),
    ],
    json: [
      'one JSON object per line: `event` (string), `time` (string, UTC, ISO '
          '8601; not on `app-closing`) and the event\'s fields.',
      '```json',
      jsonEncode({
        'event': Events.jobProgress,
        'time': '2026-10-23T14:05:09.120Z',
        'job': 1,
        'fraction': .42,
        'remainingSeconds': 1260.0,
      }),
      '```',
    ],
    shapes: ['Video', 'Job', 'Quality'],
  ),
  _CommandDoc(
    'manual',
    summary: 'prints this guide',
    about: ['It needs no window and opens none.'],
    examples: ['$c manual', '$c manual --json'],
    text: ['# vidctrl-client', '…'],
    json: [
      'the same as data: `commands` (list: `name`, `arguments`, '
          '`description`, `options`), `goals` (list: like Goal, with `goal`, '
          'the name `--goal` takes, and a `hint` for each goal and option), '
          '`exitCodes` (object: code to meaning) and `events` (list: `name`, '
          '`fields`, `description`).',
    ],
  ),
  _CommandDoc(
    'help',
    arguments: '[command]',
    summary: 'the commands, or one command\'s part of this guide',
    about: [
      'Without a command, the short list `--help` prints. It needs no window '
          'and opens none.',
    ],
    examples: ['$c help queue add'],
    text: ['### `$c queue add <videos…>`', '…'],
    json: ['the same text; `help` has no JSON.'],
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
- `options` (object): every option of the goal and its choice.
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

Preset get _firstGoal => scenarios.first.presets.first;

/// A goal as `goals` gives it, from the words here.
GoalView _goalView(Preset preset, Map<String, GoalWords> words) {
  final scenario = scenarios.firstWhere((s) => s.presets.contains(preset));
  return GoalView.fromJson(_goalJson(scenario, preset, words[preset.id]));
}

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
