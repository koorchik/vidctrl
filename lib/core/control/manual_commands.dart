import 'dart:convert';

import '../media/video_files.dart' show videoExtensions;
import '../scenarios/registry.dart';
import '../scenarios/scenario.dart';
import 'client_text.dart';
import 'manual.dart';
import 'manual_words.g.dart';
import 'protocol.dart';
import 'views.dart';

// Each command's part of vidctrl-client's manual, with samples of what it
// prints, made by the client's own words. Nothing here speaks of deleting a
// file (see `speaksOfDeleting`).

/// What a command is about: `--help` lists the commands by area, in this
/// order.
enum CommandArea {
  videos('Videos'),
  queue('The queue'),
  results('Results'),
  waiting('Waiting and following'),
  help('Help');

  const CommandArea(this.title);

  final String title;
}

/// One command's part of the manual.
class CommandDoc {
  const CommandDoc(
    this.name, {
    required this.area,
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

  /// Where `--help` lists it.
  final CommandArea area;

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

  /// The names of the shapes in [json], as the manual's "What `--json`
  /// gives" names them.
  final List<String> shapes;

  /// How it can fail, besides the failures every command shares.
  final List<String> errors;
}

Preset get _firstGoal => scenarios.first.presets.first;

/// A goal as `goals` gives it, from the words here.
GoalView _goalView(Preset preset, Map<String, GoalWords> words) {
  final scenario = scenarios.firstWhere((s) => s.presets.contains(preset));
  return GoalView.fromJson(goalJson(scenario, preset, words[preset.id]));
}

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

/// Every command's part of the manual, in the order `--help` lists them,
/// with [c] as the command that runs the client.
List<CommandDoc> commandDocs(
  String c, [
  Map<String, GoalWords> words = manualGoalWords,
]) => [
  CommandDoc(
    'add',
    area: CommandArea.videos,
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
  CommandDoc(
    'videos',
    area: CommandArea.videos,
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
  CommandDoc(
    'remove',
    area: CommandArea.videos,
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
  CommandDoc(
    'queue',
    area: CommandArea.queue,
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
  CommandDoc(
    'queue add',
    area: CommandArea.queue,
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
          'the goal and the choice made on this computer, as in Job; '
          '`added` (list of Job): the new jobs; '
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
  CommandDoc(
    'queue remove',
    area: CommandArea.queue,
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
  CommandDoc(
    'queue move',
    area: CommandArea.queue,
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
  CommandDoc(
    'queue retry',
    area: CommandArea.queue,
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
  CommandDoc(
    'queue clear-finished',
    area: CommandArea.queue,
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
  CommandDoc(
    'queue convert-anyway',
    area: CommandArea.queue,
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
  CommandDoc(
    'queue convert-whole',
    area: CommandArea.queue,
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
  CommandDoc(
    'pause',
    area: CommandArea.queue,
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
  CommandDoc(
    'resume',
    area: CommandArea.queue,
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
  CommandDoc(
    'cancel',
    area: CommandArea.queue,
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
      '# When it ended before it could be cancelled:',
      cancelledText(null, ended: _doneJob),
      '',
      '# When no job is converting:',
      cancelledText(null),
    ],
    json: [
      '`cancelled` (int, or null when nothing was cancelled); `job` (Job, '
          'optional): when it ended otherwise before it could be cancelled '
          '(done, say), how it ended.',
      ..._jsonBlock({'cancelled': 1}),
    ],
    shapes: ['Job', 'Quality'],
    errors: [
      'A job that is not in the queue, or not the one converting: exit 5, '
          'and nothing is cancelled.',
    ],
  ),
  CommandDoc(
    'status',
    area: CommandArea.waiting,
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
  CommandDoc(
    'wait',
    area: CommandArea.waiting,
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
  CommandDoc(
    'events',
    area: CommandArea.waiting,
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
  CommandDoc(
    'goals',
    area: CommandArea.help,
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
  CommandDoc(
    'manual',
    area: CommandArea.help,
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
  CommandDoc(
    'help',
    area: CommandArea.help,
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
