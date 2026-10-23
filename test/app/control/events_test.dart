import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/control/events.dart';
import 'package:vidctrl/app/quality/quality_controller.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/control/protocol.dart';

import '../../support/fake_media.dart';
import '../../support/queue_jobs.dart';

void main() {
  List<String> names(List<ControlEvent> events) => [
    for (final e in events) e.name,
  ];

  group('queue', () {
    test('a new job gives job-added with the job', () {
      final events = queueEvents(
        const QueueState(),
        QueueState(jobs: [waitingJob(1)]),
      );

      expect(names(events), [Events.jobAdded]);
      expect(events.single.data, containsPair('id', 1));
      expect(events.single.data, containsPair('status', 'waiting'));
    });

    test('a job going from waiting to done gives started then finished', () {
      final waiting = QueueState(jobs: [waitingJob(1)], busy: true);
      final running = QueueState(jobs: [runningJob(1)], busy: true);
      final done = QueueState(jobs: [doneJob(1)], busy: true);

      expect(names(queueEvents(waiting, running)), [Events.jobStarted]);
      final finished = queueEvents(running, done);
      expect(names(finished), [Events.jobFinished]);
      expect(finished.single.data, containsPair('status', 'done'));
      expect(
        finished.single.data,
        containsPair('outputPath', '/videos/1_new.mp4'),
      );
      // A job with nothing to do is finished without starting.
      final skipped = QueueState(
        jobs: [queueJob(1, JobStatus.skipped)],
        busy: true,
      );
      expect(names(queueEvents(waiting, skipped)), [Events.jobFinished]);
    });

    test('a failed or cancelled job is finished too', () {
      final running = QueueState(jobs: [runningJob(1), runningJob(2)]);

      final events = queueEvents(
        running,
        QueueState(jobs: [failedJob(1), cancelledJob(2)]),
      );

      expect(names(events), [Events.jobFinished, Events.jobFinished]);
      expect(events.map((e) => e.data['status']), ['failed', 'cancelled']);
    });

    test('a measuring attempt gives job-checking with its number', () {
      final first = QueueState(
        jobs: [queueJob(1, JobStatus.running, attempt: 1)],
      );
      final second = QueueState(
        jobs: [queueJob(1, JobStatus.running, attempt: 2)],
      );

      final events = queueEvents(first, second);

      expect(names(events), [Events.jobChecking]);
      expect(events.single.data, {'job': 1, 'attempt': 2});
      expect(names(queueEvents(QueueState(jobs: [waitingJob(1)]), first)), [
        Events.jobStarted,
        Events.jobChecking,
      ]);
    });

    test('progress gives job-progress with the part done', () {
      final events = queueEvents(
        QueueState(jobs: [runningJob(1)]),
        QueueState(
          jobs: [queueJob(1, JobStatus.running, progress: progressAt(0.25))],
        ),
      );

      expect(names(events), [Events.jobProgress]);
      expect(events.single.data, {
        'job': 1,
        'fraction': 0.25,
        'remainingSeconds': 30.0,
      });
    });

    test('a job taken out gives job-removed', () {
      final events = queueEvents(
        QueueState(jobs: [doneJob(1), waitingJob(2)]),
        QueueState(jobs: [waitingJob(2)]),
      );

      expect(names(events), [Events.jobRemoved]);
      expect(events.single.data, {'job': 1});
    });

    test('pausing and continuing are told', () {
      const running = QueueState(busy: true);
      const paused = QueueState(busy: true, paused: true);

      expect(names(queueEvents(running, paused)), [Events.queuePaused]);
      expect(names(queueEvents(paused, running)), [Events.queueResumed]);
    });

    test('the queue running out gives queue-idle', () {
      final busy = QueueState(jobs: [runningJob(1)], busy: true);
      final idle = QueueState(jobs: [doneJob(1)]);

      expect(names(queueEvents(busy, idle)), [
        Events.jobFinished,
        Events.queueIdle,
      ]);
    });

    test('nothing changed gives nothing', () {
      final state = QueueState(jobs: [runningJob(1)], busy: true);
      expect(queueEvents(state, state), isEmpty);
    });
  });

  group('videos', () {
    test('a video added, then read, gives added then ready', () {
      const probing = SourceVideo(id: 1, path: '/videos/a.mp4');
      final ready = SourceVideo(
        id: 1,
        path: '/videos/a.mp4',
        status: SourceStatus.ready,
        info: clip(path: '/videos/a.mp4'),
      );

      final added = sourceEvents(
        const SourcesState(),
        const SourcesState(videos: [probing]),
      );
      final read = sourceEvents(
        const SourcesState(videos: [probing]),
        SourcesState(videos: [ready]),
      );

      expect(names(added), [Events.videoAdded]);
      expect(added.single.data, containsPair('status', 'probing'));
      expect(names(read), [Events.videoReady]);
      expect(read.single.data, containsPair('width', 3840));
    });

    test('a file that is no video gives video-unreadable', () {
      const probing = SourceVideo(id: 1, path: '/videos/notes.txt');
      final events = sourceEvents(
        const SourcesState(videos: [probing]),
        SourcesState(
          videos: [probing.copyWith(status: SourceStatus.unreadable)],
        ),
      );

      expect(names(events), [Events.videoUnreadable]);
      expect(events.single.data, containsPair('path', '/videos/notes.txt'));
    });

    test('a video taken off the list gives video-removed', () {
      final events = sourceEvents(
        const SourcesState(videos: [SourceVideo(id: 1, path: '/videos/a.mp4')]),
        const SourcesState(),
      );

      expect(names(events), [Events.videoRemoved]);
      expect(events.single.data, {'video': 1});
    });

    test('a change of selection alone gives nothing', () {
      const videos = [SourceVideo(id: 1, path: '/videos/a.mp4')];
      expect(
        sourceEvents(
          const SourcesState(videos: videos),
          const SourcesState(videos: videos, selectedIds: {1}),
        ),
        isEmpty,
      );
    });
  });

  group('comparisons', () {
    test('a comparison that ends gives compare-finished', () {
      final measured = qualityEvents(
        {1: const QualityComparing(0.5)},
        {1: const QualityMeasured(43, vmaf: 96)},
      );
      final failed = qualityEvents(
        {2: const QualityComparing(0.5)},
        {
          2: const QualityFailed(['broken']),
        },
      );

      expect(names(measured), [Events.compareFinished]);
      expect(measured.single.data, {
        'job': 1,
        'status': 'measured',
        'closeness': 'same',
        'closenessText': 'Looks the same as the original',
        'xpsnr': 43.0,
        'vmaf': 96.0,
      });
      expect(failed.single.data, {
        'job': 2,
        'status': 'failed',
        'errorLines': ['broken'],
      });
    });

    test('progress of a comparison gives nothing', () {
      expect(
        qualityEvents(
          {1: const QualityComparing(0.2)},
          {1: const QualityComparing(0.5)},
        ),
        isEmpty,
      );
    });
  });
}
