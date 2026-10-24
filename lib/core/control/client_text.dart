import 'dart:math';

import '../media/media_details.dart' show formatBytes, fullReport;
import 'codes.dart';
import 'manual.dart' show ChoiceWords, GoalWords, OptionWords;
import 'manual_words.g.dart';
import 'protocol.dart';
import 'views.dart';
import 'words.dart';

// What vidctrl-client prints for people: plain words first, then the ids a
// person or an agent refers to things by, and the technical names last.
// Nothing here speaks of deleting a file (see `speaksOfDeleting`).

List<String> statusText(StatusView status) {
  final name = status.version.isEmpty ? 'VidCtrl' : 'VidCtrl ${status.version}';
  return switch (status.state) {
    StateCodes.ready => [
      '$name is open and ready.',
      _queueSummary(status.busy, status.paused, status.jobs),
    ],
    StateCodes.starting => ['$name is starting: it is looking for FFmpeg.'],
    StateCodes.ffmpegMissing => [
      '$name is open, but it could not find FFmpeg; the window says what '
          'to do.',
    ],
    _ => ['$name is open (${status.state}).'],
  };
}

String _queueSummary(bool busy, bool paused, Map<String, int> jobs) {
  final counts = [
    for (final MapEntry(:key, :value) in jobs.entries)
      '$value ${statusWords(key).toLowerCase()}',
  ];
  return 'The queue is ${_queueState(busy, paused)}'
      '${counts.isEmpty ? ', with no jobs' : ': ${counts.join(', ')}'}.';
}

String _queueState(bool busy, bool paused) => paused
    ? 'paused in the window'
    : busy
    ? 'converting'
    : 'idle';

/// The goals, each by the shortest name `--goal` takes: its kind's when
/// that kind has no other. The window sends ids only; the words are the
/// manual's ([words]), and a goal, option or choice they lack goes by its
/// id, as one of a newer window would.
List<String> goalsText(
  List<GoalView> goals, {
  Map<String, GoalWords> words = manualGoalWords,
}) {
  String name(GoalView goal) =>
      goals.where((g) => g.scenario == goal.scenario).length == 1
      ? goal.scenario
      : goal.id;
  return [
    for (final (i, goal) in goals.indexed) ...[
      if (i > 0) '',
      '${_goalTitle(goal, words[goal.id])}: --goal ${name(goal)}',
      for (final option in goal.options)
        ..._optionText(option, words[goal.id]?.options[option.id]),
    ],
  ];
}

String _goalTitle(GoalView goal, GoalWords? words) => words == null
    ? goal.id
    : [words.title, if (words.subtitle.isNotEmpty) words.subtitle].join(', ');

List<String> _optionText(OptionView option, OptionWords? words) => [
  '  ${words?.title ?? option.id}'
      '${option.advanced ? ' (under More options…)' : ''}: '
      '--opt ${option.id}=…',
  for (final choice in option.choices)
    _choiceText(choice, words?.choices[choice], option.defaultChoice),
];

/// A choice's label and id, and its hint; a label that only repeats the id
/// ("yes") is said once.
String _choiceText(String choice, ChoiceWords? words, String defaultChoice) {
  final named = words == null || words.label.toLowerCase() == choice
      ? choice
      : '${words.label}: $choice';
  final standard = choice == defaultChoice ? ' (the default)' : '';
  final hint = words == null || words.hint.isEmpty ? '' : '. ${words.hint}';
  return '    $named$standard$hint';
}

/// One line of a `videos.add` answer.
String addedText(Map<String, Object?> entry) {
  final path = entry['path'];
  final id = entry['id'];
  return switch (entry['result']) {
    AddResultCodes.added => 'Video $id: Added. $path',
    AddResultCodes.known => 'Video $id: In the list already. $path',
    AddResultCodes.unreadable =>
      'Video $id: ${statusWords(VideoStatusCodes.unreadable)}. $path',
    _ => 'Nothing found at $path: no file, nor a folder with videos.',
  };
}

List<String> videoText(VideoView video) => [
  'Video ${video.id}: ${statusWords(video.status)}. ${video.path}',
  ..._factsText(video),
  if (video.preview case final preview?) '  ${_previewText(preview)}',
];

/// Its size, length, picture and sound, on one line.
List<String> _factsText(VideoView video) {
  final facts = [
    if (video.sizeBytes case final bytes?) formatBytes(bytes),
    if (video.durationSeconds case final seconds?) _clock(seconds),
    if (video.width != null && video.height != null)
      '${video.width}x${video.height}',
    ?video.videoCodec,
    if (video.audioCodecs.isNotEmpty) 'sound ${video.audioCodecs.join(', ')}',
    if (video.hdr) 'HDR',
  ];
  return [if (facts.isNotEmpty) '  ${facts.join(', ')}'];
}

/// A `videos.details` answer asked with `sections`: the video, or the
/// result of [job], then each track's details as the window's "Video
/// details" shows them, in its words.
List<String> detailsText(Map<String, Object?> answer, {int? job}) {
  final info = VideoView.fromJson(
    Map<String, Object?>.from(answer['info'] as Map),
  );
  return [
    if (job == null)
      ...videoText(info)
    else ...[
      'Job $job\'s result: ${info.path}',
      ..._factsText(info),
    ],
    for (final section in (answer['sections'] as List?) ?? const []) ...[
      '${(section as Map)['title']}:',
      for (final row in section['rows'] as List)
        '  ${(row as List).first}: ${row.last}',
    ],
  ];
}

/// The whole report of a `videos.details --raw` answer, as FFmpeg gives it.
List<String> reportText(Map<String, Object?> answer) => [
  fullReport(Map<String, Object?>.from(answer['raw'] as Map)),
];

String _previewText(GoalPreview preview) {
  final size = switch (preview.expectedBytes) {
    final bytes? =>
      ' About ${formatBytes(bytes)}'
          '${preview.measured ? ', measured' : ''}.',
    null when preview.measuring => ' Measuring the size…',
    null => '',
  };
  final closeness = preview.closeness == null
      ? ''
      : ' ${closenessWords(preview.closeness!)}.';
  return 'With ${preview.goal}: ${planWords(preview.plan)}.$size$closeness';
}

String removedText(int id) =>
    'Video $id: Off the list; its file stays on disk.';

/// A job as the queue pane shows it.
List<String> jobText(JobView job) {
  final progress = [
    if (job.fraction case final fraction?
        when job.status == JobStatusCodes.running)
      _percent(fraction),
    if (job.remainingSeconds case final seconds?) _timeLeft(seconds),
  ];
  final state = job.attempt != null && job.status == JobStatusCodes.running
      ? 'Choosing the quality, try ${job.attempt}'
      : statusWords(job.status);
  return [
    'Job ${job.id}: $state${progress.map((s) => ', $s').join()}. '
        '${job.path}',
    '  ${_recipe(job.goal, job.options)}, video ${job.videoId}'
        '${switch (job.sample) {
          SampleCodes.start => ', a sample from the start',
          SampleCodes.middle => ', a sample from the middle',
          _ => '',
        }}',
    ..._resultText(
      outputPath: job.outputPath,
      outputBytes: job.outputBytes,
      sourceBytes: job.sourceBytes,
      seconds: job.seconds,
      quality: job.quality,
      needsALook: job.needsALook,
      errorLines: job.errorLines,
    ),
  ];
}

List<String> queueText(bool busy, bool paused, List<JobView> jobs) => [
  if (jobs.isEmpty)
    paused
        ? 'The queue is empty and paused in the window.'
        : 'The queue is empty.'
  else
    'The queue is ${_queueState(busy, paused)}:',
  for (final job in jobs) ...jobText(job),
];

/// A `job.get` answer: the job as the queue pane and its (i) window show
/// it, then, when [command] was asked for, what "Show the command" gives.
List<String> jobDetailsText(
  JobView job, {
  bool command = false,
  String? commandLine,
}) => [
  ...jobText(job),
  if (job.needsALook && job.quality?.outcome == OutcomeCodes.belowTarget)
    '  Its name ends in -check: look at it beside the original.',
  if (command)
    if (commandLine == null)
      'It runs no command: nothing is converted for it.'
    else ...[
      'The command, as "Show the command" in the window gives it:',
      '  $commandLine',
    ],
];

/// A `job.compare` answer, or the line [eventText] gives for its event.
String comparedText(Object? job, Map<String, Object?> comparison) =>
    'Job $job: Compared with the original. '
    '${closenessWords(comparison['closeness'] as String)} '
    '(${_scores(comparison['vmaf'] as num?, comparison['xpsnr'] as num?).join('; ')}).';

/// A `job.compare` answer when it does not wait.
String comparingText(int job) =>
    'Job $job: Comparing with the original; `vidctrl-client compare $job` '
    'waits for the result.';

/// A `queue.add` answer.
List<String> queueAddText(Map<String, Object?> answer) {
  final added = [
    for (final job in answer['added'] as List)
      JobView.fromJson(Map<String, Object?>.from(job as Map)),
  ];
  return [
    'Goal: ${_recipe(answer['goal'] as String, Map.from(answer['options'] as Map))}.',
    for (final job in added) 'Job ${job.id}: Queued. ${job.path}',
    for (final video in answer['alreadyQueued'] as List)
      'Video $video: In the queue already, with this goal and folder.',
    for (final skipped in answer['skipped'] as List)
      switch ((skipped as Map)['reason']) {
        AddResultCodes.unreadable =>
          'Not queued, ${_video(skipped['video'])}: it cannot be read.',
        _ => 'Not queued, ${_video(skipped['video'])}: nothing found there.',
      },
    if (added.isEmpty) 'Nothing new was queued.',
  ];
}

/// A job taken out of the queue, by `queue remove` or `clear-finished`.
String takenOutText(int id) =>
    'Job $id: Taken out of the queue; any finished file stays on disk.';

List<String> clearedText(List<int> removed) => [
  if (removed.isEmpty) 'No job had finished; nothing was taken out.',
  for (final id in removed) takenOutText(id),
];

/// The queue after a job was moved, numbered by position.
List<String> movedText(List<JobView> jobs) => [
  'The queue, in order:',
  for (final (i, job) in jobs.indexed)
    '${i + 1}. Job ${job.id}: ${statusWords(job.status)}. ${job.path}',
];

String retriedText(JobView job) => 'Job ${job.id}: Queued again. ${job.path}';

String pausedText({required bool paused}) => paused
    ? 'The queue is paused: nothing new starts until it is resumed, and the '
          'job under way is held where the system allows.'
    : 'The queue goes on.';

/// A `queue.cancel` answer: the job cancelled, or the one that ended
/// otherwise before it could be.
String cancelledText(int? cancelled, {JobView? ended}) => switch ((
  cancelled,
  ended,
)) {
  (final id?, _) => 'Job $id: Cancelled; the queue goes on with the next one.',
  (null, final job?) =>
    'Job ${job.id}: Not cancelled; it ended first: '
        '${statusWords(job.status)}. ${job.path}',
  _ => 'No job is converting; nothing was cancelled.',
};

/// A `queue.convertAnyway` or `queue.convertWhole` answer.
List<String> addedJobText(Map<String, Object?> answer) {
  final added = [
    for (final job in answer['added'] as List)
      JobView.fromJson(Map<String, Object?>.from(job as Map)),
  ];
  return [
    for (final job in added) 'Job ${job.id}: Queued. ${job.path}',
    if (answer['alreadyQueued'] == true)
      'In the queue already: a job just like it is waiting or under way.',
  ];
}

String _video(Object? reference) =>
    reference is int ? 'video $reference' : '$reference';

String _recipe(String goal, Map<Object?, Object?> options) => [
  goal,
  for (final MapEntry(:key, :value) in options.entries) '$key=$value',
].join(', ');

/// How a job ended, from its [Events.jobFinished] event or a `wait`.
List<String> finishedText(JobView job) => [
  'Job ${job.id}: ${statusWords(job.status)}. ${job.path}',
  if (job.status != JobStatusCodes.removed)
    ..._resultText(
      outputPath: job.status == JobStatusCodes.done ? job.outputPath : null,
      outputBytes: job.outputBytes,
      sourceBytes: job.sourceBytes,
      seconds: job.seconds,
      quality: job.quality,
      needsALook: job.needsALook,
      errorLines: job.errorLines,
    ),
];

/// The jobs a `wait` answered without, and the command that waits on for
/// them, [goOn] being its options.
List<String> pendingText(List<PendingJob> pending, {String goOn = ''}) {
  String told(PendingJob job) {
    final progress = [
      if (job.fraction case final fraction?) _percent(fraction),
      if (job.remainingSeconds case final seconds?) _timeLeft(seconds),
    ];
    final state = switch (job.status) {
      JobStatusCodes.running when job.attempt != null =>
        'choosing the quality, try ${job.attempt}',
      JobStatusCodes.paused => 'held by a pause',
      final status => statusWords(status).toLowerCase(),
    };
    return 'job ${job.id} ${[state, ...progress].join(', ')}';
  }

  const shown = 3;
  return [
    'Not ended yet: ${[for (final job in pending.take(shown)) told(job), if (pending.length > shown) '${pending.length - shown} more'].join('; ')}.',
    'To go on: vidctrl-client wait '
        '${[for (final job in pending) job.id].join(' ')}$goOn',
  ];
}

List<String> _resultText({
  String? outputPath,
  int? outputBytes,
  int? sourceBytes,
  double? seconds,
  QualityView? quality,
  required bool needsALook,
  List<String> errorLines = const [],
}) => [
  if (outputPath != null)
    '  Result: $outputPath'
        '${outputBytes == null ? '' : ', ${_sizeText(outputBytes, sourceBytes)}'}'
        '${seconds == null ? '' : '; took ${_clock(seconds)}'}',
  if (quality != null)
    '  ${_qualityText(quality, expected: outputBytes == null)}',
  if (needsALook && quality?.outcome != OutcomeCodes.belowTarget)
    '  Worth a look by eye: its name ends in -check.',
  // FFmpeg's last words say why it failed.
  for (final line in errorLines.skip(max(0, errorLines.length - 3)))
    '  > $line',
];

/// A result's size, and its share of the original's when that is known.
String _sizeText(int bytes, int? original) => original == null || original <= 0
    ? formatBytes(bytes)
    : '${formatBytes(bytes)}, ${(bytes / original * 100).round()}% of the '
          'original\'s ${formatBytes(original)}';

/// [quality] in words; with [expected], the size it is expected to come out
/// at, until the result's own is known.
String _qualityText(QualityView quality, {required bool expected}) {
  final standard = quality.standardValue;
  final numbers = [
    if (quality.value case final value?)
      standard == null || standard == value
          ? 'crf $value'
          : 'crf $value, usual $standard',
    ..._scores(quality.vmaf, quality.xpsnr),
  ];
  final size = expected && quality.share > 0
      ? ' Expected at ${(quality.share * 100).round()}% of the original\'s '
            'size.'
      : '';
  return '${outcomeWords(quality.outcome)}'
      '${numbers.isEmpty ? '' : ' (${numbers.join('; ')})'}.$size';
}

/// One event of `events`, for people.
List<String> eventText(String event, Map<String, Object?> params) {
  Object? the(String key) => params[key];
  VideoView video() => VideoView.fromJson(params);
  JobView job() => JobView.fromJson(params);
  return switch (event) {
    Events.snapshot => [
      'Now: ${(the('videos') as List).length} videos in the list, '
          '${(the('jobs') as List).length} jobs in the queue; the queue is '
          '${_queueState(the('busy') == true, the('paused') == true)}.',
    ],
    Events.videoAdded => ['Video ${the('id')}: Added. ${the('path')}'],
    Events.videoReady || Events.videoUnreadable => [videoText(video()).first],
    Events.videoRemoved => [removedText(the('video') as int)],
    Events.jobAdded => [
      'Job ${the('id')}: Queued. ${the('path')}',
      '  ${_recipe(job().goal, job().options)}',
    ],
    Events.jobChecking => [
      'Job ${the('job')}: Choosing the quality, try ${the('attempt')}.',
    ],
    Events.jobStarted => ['Job ${the('id')}: Converting. ${the('path')}'],
    Events.jobProgress => [
      'Job ${the('job')}: ${_percent(the('fraction') as num)}'
          '${switch (the('remainingSeconds')) {
            final num seconds => ', ${_timeLeft(seconds.toDouble())}',
            _ => '',
          }}.',
    ],
    Events.jobFinished => finishedText(job()),
    Events.jobRemoved => [
      'Job ${the('job')}: ${statusWords(JobStatusCodes.removed)}.',
    ],
    Events.queuePaused => ['The queue is paused in the window.'],
    Events.queueResumed => ['The queue goes on.'],
    Events.queueIdle => ['The queue has nothing more to do.'],
    Events.compareFinished when the('status') == ComparisonCodes.measured => [
      comparedText(the('job'), params),
    ],
    Events.compareFinished => [
      'Job ${the('job')}: Could not be compared with the original.',
      for (final line in (the('errorLines') as List?) ?? const []) '  > $line',
    ],
    Events.appClosing => ['VidCtrl is closing.'],
    _ => [event],
  };
}

List<String> _scores(num? vmaf, num? xpsnr) => [
  if (vmaf != null) 'VMAF ${vmaf.toStringAsFixed(1)}',
  if (xpsnr != null) 'XPSNR ${xpsnr.toStringAsFixed(1)} dB',
];

String _percent(num fraction) => '${(fraction * 100).floor()}%';

/// `12:34`, or `1:02:03` past an hour.
String _clock(double seconds) {
  final whole = seconds.round();
  final h = whole ~/ 3600;
  final m = whole % 3600 ~/ 60;
  final s = (whole % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String _timeLeft(double seconds) {
  if (seconds < 60) return 'under a minute left';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return 'about $minutes min left';
  return 'about ${minutes ~/ 60} h ${minutes % 60} min left';
}
