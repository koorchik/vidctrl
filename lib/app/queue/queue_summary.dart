import '../../core/scenarios/scenario.dart';
import 'queue_state.dart';

// What the queue's headline says, worked out from its jobs.

/// How far the run has come: the share of its video converted, the time
/// left where it can be told, and which job of how many is under way.
typedef QueueProgress = ({
  double fraction,
  Duration? left,
  int position,
  int total,
});

/// Progress across the jobs of this run, weighted by how much video each
/// converts. Waiting jobs are assumed to go at the current job's speed;
/// quick fixes take seconds and are not counted towards the time left.
QueueProgress overallProgress(QueueState state) {
  double seconds(QueueJob job) =>
      (job.sample?.length ?? job.info.duration).inMilliseconds / 1000;
  final active = state.activeJob;
  final waiting = state.waiting;
  final finished = state.jobs.where(
    (j) => j.status == JobStatus.done || j.status == JobStatus.skipped,
  );
  final doneSeconds = finished.fold<double>(0, (s, j) => s + seconds(j));
  final activeSeconds = active == null ? 0.0 : seconds(active);
  final total =
      doneSeconds +
      activeSeconds +
      waiting.fold<double>(0, (s, j) => s + seconds(j));
  final fraction = total > 0
      ? (doneSeconds + activeSeconds * (active?.progress?.fraction ?? 0)) /
            total
      : 0.0;

  final speed = active?.progress?.speed;
  final remaining = active?.progress?.remaining;
  Duration? left;
  if (remaining != null && speed != null && speed > 0) {
    final waitingEncodes = waiting
        .where((j) => j.plan.kind == PlanKind.encode)
        .fold<double>(0, (s, j) => s + seconds(j));
    left =
        remaining +
        Duration(milliseconds: (waitingEncodes / speed * 1000).round());
  }
  final position = finished.length + 1;
  return (
    fraction: fraction,
    left: left,
    position: position,
    total: position + waiting.length,
  );
}

/// What the finished whole videos weighed before and after.
({int before, int after}) doneSizes(QueueState state) {
  final done = state.jobs.where(
    (j) => j.status == JobStatus.done && !j.isSample,
  );
  return (
    before: done.fold<int>(0, (s, j) => s + j.info.sizeBytes),
    after: done.fold<int>(0, (s, j) => s + (j.result?.outputBytes ?? 0)),
  );
}
