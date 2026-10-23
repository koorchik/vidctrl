import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/listener.dart';
import '../../core/control/protocol.dart';
import '../../core/control/views.dart';
import '../../core/control/words.dart';
import '../../core/estimate/size_estimator.dart';
import '../../core/scenarios/registry.dart';
import '../../l10n/app_localizations.dart';
import '../build_info.dart';
import '../estimates/estimate_cache.dart';
import '../home/scenario_texts.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../recipe/recipe.dart';
import '../sources/sources_controller.dart';
import 'app_views.dart';
import 'arguments.dart';
import 'events.dart';
import 'waiter.dart';

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
  Methods.queueRemove: _queueRemove,
  Methods.queueMove: _queueMove,
  Methods.queueRetry: _queueRetry,
  Methods.queueClearFinished: _queueClearFinished,
  Methods.queuePause: _queuePause,
  Methods.queueResume: _queueResume,
  Methods.queueCancel: _queueCancel,
  Methods.queueConvertAnyway: _queueConvertAnyway,
  Methods.queueConvertWhole: _queueConvertWhole,
};

/// A method that goes on beyond its answer, or answers only later.
typedef _Following = Future<Object?> Function(
  Ref ref,
  ControlSessions sessions,
  ControlPeer peer,
  Map<String, Object?> params,
);

const _following = <String, _Following>{
  Methods.subscribe: _subscribe,
  Methods.wait: _wait,
};

/// What the server keeps for a client between its requests.
abstract interface class ControlSessions {
  /// From now on [peer] is told every event.
  void subscribe(ControlPeer peer);

  /// Completes when [tracker] is finished; throws [ControlError] when the
  /// window closes first.
  Future<void> waitFor(ControlPeer peer, WaitTracker tracker);
}

/// Answers one request. `status` answers at once; every other method waits
/// until FFmpeg has been looked for, and fails when it was not found.
Future<Object?> handleControl(
  Ref ref,
  ControlSessions sessions,
  String method,
  Map<String, Object?> params,
  ControlPeer peer,
) async {
  if (method == Methods.status) return _status(ref);
  final answer = _methods[method];
  final following = _following[method];
  if (answer == null && following == null) {
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
  return answer != null
      ? answer(ref, env, params)
      : following!(ref, sessions, peer, params);
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

// ---- Queue controls -----------------------------------------------------
//
// Each as the queue pane's button or menu does it, with what the window
// offers there: only a waiting job is dragged, only a failed or cancelled
// one tried again.

/// The job [params] names under [key].
QueueJob _job(Ref ref, Map<String, Object?> params, [String key = 'job']) =>
    _jobById(ref, params[key], key);

QueueJob _jobById(Ref ref, Object? id, String key) {
  if (id is! int) throw badArgument('"$key" takes job ids, not "$id".');
  for (final job in ref.read(queueProvider).jobs) {
    if (job.id == id) return job;
  }
  throw ControlError(
    ControlErrorKind.notFound,
    'There is no job $id in the queue.',
  );
}

/// Takes jobs out of the queue, as each one's remove does; a result already
/// written stays on disk.
Future<Object?> _queueRemove(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  // All are checked before any is taken out.
  final ids = {
    for (final id in listParam(params, 'jobs')) _jobById(ref, id, 'jobs').id,
  };
  final queue = ref.read(queueProvider.notifier);
  for (final id in ids) {
    await queue.remove(id);
  }
  return {'removed': ids.toList()};
}

/// Moves a waiting job to a place in the queue, 1 being the first.
Future<Object?> _queueMove(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = _job(ref, params);
  final position = params['position'];
  if (position is! int) {
    throw badArgument('"position" is a place in the queue, 1 for the first.');
  }
  if (job.status != JobStatus.waiting) {
    throw badArgument(
      'Job ${job.id} is not waiting; only a waiting job can be moved, as in '
      'the window.',
    );
  }
  final jobs = ref.read(queueProvider).jobs;
  ref
      .read(queueProvider.notifier)
      .reorder(
        jobs.indexWhere((j) => j.id == job.id),
        (position - 1).clamp(0, jobs.length - 1),
      );
  return {
    'jobs': [
      for (final job in ref.read(queueProvider).jobs) jobView(job).toJson(),
    ],
  };
}

Future<Object?> _queueRetry(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = _job(ref, params);
  if (!job.canRetry) {
    throw badArgument(
      'Job ${job.id} is ${statusWords(job.status.name).toLowerCase()}; only '
      'a job that failed or was cancelled can be tried again.',
    );
  }
  ref.read(queueProvider.notifier).retry(job.id);
  return {'job': jobView(_job(ref, params)).toJson()};
}

/// Takes the done and skipped jobs out of the queue, as "Clear finished"
/// does; their results stay on disk.
Future<Object?> _queueClearFinished(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final finished = [
    for (final job in ref.read(queueProvider).jobs)
      if (job.isFinished) job.id,
  ];
  ref.read(queueProvider.notifier).clearFinished();
  return {'removed': finished};
}

Future<Object?> _queuePause(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  ref.read(queueProvider.notifier).pause();
  return {'paused': ref.read(queueProvider).paused};
}

Future<Object?> _queueResume(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  ref.read(queueProvider.notifier).resume();
  return {'paused': ref.read(queueProvider).paused};
}

/// Cancels the job under way, as its cancel button does; answers once it
/// has stopped.
Future<Object?> _queueCancel(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final named = params['job'] == null ? null : _job(ref, params);
  final active = ref.read(queueProvider).activeJob;
  if (named != null && named.id != active?.id) {
    throw badArgument(
      'Job ${named.id} is not converting; `vidctrl-client queue remove '
      '${named.id}` takes it out of the queue.',
    );
  }
  if (active == null) return {'cancelled': null};
  // A job just starting has no conversion to stop yet; it is asked again
  // until it has stopped.
  while (ref.read(queueProvider).activeJob?.id == active.id) {
    await ref.read(queueProvider.notifier).cancelActive();
    await _untilEnded(ref, active.id, within: const Duration(seconds: 1));
  }
  return {'cancelled': active.id};
}

/// Completes once job [id] is no longer under way, or after [within].
Future<void> _untilEnded(Ref ref, int id, {required Duration within}) {
  final done = Completer<void>();
  late final ProviderSubscription<QueueState> subscription;
  Timer? timer;
  void end() {
    if (done.isCompleted) return;
    subscription.close();
    timer?.cancel();
    done.complete();
  }

  subscription = ref.listen<QueueState>(queueProvider, (_, queue) {
    if (queue.activeJob?.id != id) end();
  });
  timer = Timer(within, end);
  if (ref.read(queueProvider).activeJob?.id != id) end();
  return done.future;
}

/// "Convert anyway" of a job whose video was kept as it is.
Future<Object?> _queueConvertAnyway(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = _job(ref, params);
  if (job.status != JobStatus.skipped || !job.keptAsIs) {
    throw badArgument(
      'Job ${job.id} was not kept as it is; only a job that ended skipped '
      'with the outcome notWorthIt can be converted anyway.',
    );
  }
  return _addedBy(ref.read(queueProvider.notifier).convertAnyway(job.id));
}

/// "Convert the whole video" of a sample job.
Future<Object?> _queueConvertWhole(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = _job(ref, params);
  if (!job.isSample) {
    throw badArgument(
      'Job ${job.id} is not a sample; it converts the whole video already.',
    );
  }
  return _addedBy(ref.read(queueProvider.notifier).convertWhole(job.id));
}

/// The job a control added, or none when an identical one is pending.
Map<String, Object?> _addedBy(QueueJob? added) => {
  'added': [if (added != null) jobView(added).toJson()],
  'alreadyQueued': added == null,
};

// ---- Following ----------------------------------------------------------

/// Tells the client every event from now on; first, unless it asks not to,
/// how everything stands, so a client that starts late misses nothing.
Future<Object?> _subscribe(
  Ref ref,
  ControlSessions sessions,
  ControlPeer peer,
  Map<String, Object?> params,
) async {
  final snapshot = params['snapshot'] ?? true;
  if (snapshot is! bool) throw badArgument('"snapshot" is true or false.');
  if (snapshot) {
    final queue = ref.read(queueProvider);
    peer.notify(
      Events.snapshot,
      eventParams({
        'videos': [
          for (final video in ref.read(sourcesProvider).videos)
            videoView(video).toJson(),
        ],
        'jobs': [for (final job in queue.jobs) jobView(job).toJson()],
        'paused': queue.paused,
        'busy': queue.busy,
      }),
    );
  }
  sessions.subscribe(peer);
  return const <String, Object?>{};
}

/// Answers once no job it counts is pending: the given ones, or else those
/// pending now and any that become pending meanwhile.
Future<Object?> _wait(
  Ref ref,
  ControlSessions sessions,
  ControlPeer peer,
  Map<String, Object?> params,
) async {
  Set<int>? ids;
  if (params['jobs'] != null) {
    final given = listParam(params, 'jobs');
    final queue = ref.read(queueProvider);
    ids = {};
    for (final id in given) {
      if (id is! int) throw badArgument('"jobs" takes job ids, not "$id".');
      if (!queue.jobs.any((job) => job.id == id)) {
        throw ControlError(
          ControlErrorKind.notFound,
          'There is no job $id in the queue.',
        );
      }
      ids.add(id);
    }
  }
  final tracker = WaitTracker(ref.read(queueProvider), jobs: ids);
  await sessions.waitFor(peer, tracker);
  return {
    'outcomes': [for (final outcome in tracker.outcomes) outcome.toJson()],
  };
}
