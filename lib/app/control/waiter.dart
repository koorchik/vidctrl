import '../queue/queue_state.dart';

/// A job a `wait` counts that has ended: as last seen, or [removed] when it
/// was taken out of the queue since.
typedef EndedJob = ({QueueJob job, bool removed});

/// Follows the queue for one `wait`: the jobs pending when it starts, or the
/// ones asked for, and without those any job that becomes pending while it
/// waits (added by a client or the mouse, or tried again). Jobs that ended
/// before it started do not count, so an old failure does not fail every
/// later wait. With [any] the wait is over once one of them has ended.
class WaitTracker {
  WaitTracker(QueueState start, {Set<int>? jobs, this.any = false})
    : _given = jobs != null {
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

  /// Over once one counted job has ended, not all.
  final bool any;

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

  /// No counted job is pending any more; with [any], one has ended.
  bool get finished => pending.isEmpty || any && ended.isNotEmpty;

  /// The counted jobs that have ended so far, in the order counted.
  List<EndedJob> get ended => [
    for (final id in _counted)
      if (_seen[id] case final job?)
        if (!_present.contains(id))
          (job: job, removed: true)
        else if (!job.isPending)
          (job: job, removed: false),
  ];

  /// The counted jobs still waiting or under way, as they are now.
  List<QueueJob> get pending => [
    for (final id in _counted)
      if (_present.contains(id) && _seen[id]!.isPending) _seen[id]!,
  ];
}
