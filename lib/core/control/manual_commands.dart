import 'dart:convert';

import '../ffmpeg/capabilities.dart';
import '../ffmpeg/command_builder.dart';
import '../ffmpeg/command_text.dart';
import '../media/media_details.dart' show DetailGroup;
import '../media/media_info.dart';
import '../media/video_files.dart' show videoExtensions;
import '../scenarios/archive.dart';
import '../scenarios/registry.dart';
import '../scenarios/scenario.dart';
import 'client_text.dart';
import 'codes.dart';
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
  plan: PlanCodes.encode,
  expectedBytes: 610000000,
  measured: true,
  measuring: false,
  closeness: ClosenessCodes.same,
);

const _video = VideoView(
  id: 0,
  path: '$_folder/beach.mov',
  status: VideoStatusCodes.ready,
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
  status: JobStatusCodes.done,
  outputPath: '$_folder/Converted/beach_av1-crf35.mp4',
  outputBytes: 598000000,
  quality: QualityView(
    outcome: OutcomeCodes.standard,
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
  status: JobStatusCodes.running,
  fraction: .42,
  remainingSeconds: 1260,
  outputPath: '$_folder/Converted/party_av1-crf20-check.mp4',
  quality: QualityView(
    outcome: OutcomeCodes.belowTarget,
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
  status: JobStatusCodes.done,
  outputPath: '$_folder/Converted/party_av1-crf20-check.mp4',
  outputBytes: 2100000000,
  quality: QualityView(
    outcome: OutcomeCodes.belowTarget,
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
  status: JobStatusCodes.waiting,
  needsALook: false,
  errorLines: [],
);

const _status = StatusView(
  state: StateCodes.ready,
  version: '1.2.0',
  busy: true,
  paused: false,
  jobs: {
    JobStatusCodes.done: 1,
    JobStatusCodes.running: 1,
    JobStatusCodes.waiting: 1,
  },
);

final _addAnswer = {
  'videos': [
    {'path': '$_folder/beach.mov', 'id': 0, 'result': AddResultCodes.added},
    {'path': '$_folder/party.mov', 'id': 1, 'result': AddResultCodes.known},
    {
      'path': '$_folder/notes.mov',
      'id': 3,
      'result': AddResultCodes.unreadable,
    },
    {'path': '$_folder/missing.mov', 'result': AddResultCodes.notFound},
  ],
};

final _queueAddAnswer = {
  'goal': 'archive.master',
  'options': _options,
  'added': [_waitingJob.toJson()],
  'alreadyQueued': [0],
  'skipped': [
    {'video': 3, 'reason': AddResultCodes.unreadable},
  ],
};

/// A job made from job 3, a sample of trip.mov or that video kept as it is.
const _anotherJob = JobView(
  id: 4,
  videoId: 3,
  path: '$_folder/trip.mov',
  goal: 'archive.master',
  options: _options,
  status: JobStatusCodes.waiting,
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
      status: JobStatusCodes.done,
      outputPath: '$_folder/Converted/beach_av1-crf35.mp4',
      needsALook: false,
    ).toJson(),
    const JobOutcome(
      jobId: 1,
      path: '$_folder/party.mov',
      status: JobStatusCodes.done,
      outputPath: '$_folder/Converted/party_av1-crf20-check.mp4',
      needsALook: true,
    ).toJson(),
  ],
};

/// What "Show the command" shows for [_checkedJob], made as the window
/// makes it: party.mov, a 4K camera video, converted by Archive at the
/// quality chosen for it, with VidCtrl's own FFmpeg.
final _command = () {
  const info = MediaInfo(
    path: '$_folder/party.mov',
    formatName: 'mov,mp4,m4a,3gp,3g2,mj2',
    duration: Duration(minutes: 31, seconds: 12),
    sizeBytes: 4040000000,
    video: VideoStream(
      index: 0,
      codec: 'hevc',
      width: 3840,
      height: 2160,
      pixFmt: 'yuv420p10le',
      averageFrameRate: 25,
      nominalFrameRate: 25,
    ),
    audio: [
      AudioStream(index: 1, codec: 'aac', channels: 2, sampleRate: 48000),
    ],
  );
  final capabilities = Capabilities(
    ffmpegVersion: '8.1',
    encoders: const {'libsvtav1', 'libx265', 'aac'},
    svtAv1Params: svtAv1ParamCandidates.first,
  );
  const archive = ArchivePreset();
  final plan = archive.withQuality(
    archive.plan(info, const {}, capabilities),
    _checkedJob.quality!.value,
    belowTarget: true,
  );
  final args = buildFfmpegArgs(
    input: info.path,
    output: _checkedJob.outputPath!,
    plan: plan,
    forDisplay: true,
  );
  return singleLineCommand('ffmpeg', args, shell: ShellStyle.posix);
}();

final _jobAnswer = {'job': _checkedJob.toJson(), 'command': _command};

final _compareAnswer = {
  'job': 1,
  'status': ComparisonCodes.measured,
  'closeness': ClosenessCodes.veryClose,
  'xpsnr': 40.6,
  'vmaf': 94.1,
};

final _detailsAnswer = {
  'info': _video.toJson(),
  'details': [
    {
      'group': codeOf(DetailGroup.video),
      'number': 1,
      'title': 'Video track 1',
      'rows': [
        [
          'Codec',
          'H.265 / HEVC (High Efficiency Video Coding) · Main 10 · level 5.1',
        ],
        ['Resolution', '3840×2160'],
        ['Frame rate', '25 fps (25/1)'],
        ['Bit depth', '10-bit'],
        ['Chroma subsampling', '4:2:0'],
      ],
    },
    {
      'group': codeOf(DetailGroup.audio),
      'number': 1,
      'title': 'Audio track 1',
      'rows': [
        ['Codec', 'AAC (Advanced Audio Coding) · LC'],
        ['Channels', '2 (stereo)'],
        ['Sample rate', '48 kHz'],
      ],
    },
    {
      'group': codeOf(DetailGroup.file),
      'number': 1,
      'title': 'File',
      'rows': [
        ['Container', 'QuickTime / MOV'],
        ['Size', '4.20 GB'],
      ],
    },
  ],
};

final _estimateAnswer = {
  'videos': [
    {..._video.toJson(), 'preview': _preview.toJson()},
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
          'found) and `result` (string): `ADDED`, `KNOWN` (in the list '
          'already), `UNREADABLE` (in the list, but not a video FFmpeg can '
          'open) or `NOT_FOUND`; see "Adding".',
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
          'panel\'s, a size that needs measuring stays unknown until '
          '`$c estimate` measures it.',
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
    'details',
    area: CommandArea.videos,
    arguments: '<video> | --job <job>',
    summary: 'how a video or a result is made, as "Video details" shows it',
    about: [
      'As "Video details" in the window: how the file is encoded, track by '
          'track (picture, then sound, then the file as a whole), in the '
          'window\'s words. A video still being read is waited for. With '
          '`--job`, the same for the result of a job that is done, as '
          '"Result details" in its ⋯ menu.',
    ],
    options: [
      ('--job <job>', 'the result of this job instead of a video in the list.'),
      (
        '--raw',
        'FFmpeg\'s whole report on the file (ffprobe\'s JSON), instead of '
            'the details.',
      ),
    ],
    examples: ['$c details 0', '$c details --job 1 --raw --json'],
    text: detailsText(_detailsAnswer),
    json: [
      '`info` (Video): the video; for a job, its result, with the `id` of '
          'the video it was made from. `details` (list): for each track and '
          'the file, `group` (string: what it describes, see "Details"), '
          '`number` (int: its place among those of its group, from 1), '
          '`title` (string) and `rows` (list of [label, value], both '
          'strings), in the window\'s words. With `--raw`, `raw` (object) '
          'instead of '
          '`details`: ffprobe\'s report as it gave it.',
      ..._jsonBlock(_detailsAnswer),
    ],
    shapes: ['Video'],
    errors: [
      'A video that is not in the list, a job that is not done, or a result '
          'that cannot be read where it was written: exit 5 (`NOT_FOUND`). A '
          'video FFmpeg cannot open: exit 5.',
    ],
  ),
  CommandDoc(
    'estimate',
    area: CommandArea.videos,
    arguments: '<videos…>',
    summary: 'measures how large videos would come out with a goal',
    about: [
      'As the window does for the videos selected in its panel: it encodes '
          'a few short pieces of each video and compares them with the '
          'original, so it knows how large the result would be and how '
          'close it would look; Archive also chooses each video\'s quality, '
          'as before converting it. It answers once every video is '
          'measured, one after the other: seconds to a minute or so each. A '
          'size the goal knows without measuring (a copy) is given at once. '
          'When the window is already measuring as many videos as it does '
          'at once, it waits its turn.',
      'Only while the queue is idle, as in the window: measuring and '
          'converting would share the processor. Without `--goal`, the goal '
          'shown in the window\'s panel. What it measured stays in the '
          'window: `$c videos --goal <goal>` gives it again, and the '
          'window\'s list shows it for the goal of its panel.',
    ],
    options: [
      ('--goal <goal>', 'the goal, as `$c goals` lists them.'),
      ('--opt <option>=<choice>', 'an option of that goal, once for each.'),
    ],
    examples: ['$c estimate 0 1 2 --goal archive --json'],
    text: [
      for (final v in _estimateAnswer['videos']!)
        ...videoText(VideoView.fromJson(v)),
    ],
    json: [
      '`videos` (list of Video), as given, each that could be read with its '
          '`preview` (Preview) for the goal.',
      ..._jsonBlock(_estimateAnswer),
    ],
    shapes: ['Video', 'Preview'],
    errors: [
      'While the queue converts, or when converting starts before it has '
          'measured them all: `BUSY`, exit 5 ("Videos are being converted; '
          'the window measures when the queue is idle."). Measure before '
          'queuing, or after `$c wait`.',
      'A video that is not in the list (`$c add` it first), one FFmpeg '
          'cannot open, or an unknown goal, option or choice: exit 5.',
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
          '`reason` (string: `UNREADABLE` or `NOT_FOUND`).',
      ..._jsonBlock(_queueAddAnswer),
    ],
    shapes: ['Job', 'Quality'],
    errors: [
      'An unknown goal, option or choice, a choice of an option this '
          'computer does not offer other than the one made here anyway, a '
          'video id not in the list, or a `--subfolder` that is not one '
          'folder\'s name: exit 5, with the valid ones named.',
      'Nothing to queue, every path or video skipped (nothing found '
          'there, or it cannot be read): exit 5, with the reason for each.',
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
      'For a job that ended `SKIPPED` with the outcome `NOT_WORTH_IT`: Archive '
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
      'For a sample job that is done, as "Convert the whole video" under '
          'it in the window: a new job converts the whole video the sample '
          'was taken from, with the same goal, options and folder, into the '
          'output folder rather than `Samples`.',
    ],
    examples: ['$c queue convert-whole 3 --json'],
    text: addedJobText(_againAnswer),
    json: [
      '`added` (list of Job) and `alreadyQueued` (bool), as for `queue '
          'convert-anyway`.',
    ],
    shapes: ['Job', 'Quality'],
    errors: [
      'A job that is not in the queue, not a sample, or a sample not done '
          'yet: exit 5.',
    ],
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
          'one. The job stays in the queue as `CANCELLED`; no result is '
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
    'job',
    area: CommandArea.results,
    arguments: '<job>',
    summary: 'one job, as its row and (i) window show it',
    about: [
      'Its status, goal and options, its result and size once done, and how '
          'its quality was chosen: the outcome and the scores of the poorest '
          'piece. A job worth a look by eye (`needsALook`, the outcome '
          '`BELOW_TARGET`) has a name ending in `-check`: tell the person to '
          'look at it beside the original.',
      'With `--command`, what "Show the command" in its ⋯ menu shows: the '
          'FFmpeg command VidCtrl runs for it, for this system\'s terminal '
          '(PowerShell on Windows). It is for the person to read: do not run '
          'it, the window converts. For an Archive job whose quality is not '
          'chosen yet, its quality number may still change.',
    ],
    options: [('--command', 'add the FFmpeg command VidCtrl runs for it.')],
    examples: ['$c job 1', '$c job 1 --command --json'],
    text: jobDetailsText(_checkedJob, command: true, commandLine: _command),
    json: [
      '`job` (Job); `command` (string, optional): with `--command`, left '
          'out for a job that runs nothing (one that ended skipped or is '
          'kept as it is).',
      ..._jsonBlock(_jobAnswer),
    ],
    shapes: ['Job', 'Quality'],
    errors: ['A job that is not in the queue: exit 5.'],
  ),
  CommandDoc(
    'compare',
    arguments: '<job>',
    area: CommandArea.results,
    summary: 'compares a result with its original, as the window\'s menu does',
    about: [
      'As "Compare with the original" in a done job\'s ⋯ menu: VidCtrl '
          'compares the result with its original frame by frame (a sample '
          'with the same piece of it) and says how close it looks, by VMAF '
          'where this FFmpeg measures it, otherwise by XPSNR (see '
          '"Closeness"). It takes about as long as the video lasts, or '
          'longer, and one comparison runs at a time. The window shows it '
          'under the job, and the person may stop it there.',
      'Offered only where each frame of the result stands for one of the '
          'original: not after the picture was made smaller, its frame rate '
          'changed or its HDR turned into SDR ("Save space" makes 4K videos '
          '1080p). Asked again while that job is being compared, it waits '
          'for the same comparison.',
    ],
    options: [
      (
        '--no-wait',
        'answer at once; the `COMPARE_FINISHED` event (`$c events`) tells '
            'the result.',
      ),
    ],
    examples: ['$c compare 1', '$c compare 1 --no-wait --json'],
    text: [
      comparedText(1, _compareAnswer),
      '',
      '# With --no-wait:',
      comparingText(1),
    ],
    json: [
      '`job` (int); `status` (string): `MEASURED`; `closeness` (string, see '
          '"Closeness"); `xpsnr` '
          '(number, in dB); `vmaf` (number, optional: where this FFmpeg '
          'measures it). With `--no-wait`, `{"started": true}`.',
      ..._jsonBlock(_compareAnswer),
    ],
    errors: [
      'A job that is not done, or whose frames do not pair with the '
          'original\'s, or an FFmpeg without the `xpsnr` filter: exit 5, '
          'saying why.',
      'Another job being compared: `BUSY`, exit 5; ask again once it has '
          'ended.',
      'The comparison failed (exit 5, with FFmpeg\'s words), or was '
          'stopped in the window (exit 5).',
    ],
  ),
  CommandDoc(
    'status',
    area: CommandArea.waiting,
    summary: 'whether VidCtrl is open, and how its queue stands',
    about: [
      'It never opens the window. A window that has just opened is '
          '`STARTING` while it looks for FFmpeg, then `READY`, or '
          '`FFMPEG_MISSING` when it found none.',
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
          '(`SNAPSHOT`), so nothing is missed by starting late. The events '
          'are listed under "Waiting and events".',
    ],
    options: [
      (
        '--since-now',
        'leave out the `SNAPSHOT`; only what happens from now '
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
      'one JSON object per line: `event` (string, the event\'s code), '
          '`time` (string, UTC, ISO 8601; not on `APP_CLOSING`) and the '
          'event\'s fields.',
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
          '`exitCodes` (object: code to meaning), `events` (list: `name`, '
          '`fields`, `description`) and `codes` (object: for each kind of '
          'code, as "What the results mean" lists them, a list of `code` and '
          '`description`).',
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
