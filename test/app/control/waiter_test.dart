import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/control/waiter.dart';
import 'package:vidctrl/app/queue/queue_state.dart';

import '../../support/queue_jobs.dart';

void main() {
  List<(int, String)> outcomes(WaitTracker t) => [
    for (final o in t.outcomes) (o.jobId, o.status),
  ];

  test('jobs finished before the wait do not count', () {
    final t = WaitTracker(QueueState(jobs: [failedJob(1), waitingJob(2)]));
    expect(t.finished, isFalse);

    t.update(QueueState(jobs: [failedJob(1), doneJob(2)]));

    expect(t.finished, isTrue);
    expect(outcomes(t), [(2, 'DONE')]);
  });

  test('a job added during the wait is waited for', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1)]));

    t.update(QueueState(jobs: [doneJob(1), waitingJob(2)]));
    expect(t.finished, isFalse);

    t.update(QueueState(jobs: [doneJob(1), doneJob(2)]));
    expect(t.finished, isTrue);
    expect(outcomes(t), [(1, 'DONE'), (2, 'DONE')]);
  });

  test('a removed job is reported as removed, not failed', () {
    final t = WaitTracker(QueueState(jobs: [waitingJob(1), waitingJob(2)]));

    t.update(QueueState(jobs: [doneJob(2)]));

    expect(t.finished, isTrue);
    expect(outcomes(t), [(1, 'REMOVED'), (2, 'DONE')]);
    expect(t.outcomes.first.path, '/videos/1.mp4');
  });

  test('a job cancelled during the wait counts as cancelled', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1)]));

    t.update(QueueState(jobs: [cancelledJob(1)]));

    expect(t.finished, isTrue);
    expect(outcomes(t), [(1, 'CANCELLED')]);
  });

  test('with nothing pending the wait is over at once', () {
    expect(WaitTracker(const QueueState()).finished, isTrue);
    expect(WaitTracker(QueueState(jobs: [doneJob(1)])).finished, isTrue);
    expect(WaitTracker(QueueState(jobs: [doneJob(1)])).outcomes, isEmpty);
  });

  test('given ids, only those count', () {
    final t = WaitTracker(
      QueueState(jobs: [waitingJob(1), waitingJob(2)]),
      jobs: {2},
    );

    t.update(QueueState(jobs: [runningJob(1), doneJob(2), waitingJob(3)]));

    expect(t.finished, isTrue);
    expect(outcomes(t), [(2, 'DONE')]);
  });

  test('a given job finished already is reported at once', () {
    final t = WaitTracker(QueueState(jobs: [failedJob(1)]), jobs: {1});

    expect(t.finished, isTrue);
    expect(outcomes(t), [(1, 'FAILED')]);
  });

  test('a job retried during the wait is waited for again', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1), waitingJob(2)]));
    t.update(QueueState(jobs: [failedJob(1), runningJob(2)]));

    t.update(QueueState(jobs: [waitingJob(1), doneJob(2)]));
    expect(t.finished, isFalse);

    t.update(QueueState(jobs: [doneJob(1), doneJob(2)]));
    expect(outcomes(t), [(1, 'DONE'), (2, 'DONE')]);
  });

  test('a done job carries its result and whether it needs a look', () {
    final t = WaitTracker(QueueState(jobs: [runningJob(1)]));

    t.update(QueueState(jobs: [doneJob(1)]));

    final outcome = t.outcomes.single;
    expect(outcome.outputPath, '/videos/1_new.mp4');
    expect(outcome.needsALook, isFalse);
  });

  test('says when the queue is paused', () {
    final t = WaitTracker(QueueState(jobs: [waitingJob(1)]));
    expect(t.paused, isFalse);

    t.update(QueueState(jobs: [waitingJob(1)], paused: true));

    expect(t.paused, isTrue);
    expect(t.finished, isFalse);
  });
}
