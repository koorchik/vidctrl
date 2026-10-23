import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/control/protocol.dart';
import '../../core/control/codes.dart';
import '../../core/control/words.dart';
import '../../core/estimate/size_estimator.dart';
import '../../core/ffmpeg/command_text.dart';
import '../../core/media/ffprobe.dart';
import '../../core/media/media_details.dart';
import '../../core/media/media_info.dart';
import '../../core/quality/quality_meter.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../../l10n/app_localizations.dart';
import '../estimates/estimate_cache.dart';
import '../home/widgets/media_details_dialog.dart';
import '../providers.dart';
import '../quality/quality_controller.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../sources/sources_controller.dart';
import 'app_views.dart';
import 'arguments.dart';
import 'events.dart';

// What the window shows about jobs and videos, for `vidctrl-client`: a
// job's row and "Show the command", "Compare with the original", "Video
// details", and the expected sizes the video list measures. Each goes
// through what the window uses for it.

/// A job as its row and (i) window show it; with `command`, what "Show the
/// command" shows, for a job that runs FFmpeg.
Future<Object?> jobGet(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = jobFrom(ref, params);
  final args = _flag(params, 'command', or: false)
      ? ref.read(queueProvider.notifier).commandFor(job)
      : null;
  return {
    'job': jobView(job, env.capabilities).toJson(),
    // As the window's command window writes it.
    'command': ?(args == null ? null : singleLineCommand('ffmpeg', args)),
  };
}

/// "Compare with the original" in a finished job's menu: one comparison at
/// a time. Asked again while that job is being compared, it waits for the
/// same comparison.
Future<Object?> jobCompare(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = jobFrom(ref, params);
  final wait = _flag(params, 'wait', or: true);
  bool comparing() => ref.read(qualityProvider)[job.id] is QualityComparing;
  if (!comparing()) {
    final quality = ref.read(qualityProvider.notifier);
    if (!quality.canCompare(job)) throw badArgument(_notComparable(job, env));
    if (quality.busy) {
      throw const ControlError(
        ControlErrorKind.busy,
        'Another job is being compared with its original; one comparison '
        'runs at a time. Ask again once it has ended.',
      );
    }
    final compared = quality.compare(job);
    if (!wait) {
      unawaited(compared);
      return {'started': true};
    }
    await compared;
  } else if (!wait) {
    return {'started': true};
  } else {
    await _until(ref, [qualityProvider], () => !comparing());
  }
  return switch (ref.read(qualityProvider)[job.id]) {
    final QualityMeasured measured => comparisonJson(job.id, measured),
    QualityFailed(:final errorLines) => throw badArgument(
      [
        'Job ${job.id} could not be compared with its original:',
        ...errorLines,
      ].join('\n'),
    ),
    _ => throw badArgument(
      'The comparison of job ${job.id} was stopped before it ended.',
    ),
  };
}

/// Why [job] cannot be compared, as the window then offers no comparison.
String _notComparable(QueueJob job, AppEnvironment env) {
  if (job.status != JobStatus.done || job.result?.outputPath == null) {
    return 'Job ${job.id} is ${statusWords(codeOf(job.status)).toLowerCase()}; '
        'only a job that is done can be compared with its original.';
  }
  if (!canComparePlan(job.plan)) {
    return 'Job ${job.id}\'s result was resized, retimed or tone mapped: its '
        'frames do not pair with the original\'s, so it cannot be compared.';
  }
  return 'This FFmpeg has no xpsnr filter, which compares a result with its '
      'original.';
}

/// "Video details" of a video in the list, or of a finished job's result.
Future<Object?> videosDetails(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final raw = _flag(params, 'raw', or: false);
  if (params['video'] != null && params['job'] != null) {
    throw badArgument('Name a video ("video") or a job ("job"), not both.');
  }
  if (params['video'] == null && params['job'] == null) {
    throw badArgument('Name a video ("video") or a job ("job").');
  }
  final MediaInfo info;
  final Map<String, Object?> view;
  if (params['video'] case final reference?) {
    final video = await _readVideo(ref, videoReference(reference));
    info = video.info!;
    view = videoView(video).toJson();
  } else {
    final job = jobFrom(ref, params);
    final output = job.result?.outputPath;
    if (job.status != JobStatus.done || output == null) {
      throw ControlError(
        ControlErrorKind.notFound,
        'Job ${job.id} has no result: it is '
        '${statusWords(codeOf(job.status)).toLowerCase()}.',
      );
    }
    try {
      info = await env.ffprobe.probe(output);
    } on FfprobeException {
      throw ControlError(
        ControlErrorKind.notFound,
        'The result of job ${job.id} cannot be read at $output.',
      );
    }
    view = resultView(job, info).toJson();
  }
  return {
    'info': view,
    if (raw) 'raw': info.raw else 'details': _details(info.raw),
  };
}

/// [reference]'s video in the list once read; refused when it is not a
/// video FFmpeg can open.
Future<SourceVideo> _readVideo(Ref ref, Object reference) async {
  SourceVideo? find() => findVideo(ref.read(sourcesProvider), reference);
  if (find()?.status == SourceStatus.probing) {
    await ref.read(sourcesProvider.notifier).settled;
  }
  final video = find();
  if (video == null) {
    throw ControlError(
      ControlErrorKind.notFound,
      'There is no video $reference in the list.',
    );
  }
  if (!video.isReady) {
    throw badArgument(
      'Video ${video.id} cannot be read: it is not a video FFmpeg can open.',
    );
  }
  return video;
}

/// The window's "Video details" in English: each track, then the file, each
/// by its kind's code and its number among that kind.
List<Map<String, Object?>> _details(Map<String, Object?> raw) {
  final l10n = lookupAppLocalizations(const Locale('en'));
  return [
    for (final section in orderedDetails(encodingDetails(raw)))
      {
        'group': codeOf(section.group),
        'number': section.number,
        'title': groupTitle(l10n, section.group, section.number),
        'rows': [
          for (final row in section.rows)
            [fieldLabel(l10n, row.field), rowValue(l10n, row)],
        ],
      },
  ];
}

const _converting = ControlError(
  ControlErrorKind.busy,
  'Videos are being converted; the window measures when the queue is idle.',
);

/// Measures the expected sizes of videos in the list with a goal, as
/// selecting them in the window does: only while the queue is idle, one
/// video at a time. The answer is the list's preview of each.
Future<Object?> videosEstimate(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  if (ref.read(queueProvider).busy) throw _converting;
  final recipe = recipeFrom(ref, params, env.capabilities);
  final videos = <SourceVideo>[];
  for (final reference in listParam(params, 'videos')) {
    final video = await _readVideo(ref, videoReference(reference));
    if (!videos.any((v) => v.id == video.id)) videos.add(video);
  }
  final preset = findPreset(recipe.presetId)!;
  final raise = switch (preset) {
    final RaisesQuality raises => raises,
    _ => null,
  };
  final estimates = ref.read(estimateCacheProvider.notifier);
  for (final video in videos) {
    final info = video.info!;
    final plan = preset.plan(info, recipe.values, env.capabilities);
    // Known without measuring, or nothing to measure: as the list does.
    if (estimateWithoutEncoding(info, plan) != null ||
        !plan.producesOutput ||
        plan.video is! VideoEncode) {
      continue;
    }
    final key = estimateKey(video.path, recipe);
    bool converting() => ref.read(queueProvider).busy;
    bool measuring() => ref.read(estimateCacheProvider).measuring.contains(key);
    // No more FFmpeg at once than the window would run.
    await _until(ref, [
      estimateCacheProvider,
      queueProvider,
    ], () => converting() || measuring() || estimates.room(plan) > 0);
    if (converting()) throw _converting;
    await estimates.measure(key, info, plan, raise: raise);
    // The window may have been measuring it already.
    await _until(ref, [estimateCacheProvider], () => !measuring());
    // Converting stops measuring: what it left unmeasured is not known.
    if (converting()) throw _converting;
  }
  return {
    'videos': [
      for (final video in videos)
        videoView(
          video,
          preview: goalPreview(ref, env, video, recipe),
        ).toJson(),
    ],
  };
}

/// Whether [params] says yes to [key]; [or] when it says nothing.
bool _flag(Map<String, Object?> params, String key, {required bool or}) {
  final value = params[key] ?? or;
  if (value is! bool) throw badArgument('"$key" is true or false.');
  return value;
}

/// Completes once [done], checked whenever one of [providers] changes.
Future<void> _until(
  Ref ref,
  List<ProviderListenable<Object?>> providers,
  bool Function() done,
) {
  if (done()) return Future.value();
  final reached = Completer<void>();
  final subscriptions = <ProviderSubscription<Object?>>[];
  void check(Object? _, Object? _) {
    if (reached.isCompleted || !done()) return;
    for (final subscription in subscriptions) {
      subscription.close();
    }
    reached.complete();
  }

  for (final provider in providers) {
    subscriptions.add(ref.listen<Object?>(provider, check));
  }
  return reached.future;
}
