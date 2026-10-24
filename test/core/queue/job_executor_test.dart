// Converting one file, with a stand-in for FFmpeg: a shell script that does
// what FFmpeg would to the file it is given last. The real conversions are in
// test/integration/conversion_test.dart, which needs FFmpeg.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/ffmpeg/runner.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../../support/eventually.dart';
import '../../support/fake_media.dart';

void main() {
  late Directory folder;
  late String original;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('job_executor_test');
    original = p.join(folder.path, 'clip.mov');
    await File(original).writeAsString('camera footage');
  });

  tearDown(() => folder.delete(recursive: true));

  /// An FFmpeg that runs [body] with `$out` set to the file to write.
  JobExecutor executorRunning(String body) {
    final script = File(p.join(folder.path, 'ffmpeg'))
      ..writeAsStringSync('''
#!/bin/sh
for a; do out=\$a; done
out=\${out#file:}
$body
''');
    Process.runSync('chmod', ['+x', script.path]);
    return JobExecutor(FfmpegRunner(script.path));
  }

  String output() => p.join(folder.path, 'Converted', 'clip.mp4');

  ConversionJob job({String? input, bool keepFileDate = true}) => ConversionJob(
    input: clip(path: input ?? original),
    plan: ConversionPlan(kind: PlanKind.remux, keepFileDate: keepFileDate),
    outputPath: output(),
  );

  /// Every file left in the output folder, hidden ones included.
  List<String> leftOver() {
    final converted = Directory(p.dirname(output()));
    if (!converted.existsSync()) return [];
    return [for (final f in converted.listSync()) p.basename(f.path)]..sort();
  }

  test('a finished conversion is renamed into place', () async {
    final executor = executorRunning('''
printf 'converted' > "\$out"
echo progress=end
''');

    final handle = await executor.start(job());
    final result = await handle.result;

    expect(result.status, ConversionStatus.done);
    expect(result.outputPath, output());
    expect(result.outputBytes, 9);
    expect(leftOver(), ['clip.mp4']);
  });

  test('a failed conversion leaves nothing and says why', () async {
    final executor = executorRunning('''
printf 'half' > "\$out"
echo 'Invalid data found when processing input' >&2
exit 1
''');

    final result = await (await executor.start(job())).result;

    expect(result.status, ConversionStatus.failed);
    expect(result.errorLines, ['Invalid data found when processing input']);
    expect(leftOver(), isEmpty);
  });

  test('a cancelled conversion stops at once and leaves nothing', () async {
    final executor = executorRunning('''
printf 'half' > "\$out"
exec sleep 30
''');
    final handle = await executor.start(job());
    final partial = File(temporaryPathFor(output()));
    await eventually(partial.existsSync);

    await handle.cancel();
    final result = await handle.result.timeout(const Duration(seconds: 5));

    expect(result.status, ConversionStatus.cancelled);
    expect(leftOver(), isEmpty);
  });

  test('a finished file is kept when the original is gone meanwhile', () async {
    // As when a card is pulled out once FFmpeg has read it: the file's date
    // cannot be copied, but the result is whole.
    final executor = executorRunning('''
printf 'converted' > "\$out"
''');

    final result = await (await executor.start(
      job(input: p.join(folder.path, 'gone.mov')),
    )).result;

    expect(result.status, ConversionStatus.done);
    expect(leftOver(), ['clip.mp4']);
  });

  test('a result that cannot be put in place fails and leaves no '
      'unfinished file', () async {
    // A folder already has the name the result was to get.
    await Directory(output()).create(recursive: true);
    final executor = executorRunning('''
printf 'converted' > "\$out"
''');

    final result = await (await executor.start(job())).result;

    expect(result.status, ConversionStatus.failed);
    expect(result.errorLines, isNotEmpty);
    expect(leftOver(), ['clip.mp4']);
    expect(FileSystemEntity.isDirectorySync(output()), isTrue);
  });

  test('progress that is not text does not stop the conversion', () async {
    final executor = executorRunning(r'''
printf 'converted' > "$out"
printf 'frame=\377\376\n'
echo progress=end
''');

    final result = await (await executor.start(job())).result;

    expect(result.status, ConversionStatus.done);
  });
}
