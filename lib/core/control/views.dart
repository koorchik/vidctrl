import 'words.dart';

// The shapes the window sends and the client prints. In JSON the keys are
// the field names and an absent value is left out, never null. The `...Text`
// keys beside some ids carry the English words; reading them back ignores
// them.

T? _opt<T>(Map<String, Object?> json, String key) => json[key] as T?;

double? _double(Map<String, Object?> json, String key) =>
    (json[key] as num?)?.toDouble();

List<String> _strings(Object? value) => [
  for (final item in (value as List?) ?? const []) item as String,
];

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value as Map);

class VideoView {
  const VideoView({
    required this.id,
    required this.path,
    required this.status,
    required this.audioCodecs,
    required this.hdr,
    this.sizeBytes,
    this.durationSeconds,
    this.width,
    this.height,
    this.videoCodec,
    this.preview,
  });

  factory VideoView.fromJson(Map<String, Object?> json) => VideoView(
    id: json['id'] as int,
    path: json['path'] as String,
    status: json['status'] as String,
    sizeBytes: _opt<int>(json, 'sizeBytes'),
    durationSeconds: _double(json, 'durationSeconds'),
    width: _opt<int>(json, 'width'),
    height: _opt<int>(json, 'height'),
    videoCodec: _opt<String>(json, 'videoCodec'),
    audioCodecs: _strings(json['audioCodecs']),
    hdr: json['hdr'] as bool? ?? false,
    preview: json['preview'] == null
        ? null
        : GoalPreview.fromJson(_map(json['preview'])),
  );

  final int id;
  final String path;

  /// probing, ready or unreadable.
  final String status;
  final int? sizeBytes;
  final double? durationSeconds;
  final int? width;
  final int? height;
  final String? videoCodec;
  final List<String> audioCodecs;
  final bool hdr;
  final GoalPreview? preview;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'status': status,
    'statusText': statusWords(status),
    'sizeBytes': ?sizeBytes,
    'durationSeconds': ?durationSeconds,
    'width': ?width,
    'height': ?height,
    'videoCodec': ?videoCodec,
    'audioCodecs': audioCodecs,
    'hdr': hdr,
    'preview': ?preview?.toJson(),
  };
}

class GoalPreview {
  const GoalPreview({
    required this.goal,
    required this.plan,
    required this.measured,
    required this.measuring,
    this.expectedBytes,
    this.closeness,
  });

  factory GoalPreview.fromJson(Map<String, Object?> json) => GoalPreview(
    goal: json['goal'] as String,
    plan: json['plan'] as String,
    expectedBytes: _opt<int>(json, 'expectedBytes'),
    measured: json['measured'] as bool? ?? false,
    measuring: json['measuring'] as bool? ?? false,
    closeness: _opt<String>(json, 'closeness'),
  );

  /// The preset id.
  final String goal;

  /// skip, remux, audioOnly, encode, unsupported or keptAsIs.
  final String plan;
  final int? expectedBytes;
  final bool measured;
  final bool measuring;

  /// same, veryClose or differs.
  final String? closeness;

  Map<String, Object?> toJson() => {
    'goal': goal,
    'plan': plan,
    'planText': planWords(plan),
    'expectedBytes': ?expectedBytes,
    'measured': measured,
    'measuring': measuring,
    'closeness': ?closeness,
    'closenessText': ?(closeness == null ? null : closenessWords(closeness!)),
  };
}

class JobView {
  const JobView({
    required this.id,
    required this.videoId,
    required this.path,
    required this.goal,
    required this.options,
    required this.status,
    required this.needsALook,
    required this.errorLines,
    this.sample,
    this.fraction,
    this.remainingSeconds,
    this.attempt,
    this.outputPath,
    this.outputBytes,
    this.quality,
  });

  factory JobView.fromJson(Map<String, Object?> json) => JobView(
    id: json['id'] as int,
    videoId: json['videoId'] as int,
    path: json['path'] as String,
    goal: json['goal'] as String,
    options: {
      for (final e in _map(json['options']).entries) e.key: e.value as String,
    },
    sample: _opt<String>(json, 'sample'),
    status: json['status'] as String,
    fraction: _double(json, 'fraction'),
    remainingSeconds: _double(json, 'remainingSeconds'),
    attempt: _opt<int>(json, 'attempt'),
    outputPath: _opt<String>(json, 'outputPath'),
    outputBytes: _opt<int>(json, 'outputBytes'),
    quality: json['quality'] == null
        ? null
        : QualityView.fromJson(_map(json['quality'])),
    needsALook: json['needsALook'] as bool? ?? false,
    errorLines: _strings(json['errorLines']),
  );

  final int id;
  final int videoId;
  final String path;
  final String goal;
  final Map<String, String> options;

  /// start or middle, for a sample.
  final String? sample;

  /// A `JobStatus` name.
  final String status;
  final double? fraction;
  final double? remainingSeconds;
  final int? attempt;
  final String? outputPath;
  final int? outputBytes;
  final QualityView? quality;
  final bool needsALook;
  final List<String> errorLines;

  Map<String, Object?> toJson() => {
    'id': id,
    'videoId': videoId,
    'path': path,
    'goal': goal,
    'options': options,
    'sample': ?sample,
    'status': status,
    'statusText': statusWords(status),
    'fraction': ?fraction,
    'remainingSeconds': ?remainingSeconds,
    'attempt': ?attempt,
    'outputPath': ?outputPath,
    'outputBytes': ?outputBytes,
    'quality': ?quality?.toJson(),
    'needsALook': needsALook,
    'errorLines': errorLines,
  };
}

class QualityView {
  const QualityView({
    required this.outcome,
    required this.share,
    this.value,
    this.standardValue,
    this.vmaf,
    this.xpsnr,
  });

  factory QualityView.fromJson(Map<String, Object?> json) => QualityView(
    outcome: json['outcome'] as String,
    value: _opt<int>(json, 'value'),
    standardValue: _opt<int>(json, 'standardValue'),
    vmaf: _double(json, 'vmaf'),
    xpsnr: _double(json, 'xpsnr'),
    share: _double(json, 'share') ?? 0,
  );

  /// A `QualityOutcome` name.
  final String outcome;
  final int? value;
  final int? standardValue;
  final double? vmaf;
  final double? xpsnr;
  final double share;

  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'outcomeText': outcomeWords(outcome),
    'value': ?value,
    'standardValue': ?standardValue,
    'vmaf': ?vmaf,
    'xpsnr': ?xpsnr,
    'share': share,
  };
}

class StatusView {
  const StatusView({
    required this.state,
    required this.version,
    required this.busy,
    required this.paused,
    required this.jobs,
  });

  factory StatusView.fromJson(Map<String, Object?> json) => StatusView(
    state: json['state'] as String,
    version: json['version'] as String,
    busy: json['busy'] as bool? ?? false,
    paused: json['paused'] as bool? ?? false,
    jobs: {for (final e in _map(json['jobs']).entries) e.key: e.value as int},
  );

  /// starting, ready or ffmpegMissing.
  final String state;
  final String version;
  final bool busy;
  final bool paused;

  /// How many jobs there are in each status.
  final Map<String, int> jobs;

  Map<String, Object?> toJson() => {
    'state': state,
    'version': version,
    'busy': busy,
    'paused': paused,
    'jobs': jobs,
  };
}

class GoalView {
  const GoalView({
    required this.id,
    required this.scenario,
    required this.title,
    required this.subtitle,
    required this.options,
  });

  factory GoalView.fromJson(Map<String, Object?> json) => GoalView(
    id: json['id'] as String,
    scenario: json['scenario'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String? ?? '',
    options: [
      for (final o in (json['options'] as List?) ?? const [])
        OptionView.fromJson(_map(o)),
    ],
  );

  final String id;
  final String scenario;
  final String title;
  final String subtitle;
  final List<OptionView> options;

  Map<String, Object?> toJson() => {
    'id': id,
    'scenario': scenario,
    'title': title,
    'subtitle': subtitle,
    'options': [for (final o in options) o.toJson()],
  };
}

class OptionView {
  const OptionView({
    required this.id,
    required this.title,
    required this.defaultChoice,
    required this.advanced,
    required this.choices,
  });

  factory OptionView.fromJson(Map<String, Object?> json) => OptionView(
    id: json['id'] as String,
    title: json['title'] as String,
    defaultChoice: json['defaultChoice'] as String,
    advanced: json['advanced'] as bool? ?? false,
    choices: [
      for (final c in (json['choices'] as List?) ?? const [])
        ChoiceView.fromJson(_map(c)),
    ],
  );

  final String id;
  final String title;
  final String defaultChoice;
  final bool advanced;
  final List<ChoiceView> choices;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'defaultChoice': defaultChoice,
    'advanced': advanced,
    'choices': [for (final c in choices) c.toJson()],
  };
}

class ChoiceView {
  const ChoiceView({required this.id, required this.label, required this.hint});

  factory ChoiceView.fromJson(Map<String, Object?> json) => ChoiceView(
    id: json['id'] as String,
    label: json['label'] as String,
    hint: json['hint'] as String? ?? '',
  );

  final String id;
  final String label;
  final String hint;

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'hint': hint};
}

/// How a job ended, as `wait` reports it.
class JobOutcome {
  const JobOutcome({
    required this.jobId,
    required this.path,
    required this.status,
    required this.needsALook,
    this.outputPath,
  });

  factory JobOutcome.fromJson(Map<String, Object?> json) => JobOutcome(
    jobId: json['jobId'] as int,
    path: json['path'] as String,
    status: json['status'] as String,
    outputPath: _opt<String>(json, 'outputPath'),
    needsALook: json['needsALook'] as bool? ?? false,
  );

  final int jobId;
  final String path;

  /// done, skipped, failed, cancelled or removed.
  final String status;
  final String? outputPath;
  final bool needsALook;

  Map<String, Object?> toJson() => {
    'jobId': jobId,
    'path': path,
    'status': status,
    'statusText': statusWords(status),
    'outputPath': ?outputPath,
    'needsALook': needsALook,
  };
}
