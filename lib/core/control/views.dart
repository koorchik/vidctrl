import 'codes.dart';

// The shapes the window sends and the client prints. In JSON the keys are
// the field names and an absent value is left out, never null. A value that
// is one of a few is a code of codes.dart, never words, nor the window's
// labels: the client's words for people are in words.dart, and the goals'
// in manual_words.g.dart.

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

  /// A [VideoStatusCodes] code.
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

  /// A [PlanCodes] code.
  final String plan;
  final int? expectedBytes;
  final bool measured;
  final bool measuring;

  /// A [ClosenessCodes] code.
  final String? closeness;

  Map<String, Object?> toJson() => {
    'goal': goal,
    'plan': plan,
    'expectedBytes': ?expectedBytes,
    'measured': measured,
    'measuring': measuring,
    'closeness': ?closeness,
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

  /// A [SampleCodes] code, for a sample.
  final String? sample;

  /// A [JobStatusCodes] code.
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

  /// An [OutcomeCodes] code.
  final String outcome;
  final int? value;
  final int? standardValue;
  final double? vmaf;
  final double? xpsnr;
  final double share;

  Map<String, Object?> toJson() => {
    'outcome': outcome,
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

  /// A [StateCodes] code.
  final String state;
  final String version;
  final bool busy;
  final bool paused;

  /// How many jobs there are in each status, by [JobStatusCodes] code.
  final Map<String, int> jobs;

  Map<String, Object?> toJson() => {
    'state': state,
    'version': version,
    'busy': busy,
    'paused': paused,
    'jobs': jobs,
  };
}

/// A goal by its ids; its words, and what its options and choices mean,
/// are in the manual.
class GoalView {
  const GoalView({
    required this.id,
    required this.scenario,
    required this.options,
  });

  factory GoalView.fromJson(Map<String, Object?> json) => GoalView(
    id: json['id'] as String,
    scenario: json['scenario'] as String,
    options: [
      for (final o in (json['options'] as List?) ?? const [])
        OptionView.fromJson(_map(o)),
    ],
  );

  /// The preset id.
  final String id;

  /// The scenario id.
  final String scenario;
  final List<OptionView> options;

  Map<String, Object?> toJson() => {
    'id': id,
    'scenario': scenario,
    'options': [for (final o in options) o.toJson()],
  };
}

class OptionView {
  const OptionView({
    required this.id,
    required this.defaultChoice,
    required this.advanced,
    required this.choices,
  });

  factory OptionView.fromJson(Map<String, Object?> json) => OptionView(
    id: json['id'] as String,
    defaultChoice: json['defaultChoice'] as String,
    advanced: json['advanced'] as bool? ?? false,
    choices: _strings(json['choices']),
  );

  final String id;
  final String defaultChoice;
  final bool advanced;

  /// The choices' ids, as `--opt` takes them.
  final List<String> choices;

  Map<String, Object?> toJson() => {
    'id': id,
    'defaultChoice': defaultChoice,
    'advanced': advanced,
    'choices': choices,
  };
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

  /// A [JobStatusCodes] code: done, skipped, failed, cancelled or removed.
  final String status;
  final String? outputPath;
  final bool needsALook;

  Map<String, Object?> toJson() => {
    'jobId': jobId,
    'path': path,
    'status': status,
    'outputPath': ?outputPath,
    'needsALook': needsALook,
  };
}
