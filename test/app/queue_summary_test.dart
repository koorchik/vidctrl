import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/queue/queue_summary.dart';
import 'package:vidctrl/core/estimate/progress_estimator.dart';
import 'package:vidctrl/core/ffmpeg/command_builder.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../support/queue_jobs.dart';

void main() {
  // Every job converts a one-minute clip.
  const encode = ConversionPlan(
    kind: PlanKind.encode,
    video: VideoEncode(encoder: 'libx265', pixFmt: 'yuv420p10le'),
    extension: 'mp4',
  );

  QueueState busy(List<QueueJob> jobs) => QueueState(jobs: jobs, busy: true);

  JobProgress halfway({double? speed}) => JobProgress(
    fraction: 0.5,
    outTime: const Duration(seconds: 30),
    speed: speed,
    remaining: const Duration(seconds: 30),
  );

  group('progress across the run', () {
    test('counts each job by how much video it converts', () {
      final progress = overallProgress(
        busy([
          doneJob(1),
          queueJob(2, JobStatus.running, progress: halfway()),
          waitingJob(3),
        ]),
      );

      expect(progress.fraction, 0.5);
      expect(progress.position, 2);
      expect(progress.total, 3);
    });

    test('expects the waiting encodes to go at the current speed', () {
      final progress = overallProgress(
        busy([
          queueJob(1, JobStatus.running, progress: halfway(speed: 2)),
          waitingJob(2).copyWith(plan: encode),
          // A quick fix takes seconds: not counted in the time left.
          waitingJob(3),
        ]),
      );

      expect(progress.left, const Duration(minutes: 1));
    });

    test('says no time left before the speed is known', () {
      final progress = overallProgress(
        busy([queueJob(1, JobStatus.running, progress: halfway())]),
      );

      expect(progress.left, isNull);
    });
  });

  test('the sizes before and after count whole videos only', () {
    ConversionResult wrote(int bytes) => ConversionResult(
      status: ConversionStatus.done,
      elapsed: Duration.zero,
      outputBytes: bytes,
    );
    final whole = doneJob(1).copyWith(result: wrote(150000000));
    final sample = queueJob(
      2,
      JobStatus.done,
      sample: const SampleRange(length: Duration(seconds: 10)),
    ).copyWith(result: wrote(3000000));

    final sizes = doneSizes(QueueState(jobs: [whole, sample, waitingJob(3)]));

    expect(sizes.before, 750000000);
    expect(sizes.after, 150000000);
  });
}
