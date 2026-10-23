import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/control/views.dart';
import '../../core/estimate/size_estimator.dart';
import '../../core/ffmpeg/capabilities.dart';
import '../../core/media/media_info.dart';
import '../../core/quality/quality_search.dart';
import '../../core/scenarios/archive.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../estimates/estimate_cache.dart';
import '../providers.dart';
import '../queue/queue_state.dart';
import '../recipe/recipe.dart';
import '../sources/sources_controller.dart';

// The window's state in the shapes a client reads.

VideoView videoView(SourceVideo video, {GoalPreview? preview}) => _videoView(
  video.id,
  video.path,
  video.status.name,
  video.info,
  preview: preview,
);

/// The result of [job], read as [info], in the shape of a video: its id is
/// that of the video the job was made from.
VideoView resultView(QueueJob job, MediaInfo info) =>
    _videoView(job.sourceId, info.path, 'ready', info);

VideoView _videoView(
  int id,
  String path,
  String status,
  MediaInfo? info, {
  GoalPreview? preview,
}) {
  final picture = info?.video;
  return VideoView(
    id: id,
    path: path,
    status: status,
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

/// [job] as a client reads it, its options as they are applied with
/// [capabilities].
JobView jobView(QueueJob job, Capabilities capabilities) {
  final progress = job.isActive ? job.progress : null;
  final remaining = progress?.remaining;
  final result = job.result;
  return JobView(
    id: job.id,
    videoId: job.sourceId,
    path: job.path,
    goal: job.recipe.presetId,
    options: appliedOptions(job.recipe, capabilities),
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

/// What [recipe] would do to [video], as the video list shows it.
GoalPreview goalPreview(
  Ref ref,
  AppEnvironment env,
  SourceVideo video,
  Recipe recipe,
) {
  final info = video.info!;
  final plan = findPreset(recipe.presetId)!
      .plan(info, recipe.values, env.capabilities);
  final cache = ref.read(estimateCacheProvider);
  final key = estimateKey(video.path, recipe);
  final estimate = estimateWithoutEncoding(info, plan) ?? cache.estimates[key];
  return GoalPreview(
    goal: recipe.presetId,
    plan: estimate?.choice?.converts == false ? 'keptAsIs' : plan.kind.name,
    expectedBytes: estimate?.bytes,
    measured: estimate?.measured ?? false,
    measuring: cache.measuring.contains(key),
    closeness: estimate?.quality?.closeness.name,
  );
}

double _seconds(Duration d) => d.inMilliseconds / 1000;

/// Every option of [recipe]'s goal, with the choice its preset makes on a
/// computer with [capabilities].
Map<String, String> appliedOptions(Recipe recipe, Capabilities capabilities) {
  final preset = findPreset(recipe.presetId)!;
  return {
    for (final option in preset.options)
      option.id: appliedChoice(preset, option.id, recipe.values, capabilities),
  };
}

/// The choice [preset] really makes for [optionId] with [values] on a
/// computer with [capabilities]: the archive writes HEVC where this FFmpeg
/// cannot make AV1, and uses the processor where the graphics card cannot
/// encode that format. Otherwise the choice given, or the default.
String appliedChoice(
  Preset preset,
  String optionId,
  OptionValues values,
  Capabilities capabilities,
) {
  final chosen = preset.choice(values, optionId);
  if (preset is! ArchivePreset) return chosen;
  final format = ArchivePreset.formatFor(values, capabilities);
  return switch (optionId) {
    ArchivePreset.codec => format,
    ArchivePreset.speed
        when ArchivePreset.gpuEncoder(capabilities, format) == null =>
      'cpu',
    _ => chosen,
  };
}
