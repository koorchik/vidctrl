import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/listener.dart';
import '../../core/control/protocol.dart';
import '../../core/control/views.dart';
import '../../core/estimate/size_estimator.dart';
import '../../core/ffmpeg/capabilities.dart';
import '../../core/output/output_namer.dart';
import '../../core/quality/quality_search.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../../l10n/app_localizations.dart';
import '../build_info.dart';
import '../estimates/estimate_cache.dart';
import '../home/scenario_texts.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../recipe/recipe.dart';
import '../recipe/recipe_controller.dart';
import '../sources/sources_controller.dart';

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
                if (_offered(preset, option, env.capabilities))
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

/// Whether the panel shows [option], with the goal's defaults or with one
/// other option changed: the archive's speed row appears only once HEVC is
/// chosen on a computer whose graphics card makes HEVC alone. An option this
/// computer cannot use at all is never shown.
bool _offered(Preset preset, PresetOption option, Capabilities capabilities) {
  bool shownWith(OptionValues values) =>
      optionVisible(preset, option, values, capabilities) ||
      advancedOptionVisible(preset, option, values);
  if (shownWith(const {})) return true;
  for (final other in preset.options) {
    for (final choice in other.choices) {
      if (shownWith({other.id: choice})) return true;
    }
  }
  return false;
}

// ---- Videos -------------------------------------------------------------

Future<Object?> _videosAdd(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final paths = [
    for (final path in _items(params, 'paths')) _absolute(path, 'paths'),
  ];
  final entries = await _addPaths(ref, paths, wait: params['wait'] != false);
  if (entries.every((e) => e.id == null)) {
    throw _bad(
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
    throw _bad('Options go with a goal.');
  }
  final recipe = params['goal'] == null ? null : _recipe(ref, params);
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
  for (final reference in _items(params, 'videos')) {
    final video = _video(state, _reference(reference));
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
  final recipe = _recipe(ref, params, withSample: true);
  final output = _output(ref, params);
  final references = [
    for (final reference in _items(params, 'videos')) _reference(reference),
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
      if (reference is String && _video(listed, reference) == null) reference,
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
      ids.add(_video(listed, reference)!.id);
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
    'options': _applied(recipe),
    'added': [for (final job in result.added) jobView(job).toJson()],
    'alreadyQueued': result.alreadyQueued,
    'skipped': skipped,
  };
}

// ---- Views --------------------------------------------------------------

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
    options: _applied(job.recipe),
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
Map<String, String> _applied(Recipe recipe) {
  final preset = findPreset(recipe.presetId)!;
  return {
    for (final option in preset.options)
      option.id: preset.choice(recipe.values, option.id),
  };
}

// ---- Arguments ----------------------------------------------------------

ControlError _bad(String message) =>
    ControlError(ControlErrorKind.badArgument, message);

List<Object?> _items(Map<String, Object?> params, String key) {
  final items = params[key];
  if (items is! List || items.isEmpty) {
    throw _bad('"$key" must be a list with at least one item.');
  }
  return items;
}

String _absolute(Object? path, String key) {
  if (path is! String || !p.isAbsolute(path)) {
    throw _bad('"$key" takes absolute paths; "$path" is not one.');
  }
  return p.normalize(path);
}

/// A video's id, or its path made plain.
Object _reference(Object? reference) =>
    reference is int ? reference : _absolute(reference, 'videos');

SourceVideo? _video(SourcesState state, Object reference) {
  if (reference is int) return state.byId(reference);
  for (final video in state.videos) {
    if (p.normalize(video.path) == reference) return video;
  }
  return null;
}

/// The goal and options asked for in [params], or the panel's goal and
/// options where no goal is named; options given then change the panel's.
/// The panel itself is left as it is.
Recipe _recipe(
  Ref ref,
  Map<String, Object?> params, {
  bool withSample = false,
}) {
  final goal = params['goal'];
  final panel = ref.read(recipeProvider).recipe;
  final preset = goal == null ? findPreset(panel.presetId)! : _preset(goal);
  return Recipe(
    presetId: preset.id,
    values: {
      if (goal == null) ...panel.values,
      ..._options(preset, params['options']),
    },
    sample: withSample ? _sample(params['sample']) : SampleChoice.none,
  );
}

Preset _preset(Object goal) {
  if (goal is String) {
    final preset = findPreset(goal);
    if (preset != null) return preset;
    for (final scenario in scenarios) {
      if (scenario.id != goal) continue;
      if (scenario.presets.length == 1) return scenario.presets.single;
      throw _bad(
        'The goal "$goal" comes in ${scenario.presets.length} kinds; name '
        'one: ${[for (final kind in scenario.presets) kind.id].join(', ')}.',
      );
    }
  }
  final goals = [
    for (final scenario in scenarios)
      if (scenario.presets.length == 1)
        scenario.id
      else
        for (final preset in scenario.presets) preset.id,
  ];
  throw _bad('There is no goal "$goal". Goals: ${goals.join(', ')}.');
}

OptionValues _options(Preset preset, Object? options) {
  if (options == null) return const {};
  if (options is! Map) {
    throw _bad('"options" must map option ids to choice ids.');
  }
  final values = <String, String>{};
  for (final MapEntry(:key, :value) in options.entries) {
    final option = preset.options.where((o) => o.id == key).firstOrNull;
    if (option == null) {
      throw _bad(
        preset.options.isEmpty
            ? 'The goal ${preset.id} has no options.'
            : 'The goal ${preset.id} has no option "$key". Options: '
                  '${[for (final o in preset.options) o.id].join(', ')}.',
      );
    }
    if (value is! String || !option.choices.contains(value)) {
      throw _bad(
        'The option ${option.id} of ${preset.id} has no choice "$value". '
        'Choices: ${option.choices.join(', ')}.',
      );
    }
    values[option.id] = value;
  }
  return values;
}

SampleChoice _sample(Object? sample) => switch (sample) {
  null => SampleChoice.none,
  'start' => SampleChoice.start,
  'middle' => SampleChoice.middle,
  _ => throw _bad('"sample" is start or middle, not "$sample".'),
};

/// Where results go: the panel's setting when nothing is asked; `next` for
/// a folder beside each video (`subfolder` names it, and alone implies
/// `next`); or a folder for all of them.
OutputSettings _output(Ref ref, Map<String, Object?> params) {
  final out = params['out'];
  final subfolder = params['subfolder'];
  if (subfolder != null &&
      (subfolder is! String ||
          subfolder.isEmpty ||
          subfolder == '.' ||
          subfolder == '..' ||
          p.basename(subfolder) != subfolder)) {
    throw _bad('"subfolder" is the name of one folder, not "$subfolder".');
  }
  if (out == null && subfolder == null) return ref.read(recipeProvider).output;
  if (out == null || out == 'next') {
    return subfolder is String
        ? OutputSettings(subfolderName: subfolder)
        : const OutputSettings();
  }
  if (subfolder != null) {
    throw _bad('"subfolder" goes with out "next", not with a folder.');
  }
  return OutputSettings(
    mode: OutputMode.customFolder,
    customDir: _absolute(out, 'out'),
  );
}
