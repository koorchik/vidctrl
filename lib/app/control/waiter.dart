import '../../core/control/views.dart';
import '../queue/queue_state.dart';

/// Follows the queue for one `wait`: the jobs pending when it starts, or the
/// ones asked for, and without those any job that becomes pending while it
/// waits (added by a client or the mouse, or tried again). Jobs that ended
/// before it started do not count, so an old failure does not fail every
/// later wait.
class WaitTracker {
  WaitTracker(QueueState start, {Set<int>? jobs}) : _given = jobs != null {
    _counted.addAll(
      jobs ??
          {
            for (final job in start.jobs)
              if (job.isPending) job.id,
          },
    );
    update(start);
  }

  final bool _given;

  /// In the order first counted.
  final _counted = <int>{};

  /// The last that was seen of each counted job; one gone since was removed.
  final _seen = <int, QueueJob>{};
  final _present = <int>{};
  var _paused = false;

  void update(QueueState state) {
    _paused = state.paused;
    _present.clear();
    for (final job in state.jobs) {
      if (!_given && job.isPending) _counted.add(job.id);
      if (!_counted.contains(job.id)) continue;
      _seen[job.id] = job;
      _present.add(job.id);
    }
  }

  /// Whether the queue was paused when last seen. A paused queue keeps the
  /// wait going: the owner may continue it.
  bool get paused => _paused;

  /// No counted job is pending any more.
  bool get finished =>
      _counted.every((id) => !_present.contains(id) || !_seen[id]!.isPending);

  /// How each counted job has ended so far.
  List<JobOutcome> get outcomes => [
    for (final id in _counted)
      if (_seen[id] case final job?)
        if (!_present.contains(id))
          JobOutcome(
            jobId: id,
            path: job.path,
            status: 'removed',
            needsALook: false,
          )
        else if (!job.isPending)
          JobOutcome(
            jobId: id,
            path: job.path,
            status: job.status.name,
            outputPath:
                job.status == JobStatus.done && job.outputPath.isNotEmpty
                ? job.outputPath
                : null,
            needsALook: job.needsALook,
          ),
  ];
}
