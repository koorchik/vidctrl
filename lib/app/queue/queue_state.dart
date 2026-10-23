import '../../core/estimate/progress_estimator.dart';
import '../../core/ffmpeg/command_builder.dart';
import '../../core/media/media_info.dart';
import '../../core/output/output_namer.dart';
import '../../core/quality/quality_search.dart';
import '../../core/queue/job_executor.dart';
import '../../core/scenarios/scenario.dart';
import '../recipe/recipe.dart';

enum JobStatus {
  waiting,
  running,
  paused,
  done,

  /// Nothing was written: the video already met the goal, or converting
  /// would hardly make it smaller ([QueueJob.keptAsIs]).
  skipped,
  failed,
  cancelled,
}

/// One conversion in the queue. It keeps its own copy of everything it needs,
/// so later changes to the panel, or removing the video from the list, do
/// not affect it.
class QueueJob {
  const QueueJob({
    required this.id,
    required this.sourceId,
    required this.info,
    required this.recipe,
    required this.plan,
    required this.output,
    required this.outputPath,
    this.sample,
    this.status = JobStatus.waiting,
    this.progress,
    this.result,
    this.quality,
    this.attempt,
  });

  final int id;

  /// The video in the list this job was made from.
  final int sourceId;
  final MediaInfo info;
  final Recipe recipe;
  final ConversionPlan plan;
  final OutputSettings output;

  /// Where the result goes. Empty for a job that writes nothing.
  final String outputPath;

  /// The piece converted, for a sample job.
  final SampleRange? sample;
  final JobStatus status;
  final JobProgress? progress;
  final ConversionResult? result;

  /// The quality chosen for this video, once known; [plan] already uses it.
  final QualityChoice? quality;

  /// While the job measures its video before converting: 1 checks the
  /// standard quality, from 2 on better ones are tried. Null otherwise.
  final int? attempt;

  /// Whether the job is measuring its video, not converting yet.
  bool get checking => attempt != null;

  /// Left as it is: converting would hardly make it smaller.
  bool get keptAsIs => quality?.converts == false;

  /// Converted, but even the best quality fell short somewhere: worth a look
  /// before the original is deleted.
  bool get needsALook => quality?.outcome == QualityOutcome.belowTarget;

  String get path => info.path;
  bool get isSample => sample != null;
  bool get isActive =>
      status == JobStatus.running || status == JobStatus.paused;

  /// Waiting or under way.
  bool get isPending => status == JobStatus.waiting || isActive;

  /// Done one way or another; "Clear finished" removes these.
  bool get isFinished =>
      status == JobStatus.done || status == JobStatus.skipped;
  bool get canRetry =>
      status == JobStatus.failed || status == JobStatus.cancelled;

  QueueJob copyWith({
    JobStatus? status,
    JobProgress? progress,
    ConversionResult? result,
    String? outputPath,
    ConversionPlan? plan,
    QualityChoice? quality,
    int? attempt,
    bool clearAttempt = false,
    bool clearProgress = false,
  }) => QueueJob(
    id: id,
    sourceId: sourceId,
    info: info,
    recipe: recipe,
    plan: plan ?? this.plan,
    output: output,
    outputPath: outputPath ?? this.outputPath,
    sample: sample,
    status: status ?? this.status,
    progress: clearProgress ? null : progress ?? this.progress,
    result: clearProgress ? null : result ?? this.result,
    quality: quality ?? this.quality,
    attempt: clearAttempt ? null : attempt ?? this.attempt,
  );
}

class QueueState {
  const QueueState({
    this.jobs = const [],
    this.paused = false,
    this.busy = false,
  });

  final List<QueueJob> jobs;

  /// The user paused the queue: nothing new starts until they continue.
  final bool paused;

  /// Jobs are being worked through.
  final bool busy;

  QueueJob? get activeJob {
    for (final job in jobs) {
      if (job.isActive) return job;
    }
    return null;
  }

  List<QueueJob> get waiting => [
    for (final job in jobs)
      if (job.status == JobStatus.waiting) job,
  ];

  bool get hasFinished => jobs.any((job) => job.isFinished);

  QueueState copyWith({List<QueueJob>? jobs, bool? paused, bool? busy}) =>
      QueueState(
        jobs: jobs ?? this.jobs,
        paused: paused ?? this.paused,
        busy: busy ?? this.busy,
      );
}
