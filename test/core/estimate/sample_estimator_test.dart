// Measuring a video's expected size, with a stand-in for FFmpeg: a shell
// script that writes each piece it is asked for. The real measurements are
// in test/integration/conversion_test.dart, which needs FFmpeg.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/estimate/size_estimator.dart';
import 'package:vidctrl/core/ffmpeg/runner.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../../support/fake_media.dart';

void main() {
  late Directory folder;
  late File written;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('sample_estimator_test');
    written = File(p.join(folder.path, 'written.txt'));
  });

  tearDown(() => folder.delete(recursive: true));

  /// An FFmpeg that writes a 1000-byte piece and notes where.
  FfmpegRunner runner() {
    final script = File(p.join(folder.path, 'ffmpeg'))
      ..writeAsStringSync('''
#!/bin/sh
for a; do out=\$a; done
out=\${out#file:}
head -c 1000 /dev/zero > "\$out"
echo "\$out" >> "${written.path}"
''');
    Process.runSync('chmod', ['+x', script.path]);
    return FfmpegRunner(script.path);
  }

  const encode = ConversionPlan(
    kind: PlanKind.encode,
    video: VideoEncode(encoder: 'libx265', pixFmt: 'yuv420p10le'),
    extension: 'mp4',
  );

  test('pieces are encoded in a folder of the app\'s own, removed on '
      'leaving', () async {
    final estimator = SampleEstimator(runner());

    final estimate = await estimator.estimate(clip(audio: []), encode);

    expect(estimate!.bytes, greaterThan(0));
    final pieces = Directory(p.dirname(written.readAsLinesSync().first));
    expect(p.basename(pieces.path), startsWith('vidctrl_estimates_'));
    expect(p.basename(pieces.path), isNot('vidctrl_estimates_$pid'));
    final mode = Process.runSync('stat', [
      if (Platform.isMacOS) ...['-f', '%Lp'] else ...['-c', '%a'],
      pieces.path,
    ]);
    expect((mode.stdout as String).trim(), '700');

    await estimator.discardKept();

    expect(pieces.existsSync(), isFalse);
  });
}
