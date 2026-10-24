import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/codes.dart';
import '../../core/control/listener.dart';
import '../../core/control/protocol.dart';
import '../../core/control/views.dart';
import '../../core/scenarios/registry.dart';
import '../build_info.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../sources/sources_controller.dart';
import 'app_views.dart';
import 'arguments.dart';
import 'events.dart';
import 'queue_handlers.dart';
import 'result_handlers.dart';
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
  Methods.videosDetails: videosDetails,
  Methods.videosEstimate: videosEstimate,
  Methods.queueList: _queueList,
  Methods.queueAdd: _queueAdd,
  Methods.queueRemove: queueRemove,
  Methods.queueMove: queueMove,
  Methods.queueRetry: queueRetry,
  Methods.queueClearFinished: queueClearFinished,
  Methods.queuePause: queuePause,
  Methods.queueResume: queueResume,
  Methods.queueCancel: queueCancel,
  Methods.queueConvertAnyway: queueConvertAnyway,
  Methods.queueConvertWhole: queueConvertWhole,
  Methods.jobGet: jobGet,
  Methods.jobCompare: jobCompare,
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

  /// Completes when [tracker] is finished, or once [timeout] has passed;
  /// throws [ControlError] when the window closes first.
  Future<void> waitFor(
    ControlPeer peer,
    WaitTracker tracker, {
    Duration? timeout,
  });
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
      state: environment.hasError
          ? StateCodes.ffmpegMissing
          : StateCodes.starting,
      version: version,
      busy: false,
      paused: false,
      jobs: const {},
    ).toJson();
  }
  final queue = ref.read(queueProvider);
  final counts = <String, int>{};
  for (final job in queue.jobs) {
    counts.update(codeOf(job.status), (n) => n + 1, ifAbsent: () => 1);
  }
  return StatusView(
    state: StateCodes.ready,
    version: version,
    busy: queue.busy,
    paused: queue.paused,
    jobs: counts,
  ).toJson();
}

/// The goals by their ids, with the options this computer offers; the
/// words for them are in the client's manual.
Future<Object?> _goals(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async => {
  'goals': [
    for (final scenario in scenarios)
      for (final preset in scenario.presets)
        GoalView(
          id: preset.id,
          scenario: scenario.id,
          options: [
            for (final option in preset.options)
              if (optionOffered(preset, option, env.capabilities))
                OptionView(
                  id: option.id,
                  defaultChoice: option.defaultChoice,
                  advanced: option.advanced,
                  choices: option.choices,
                ),
          ],
        ).toJson(),
  ],
};

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

  /// An [AddResultCodes] code.
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
          ? AddResultCodes.unreadable
          : before.contains(video.id)
          ? AddResultCodes.known
          : AddResultCodes.added;
      entries.add(_Added(given, video.path, result, video.id));
    }
    // A folder with no videos in it counts as nothing there.
    if (!found) entries.add(_Added(given, given, AddResultCodes.notFound));
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
              : goalPreview(ref, env, video, recipe),
        ).toJson(),
    ],
  };
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
    'jobs': [
      for (final job in queue.jobs) jobView(job, env.capabilities).toJson(),
    ],
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
          skipped.add({'video': reference, 'reason': AddResultCodes.notFound});
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
      skipped.add({'video': id, 'reason': AddResultCodes.notFound});
    } else if (!video.isReady) {
      skipped.add({'video': id, 'reason': AddResultCodes.unreadable});
    } else {
      ready.add(video);
    }
  }
  if (ready.isEmpty) {
    // Every video was skipped, as `videos.add` with nothing to add.
    final reasons = [
      for (final s in skipped)
        s['reason'] == AddResultCodes.unreadable
            ? 'video ${s['video']} cannot be read'
            : 'nothing found at ${s['video']}',
    ];
    throw badArgument('Nothing was queued: ${reasons.join('; ')}.');
  }
  final result = ref
      .read(queueProvider.notifier)
      .addVideos(ready, recipe: recipe, output: output);
  return {
    'goal': recipe.presetId,
    'options': appliedOptions(recipe, env.capabilities),
    'added': [
      for (final job in result.added) jobView(job, env.capabilities).toJson(),
    ],
    'alreadyQueued': result.alreadyQueued,
    'skipped': skipped,
  };
}

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
    final capabilities = ref
        .read(environmentProvider)
        .requireValue
        .capabilities;
    peer.notify(
      Events.snapshot,
      eventParams({
        'videos': [
          for (final video in ref.read(sourcesProvider).videos)
            videoView(video).toJson(),
        ],
        'jobs': [
          for (final job in queue.jobs) jobView(job, capabilities).toJson(),
        ],
        'paused': queue.paused,
        'busy': queue.busy,
      }),
    );
  }
  sessions.subscribe(peer);
  return const <String, Object?>{};
}

/// Answers once no job it counts is pending: the given ones, or else those
/// pending now and any that become pending meanwhile; with `any`, once one
/// of them has ended; with `timeout`, after that many seconds at most. The
/// answer holds each counted job that has ended, and how the others stand.
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
  final any = params['any'] ?? false;
  if (any is! bool) throw badArgument('"any" is true or false.');
  final limit = params['timeout'];
  if (limit != null && (limit is! num || !(limit >= 0))) {
    throw badArgument('"timeout" is a number of seconds, 0 or more.');
  }
  final seconds = limit as num?;
  final tracker = WaitTracker(ref.read(queueProvider), jobs: ids, any: any);
  await sessions.waitFor(
    peer,
    tracker,
    timeout: seconds == null
        ? null
        // Longer than that is as good as no limit, and fits a Duration.
        : Duration(milliseconds: (min(seconds, 1e9) * 1000).round()),
  );
  final capabilities = ref.read(environmentProvider).requireValue.capabilities;
  return {
    'ended': [
      for (final (:job, :removed) in tracker.ended)
        jobView(job, capabilities, removed: removed).toJson(),
    ],
    'pending': [for (final job in tracker.pending) pendingView(job).toJson()],
    'paused': tracker.paused,
  };
}
