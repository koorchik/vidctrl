import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/listener.dart';
import '../../core/control/protocol.dart';
import '../../core/control/views.dart';
import '../../core/estimate/size_estimator.dart';
import '../../core/scenarios/registry.dart';
import '../../l10n/app_localizations.dart';
import '../build_info.dart';
import '../estimates/estimate_cache.dart';
import '../home/scenario_texts.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../recipe/recipe.dart';
import '../sources/sources_controller.dart';
import 'app_views.dart';
import 'arguments.dart';

// What the window does for each request of `vidctrl-client`. Every method
// works through the notifiers the window's own buttons use, so the window
// shows what a client did; none changes the panel.

typedef _Method = Future<Object?> Function(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
);

const _methods = <String, _Method>{
  Methods.goals: _goals,
  Methods.videosAdd: _videosAdd,
  Methods.videosList: _videosList,
  Methods.videosRemove: _videosRemove,
  Methods.queueList: _queueList,
  Methods.queueAdd: _queueAdd,
};

/// Answers one request. `status` answers at once; every other method waits
/// until FFmpeg has been looked for, and fails when it was not found.
Future<Object?> handleControl(
  Ref ref,
  String method,
  Map<String, Object?> params,
  ControlPeer peer,
) async {
  if (method == Methods.status) return _status(ref);
  final answer = _methods[method];
  if (answer == null) {
    throw ControlError(
      ControlErrorKind.unknownMethod,
      'VidCtrl knows no method "$method".',
    );
  }
  final AppEnvironment env;
  try {
    env = await ref.read(environmentProvider.future);
  } on Object {
    // The window shows its "engine missing" screen for any failure here.
    throw const ControlError(
      ControlErrorKind.ffmpegMissing,
      'VidCtrl could not find FFmpeg; the window says what to do.',
    );
  }
  return answer(ref, env, params);
}

// ---- Status and goals ---------------------------------------------------

Map<String, Object?> _status(Ref ref) {
  final environment = ref.read(environmentProvider);
  final version = ref.read(buildInfoProvider).version;
  if (!environment.hasValue) {
    return StatusView(
      state: environment.hasError ? 'ffmpegMissing' : 'starting',
      version: version,
      busy: false,
      paused: false,
      jobs: const {},
    ).toJson();
  }
  final queue = ref.read(queueProvider);
  final counts = <String, int>{};
  for (final job in queue.jobs) {
    counts.update(job.status.name, (n) => n + 1, ifAbsent: () => 1);
  }
  return StatusView(
    state: 'ready',
    version: version,
    busy: queue.busy,
    paused: queue.paused,
    jobs: counts,
  ).toJson();
}

Future<Object?> _goals(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final l10n = lookupAppLocalizations(const Locale('en'));
  return {
    'goals': [
      for (final scenario in scenarios)
        for (final preset in scenario.presets)
          GoalView(
            id: preset.id,
            scenario: scenario.id,
            title: scenarioTitle(l10n, scenario.id),
            // Resolve's two are told apart as on the panel's tile.
            subtitle: scenario.presets.length > 1
                ? presetTitle(l10n, preset.id)
                : scenarioSubtitle(l10n, scenario.id),
            options: [
              for (final option in preset.options)
                if (optionOffered(preset, option, env.capabilities))
                  OptionView(
                    id: option.id,
                    title: optionTitle(l10n, preset.id, option.id),
                    defaultChoice: option.defaultChoice,
                    advanced: option.advanced,
                    choices: [
                      for (final choice in option.choices)
                        ChoiceView(
                          id: choice,
                          label: choiceLabel(l10n, preset.id, choice),
                          hint: choiceHint(l10n, option.id, choice),
                        ),
                    ],
                  ),
            ],
          ).toJson(),
    ],
  };
}

// ---- Videos -------------------------------------------------------------

Future<Object?> _videosAdd(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final paths = [
    for (final path in listParam(params, 'paths')) absolutePath(path, 'paths'),
  ];
  final entries = await _addPaths(ref, paths, wait: params['wait'] != false);
  if (entries.every((e) => e.id == null)) {
    throw badArgument(
      'Nothing could be added: there is no file, nor a folder with videos, '
      'at ${paths.join(', ')}.',
    );
  }
  return {
    'videos': [for (final e in entries) e.toJson()],
  };
}

/// What adding one path gave: a video in the list, or nothing found there.
class _Added {
  const _Added(this.given, this.path, this.result, [this.id]);

  /// The path as asked for: the file, or the folder it was found in.
  final String given;
  final String path;

  /// added, known (listed before), notFound or unreadable.
  final String result;
  final int? id;

  Map<String, Object?> toJson() => {'path': path, 'id': ?id, 'result': result};
}

/// Adds [paths] to the list as a drop does: folders give the videos inside
/// them, and each file is listed once. Paths where nothing is are not passed
/// on. With [wait], every video is inspected before this returns.
Future<List<_Added>> _addPaths(
  Ref ref,
  List<String> paths, {
  required bool wait,
}) async {
  final sources = ref.read(sourcesProvider.notifier);
  final before = {for (final v in ref.read(sourcesProvider).videos) v.id};
  final existing = <String>{};
  for (final path in paths) {
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      existing.add(path);
    }
  }
  final ids = existing.isEmpty
      ? const <int>[]
      : await sources.addPaths(existing, waitForProbes: wait);
  if (wait) await sources.settled;
  final state = ref.read(sourcesProvider);
  final videos = {for (final id in ids) id: ?state.byId(id)};
  final reported = <int>{};
  final entries = <_Added>[];
  for (final given in paths) {
    var found = false;
    for (final video in videos.values) {
      if (video.path != given && !p.isWithin(given, video.path)) continue;
      found = true;
      if (!reported.add(video.id)) continue;
      final result = video.status == SourceStatus.unreadable
          ? 'unreadable'
          : before.contains(video.id)
          ? 'known'
          : 'added';
      entries.add(_Added(given, video.path, result, video.id));
    }
    // A folder with no videos in it counts as nothing there.
    if (!found) entries.add(_Added(given, given, 'notFound'));
  }
  return entries;
}

Future<Object?> _videosList(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  if (params['goal'] == null && params['options'] != null) {
    throw badArgument('Options go with a goal.');
  }
  final recipe = params['goal'] == null
      ? null
      : recipeFrom(ref, params, env.capabilities);
  return {
    'videos': [
      for (final video in ref.read(sourcesProvider).videos)
        videoView(
          video,
          preview: recipe == null || !video.isReady
              ? null
              : _preview(ref, env, video, recipe),
        ).toJson(),
    ],
  };
}

/// What [recipe] would do to [video], as the video list shows it.
GoalPreview _preview(
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

Future<Object?> _videosRemove(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final state = ref.read(sourcesProvider);
  final ids = <int>{};
  for (final reference in listParam(params, 'videos')) {
    final video = findVideo(state, videoReference(reference));
    if (video == null) {
      throw ControlError(
        ControlErrorKind.notFound,
        'There is no video $reference in the list.',
      );
    }
    ids.add(video.id);
  }
  final sources = ref.read(sourcesProvider.notifier);
  for (final id in ids) {
    sources.remove(id);
  }
  return {'removed': ids.toList()};
}

// ---- Queue --------------------------------------------------------------

Future<Object?> _queueList(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final queue = ref.read(queueProvider);
  return {
    'paused': queue.paused,
    'busy': queue.busy,
    'jobs': [for (final job in queue.jobs) jobView(job).toJson()],
  };
}

/// Queues videos as Add to queue does, with the panel's goal unless another
/// is named; whole videos unless a sample is asked for, whatever the panel
/// says.
Future<Object?> _queueAdd(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  // Everything is checked before anything is added.
  final recipe = recipeFrom(ref, params, env.capabilities, withSample: true);
  final output = outputFrom(ref, params);
  final references = [
    for (final reference in listParam(params, 'videos'))
      videoReference(reference),
  ];
  final listed = ref.read(sourcesProvider);
  for (final reference in references) {
    if (reference is int && listed.byId(reference) == null) {
      throw ControlError(
        ControlErrorKind.notFound,
        'There is no video $reference in the list.',
      );
    }
  }
  final newPaths = [
    for (final reference in references)
      if (reference is String && findVideo(listed, reference) == null)
        reference,
  ];
  final added = newPaths.isEmpty
      ? const <_Added>[]
      : await _addPaths(ref, newPaths, wait: true);

  final sources = ref.read(sourcesProvider.notifier);
  final skipped = <Map<String, Object?>>[];
  final ids = <int>[];
  for (final reference in references) {
    if (reference is String && newPaths.contains(reference)) {
      for (final entry in added.where((e) => e.given == reference)) {
        if (entry.id case final id?) {
          ids.add(id);
        } else {
          skipped.add({'video': reference, 'reason': 'notFound'});
        }
      }
    } else {
      ids.add(findVideo(listed, reference)!.id);
    }
  }
  if (ids.any(
    (id) => ref.read(sourcesProvider).byId(id)?.status == SourceStatus.probing,
  )) {
    await sources.settled;
  }
  final state = ref.read(sourcesProvider);
  final ready = <SourceVideo>[];
  for (final id in ids) {
    final video = state.byId(id);
    if (video == null) {
      // Taken off the list meanwhile.
      skipped.add({'video': id, 'reason': 'notFound'});
    } else if (!video.isReady) {
      skipped.add({'video': id, 'reason': 'unreadable'});
    } else {
      ready.add(video);
    }
  }
  final result = ref
      .read(queueProvider.notifier)
      .addVideos(ready, recipe: recipe, output: output);
  return {
    'goal': recipe.presetId,
    'options': appliedOptions(recipe),
    'added': [for (final job in result.added) jobView(job).toJson()],
    'alreadyQueued': result.alreadyQueued,
    'skipped': skipped,
  };
}
