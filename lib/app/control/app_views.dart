import '../../core/control/views.dart';
import '../../core/quality/quality_search.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../queue/queue_state.dart';
import '../recipe/recipe.dart';
import '../sources/sources_controller.dart';

// The window's state in the shapes a client reads.

VideoView videoView(SourceVideo video, {GoalPreview? preview}) {
  final info = video.info;
  final picture = info?.video;
  return VideoView(
    id: video.id,
    path: video.path,
    status: video.status.name,
    sizeBytes: info?.sizeBytes,
    durationSeconds: info == null ? null : _seconds(info.duration),
    width: picture?.width,
    height: picture?.height,
    videoCodec: picture?.codec,
    audioCodecs: [for (final track in info?.audio ?? const []) track.codec],
    hdr: picture?.color.isHdr ?? false,
    preview: preview,
  );
}

JobView jobView(QueueJob job) {
  final progress = job.isActive ? job.progress : null;
  final remaining = progress?.remaining;
  final result = job.result;
  return JobView(
    id: job.id,
    videoId: job.sourceId,
    path: job.path,
    goal: job.recipe.presetId,
    options: appliedOptions(job.recipe),
    sample: job.recipe.isSample ? job.recipe.sample.name : null,
    status: job.status.name,
    fraction: progress?.fraction,
    remainingSeconds: remaining == null ? null : _seconds(remaining),
    attempt: job.attempt,
    outputPath: job.outputPath.isEmpty ? null : job.outputPath,
    outputBytes: result?.outputBytes,
    quality: switch (job.quality) {
      final choice? => _qualityView(choice),
      null => null,
    },
    needsALook: job.needsALook,
    errorLines: result?.errorLines ?? const [],
  );
}

QualityView _qualityView(QualityChoice choice) => QualityView(
  outcome: choice.outcome.name,
  value: choice.value,
  standardValue: choice.standardValue,
  vmaf: choice.chosen.score.vmaf,
  xpsnr: choice.chosen.score.lumaDb,
  share: choice.share,
);

double _seconds(Duration d) => d.inMilliseconds / 1000;

/// Every option of [recipe]'s goal, as its preset applies them.
Map<String, String> appliedOptions(Recipe recipe) {
  final preset = findPreset(recipe.presetId)!;
  return {
    for (final option in preset.options)
      option.id: preset.choice(recipe.values, option.id),
  };
}
