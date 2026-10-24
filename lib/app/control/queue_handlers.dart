import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/control/codes.dart';
import '../../core/control/words.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import 'app_views.dart';
import 'arguments.dart';

// The queue's controls for `vidctrl-client`, each as the queue pane's button
// or menu does it, with what the window offers there: only a waiting job is
// dragged, only a failed or cancelled one tried again.

/// Takes jobs out of the queue, as each one's remove does; a result already
/// written stays on disk.
Future<Object?> queueRemove(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  // All are checked before any is taken out.
  final ids = {
    for (final id in listParam(params, 'jobs')) jobById(ref, id, 'jobs').id,
  };
  final queue = ref.read(queueProvider.notifier);
  for (final id in ids) {
    await queue.remove(id);
  }
  return {'removed': ids.toList()};
}

/// Moves a waiting job to a place in the queue, 1 being the first.
Future<Object?> queueMove(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = jobFrom(ref, params);
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
      for (final job in ref.read(queueProvider).jobs)
        jobView(job, env.capabilities).toJson(),
    ],
  };
}

Future<Object?> queueRetry(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = jobFrom(ref, params);
  if (!job.canRetry) {
    throw badArgument(
      'Job ${job.id} is ${statusWords(codeOf(job.status)).toLowerCase()}; only '
      'a job that failed or was cancelled can be tried again.',
    );
  }
  ref.read(queueProvider.notifier).retry(job.id);
  return {'job': jobView(jobFrom(ref, params), env.capabilities).toJson()};
}

/// Takes the done and skipped jobs out of the queue, as "Clear finished"
/// does; their results stay on disk.
Future<Object?> queueClearFinished(
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

Future<Object?> queuePause(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  ref.read(queueProvider.notifier).pause();
  return {'paused': ref.read(queueProvider).paused};
}

Future<Object?> queueResume(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  ref.read(queueProvider.notifier).resume();
  return {'paused': ref.read(queueProvider).paused};
}

/// Cancels the job under way, as its cancel button does; answers once it
/// has stopped.
Future<Object?> queueCancel(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final named = params['job'] == null ? null : jobFrom(ref, params);
  final active = ref.read(queueProvider).activeJob;
  if (named != null && named.id != active?.id) {
    throw badArgument(
      'Job ${named.id} is not converting; `vidctrl-client queue remove '
      '${named.id}` takes it out of the queue.',
    );
  }
  if (active == null) return {'cancelled': null};
  // Answers once it has stopped. A job just starting stops as soon as it has
  // started; it is asked again each second all the same.
  while (ref.read(queueProvider).activeJob?.id == active.id) {
    await ref.read(queueProvider.notifier).cancelActive();
    await _untilEnded(ref, active.id, within: const Duration(seconds: 1));
  }
  final ended = ref
      .read(queueProvider)
      .jobs
      .where((job) => job.id == active.id)
      .firstOrNull;
  if (ended?.status == JobStatus.cancelled) return {'cancelled': active.id};
  // It ended otherwise first, or was taken out of the queue meanwhile.
  return {
    'cancelled': null,
    if (ended != null) 'job': jobView(ended, env.capabilities).toJson(),
  };
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
Future<Object?> queueConvertAnyway(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = jobFrom(ref, params);
  if (job.status != JobStatus.skipped || !job.keptAsIs) {
    throw badArgument(
      'Job ${job.id} was not kept as it is; only a job kept as it is, '
      'because converting would hardly make it smaller, can be converted '
      'anyway.',
    );
  }
  return _addedBy(env, ref.read(queueProvider.notifier).convertAnyway(job.id));
}

/// "Convert the whole video" of a sample job.
Future<Object?> queueConvertWhole(
  Ref ref,
  AppEnvironment env,
  Map<String, Object?> params,
) async {
  final job = jobFrom(ref, params);
  if (!job.isSample) {
    throw badArgument(
      'Job ${job.id} is not a sample; it converts the whole video already.',
    );
  }
  // As the window, which offers it under a finished sample only.
  if (job.status != JobStatus.done) {
    throw badArgument(
      'Job ${job.id} is a sample not done yet; the whole video can be '
      'queued once the sample is done.',
    );
  }
  return _addedBy(env, ref.read(queueProvider.notifier).convertWhole(job.id));
}

/// The job a control added, or none when an identical one is pending.
Map<String, Object?> _addedBy(AppEnvironment env, QueueJob? added) => {
  'added': [if (added != null) jobView(added, env.capabilities).toJson()],
  'alreadyQueued': added == null,
};
