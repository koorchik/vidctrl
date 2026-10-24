import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/control/waiter.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/core/control/codes.dart';

import '../../support/queue_jobs.dart';

void main() {
  /// Each ended job by id and status, `REMOVED` for one taken out.
  List<(int, String)> ended(WaitTracker t) => [
    for (final e in t.ended)
      (e.job.id, e.removed ? JobStatusCodes.removed : codeOf(e.job.status)),
  ];
  List<int> pending(WaitTracker t) => [for (final job in t.pending) job.id];

  test('jobs finished before the wait do not count', () {
    final t = WaitTracker(QueueState(jobs: [failedJob(1), waitingJob(2)]));
    expect(t.finished, isFalse);

    t.update(QueueState(jobs: [failedJob(1), doneJob(2)]));

    expect(t.finished, isTrue);
    expect(ended(t), [(2, 'DONE')]);
  });

  test('a job added during the wait is waited for', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1)]));

    t.update(QueueState(jobs: [doneJob(1), waitingJob(2)]));
    expect(t.finished, isFalse);
    expect(pending(t), [2]);

    t.update(QueueState(jobs: [doneJob(1), doneJob(2)]));
    expect(t.finished, isTrue);
    expect(ended(t), [(1, 'DONE'), (2, 'DONE')]);
    expect(t.pending, isEmpty);
  });

  test('a removed job is reported as removed, not failed', () {
    final t = WaitTracker(QueueState(jobs: [waitingJob(1), waitingJob(2)]));

    t.update(QueueState(jobs: [doneJob(2)]));

    expect(t.finished, isTrue);
    expect(ended(t), [(1, 'REMOVED'), (2, 'DONE')]);
    expect(t.ended.first.job.path, '/videos/1.mp4');
  });

  test('a job cancelled during the wait counts as cancelled', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1)]));

    t.update(QueueState(jobs: [cancelledJob(1)]));

    expect(t.finished, isTrue);
    expect(ended(t), [(1, 'CANCELLED')]);
  });

  test('with nothing pending the wait is over at once', () {
    expect(WaitTracker(const QueueState()).finished, isTrue);
    expect(WaitTracker(QueueState(jobs: [doneJob(1)])).finished, isTrue);
    expect(WaitTracker(QueueState(jobs: [doneJob(1)])).ended, isEmpty);
    expect(WaitTracker(const QueueState(), any: true).finished, isTrue);
  });

  test('given ids, only those count', () {
    final t = WaitTracker(
      QueueState(jobs: [waitingJob(1), waitingJob(2)]),
      jobs: {2},
    );

    t.update(QueueState(jobs: [runningJob(1), doneJob(2), waitingJob(3)]));

    expect(t.finished, isTrue);
    expect(ended(t), [(2, 'DONE')]);
  });

  test('a given job finished already is reported at once', () {
    final t = WaitTracker(QueueState(jobs: [failedJob(1)]), jobs: {1});

    expect(t.finished, isTrue);
    expect(ended(t), [(1, 'FAILED')]);
  });

  test('a job retried during the wait is waited for again', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1), waitingJob(2)]));
    t.update(QueueState(jobs: [failedJob(1), runningJob(2)]));

    t.update(QueueState(jobs: [waitingJob(1), doneJob(2)]));
    expect(t.finished, isFalse);

    t.update(QueueState(jobs: [doneJob(1), doneJob(2)]));
    expect(ended(t), [(1, 'DONE'), (2, 'DONE')]);
  });

  test('a done job is kept as it ended, with its result', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1)]));

    t.update(QueueState(jobs: [doneJob(1)]));

    final job = t.ended.single.job;
    expect(job.outputPath, '/videos/1_new.mp4');
    expect(job.needsALook, isFalse);
  });

  test('the jobs still pending are told as they are now', () {
    final t = WaitTracker(
      QueueState(jobs: [runningJob(1), waitingJob(2), waitingJob(3)]),
    );

    t.update(QueueState(jobs: [doneJob(1), runningJob(2), waitingJob(3)]));

    expect(pending(t), [2, 3]);
    expect(t.pending.first.status, JobStatus.running);
  });

  test('with any, it is over once one counted job has ended', () {
    final t = WaitTracker(
      QueueState(jobs: [runningJob(1), waitingJob(2)]),
      any: true,
    );
    expect(t.finished, isFalse);

    t.update(QueueState(jobs: [doneJob(1), runningJob(2)]));

    expect(t.finished, isTrue);
    expect(ended(t), [(1, 'DONE')]);
    expect(pending(t), [2]);
  });

  test('with any and ids, one of them ended already answers at once', () {
    final t = WaitTracker(
      QueueState(jobs: [doneJob(1), runningJob(2)]),
      jobs: {1, 2},
      any: true,
    );

    expect(t.finished, isTrue);
    expect(ended(t), [(1, 'DONE')]);
    expect(pending(t), [2]);
  });

  test('says when the queue is paused', () {
    final t = WaitTracker(QueueState(jobs: [waitingJob(1)]));
    expect(t.paused, isFalse);

    t.update(QueueState(jobs: [waitingJob(1)], paused: true));

    expect(t.paused, isTrue);
    expect(t.finished, isFalse);
  });
}
