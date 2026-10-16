import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/estimate/progress_estimator.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/progress_parser.dart';

void main() {
  group('progress parser', () {
    List<ProgressSnapshot> parse(String text) {
      final parser = ProgressParser();
      return [
        for (final line in text.trim().split('\n')) ?parser.addLine(line),
      ];
    }

    test('reports once per block, with time and size', () {
      final snapshots = parse('''
frame=60
fps=30.00
total_size=749049
out_time_us=2000000
out_time_ms=2000000
out_time=00:00:02.000000
speed=1.5x
progress=continue
frame=90
total_size=1100000
out_time_us=3000000
progress=end
''');

      expect(snapshots, hasLength(2));
      expect(snapshots[0].outTime, const Duration(seconds: 2));
      expect(snapshots[0].totalSize, 749049);
      expect(snapshots[0].frame, 60);
      expect(snapshots[0].isEnd, isFalse);
      expect(snapshots[1].outTime, const Duration(seconds: 3));
      expect(snapshots[1].isEnd, isTrue);
    });

    test('an unknown size stays unknown', () {
      final snapshot = parse('''
total_size=N/A
out_time_us=1000000
progress=continue
''').single;

      expect(snapshot.totalSize, isNull);
      expect(snapshot.outTime, const Duration(seconds: 1));
    });

    test('a negative first timestamp is ignored', () {
      final snapshot = parse('''
out_time_us=-9223372036854775808
progress=continue
''').single;

      expect(snapshot.outTime, isNull);
    });
  });

  group('progress estimator', () {
    const minute = Duration(minutes: 1);
    ProgressSnapshot at(int seconds, {int? bytes}) => ProgressSnapshot(
      outTime: Duration(seconds: seconds),
      totalSize: bytes,
    );

    test('reports fraction, speed and time remaining', () {
      final estimator = ProgressEstimator(minute);
      estimator.update(at(0), Duration.zero);
      final progress = estimator.update(at(20), const Duration(seconds: 10));

      expect(progress.fraction, closeTo(1 / 3, 0.001));
      expect(progress.speed, closeTo(2.0, 0.001));
      expect(progress.remaining, const Duration(seconds: 20));
    });

    test('speed follows the recent rate, not the average since the start', () {
      final estimator = ProgressEstimator(const Duration(minutes: 10));
      // Fast for the first minute, then a slow stretch.
      for (var t = 0; t <= 60; t += 5) {
        estimator.update(at(t * 2), Duration(seconds: t));
      }
      late JobProgress progress;
      for (var t = 65; t <= 90; t += 5) {
        progress = estimator.update(
          at(120 + (t - 60) ~/ 2),
          Duration(seconds: t),
        );
      }

      expect(progress.speed, closeTo(0.5, 0.11));
    });

    test('gives no speed before there is a second of history', () {
      final estimator = ProgressEstimator(minute);
      final progress = estimator.update(
        at(1),
        const Duration(milliseconds: 300),
      );

      expect(progress.speed, isNull);
      expect(progress.remaining, isNull);
    });

    test('predicts the final size only once enough has been written', () {
      final estimator = ProgressEstimator(const Duration(minutes: 10));
      final early = estimator.update(
        at(10, bytes: 5000000),
        const Duration(seconds: 5),
      );
      final later = estimator.update(
        at(60, bytes: 30000000),
        const Duration(seconds: 30),
      );

      expect(early.predictedBytes, isNull);
      expect(later.predictedBytes, 300000000);
    });

    test('never runs backwards when FFmpeg repeats an earlier time', () {
      final estimator = ProgressEstimator(minute);
      estimator.update(at(30), const Duration(seconds: 10));
      final progress = estimator.update(at(25), const Duration(seconds: 11));

      expect(progress.outTime, const Duration(seconds: 30));
    });

    test('the final report means the job is complete', () {
      final estimator = ProgressEstimator(minute);
      final progress = estimator.update(
        const ProgressSnapshot(outTime: Duration(seconds: 59), isEnd: true),
        const Duration(seconds: 30),
      );

      expect(progress.fraction, 1.0);
      expect(progress.remaining, Duration.zero);
    });
  });

  group('FFmpeg self-description', () {
    test('version is read from the banner line', () {
      expect(
        parseFfmpegVersion('ffmpeg version 8.0.1-3build2 Copyright (c) 2000'),
        '8.0.1-3build2',
      );
    });

    test('the short version is the release number', () {
      expect(shortFfmpegVersion('n8.1.3-9-g29e619e767-20260930'), '8.1.3');
      expect(shortFfmpegVersion('8.1.2-https://www.martin-riedl.de'), '8.1.2');
      expect(shortFfmpegVersion('8.0.1-3build2'), '8.0.1');
      expect(
        shortFfmpegVersion('N-127021-ge0c94b2d1c'),
        'N-127021-ge0c94b2d1c',
      );
    });

    test('encoder list skips the legend', () {
      const output = '''
Encoders:
 V..... = Video
 A..... = Audio
 ------
 V....D libsvtav1            SVT-AV1 encoder (codec av1)
 VFS..D dnxhd                VC3/DNxHD
 A....D aac                  AAC (Advanced Audio Coding)
''';

      expect(parseEncoderList(output), {'libsvtav1', 'dnxhd', 'aac'});
    });
  });
}
