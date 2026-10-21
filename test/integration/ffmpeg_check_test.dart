@Tags(['ffmpeg', 'ffmpeg_check'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/runner.dart';
import 'package:vidctrl/core/media/ffprobe.dart';
import 'package:vidctrl/core/media/media_info.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/archive.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../support/test_media.dart';

/// The quick check that the installed FFmpeg can do what the app asks of it:
/// it is found, it has the encoders the presets rely on, one short clip goes
/// through a conversion from start to finish, and the archive goal's AV1
/// comes as close to the original as it should. It takes seconds, so it is
/// what CI runs on every system:
///
///   flutter test --tags ffmpeg_check
///
/// The real conversions of every goal are in `conversion_test.dart`. They
/// take minutes of encoding and are run on a developer's machine.
void main() {
  TestMedia? media;
  late Capabilities capabilities;

  // The conversion tests skip themselves without FFmpeg. Here a missing
  // FFmpeg is a failure: finding that out is what the check is for.
  setUpAll(() async {
    media = await TestMedia.create();
    if (media == null) fail('ffmpeg and ffprobe were not found on the PATH');
    capabilities = await CapabilityProbe(media!.paths.ffmpeg).detect();
  });

  tearDownAll(() async => media?.dispose());

  test('FFmpeg is found and says which version it is', () {
    expect(capabilities.ffmpegVersion, isNot('unknown'));
    // Shown in the test output, so a CI log says what was checked.
    // ignore: avoid_print
    print('FFmpeg ${capabilities.ffmpegVersion} at ${media!.paths.ffmpeg}');
  });

  test('it has the software encoders the presets rely on', () {
    expect(
      capabilities.encoders,
      containsAll([
        'libsvtav1',
        'libx265',
        'libx264',
        'prores_ks',
        'dnxhd',
        'aac',
      ]),
    );
  });

  test('SVT-AV1 accepts one of the parameter sets the app knows', () {
    expect(svtAv1ParamCandidates, contains(capabilities.svtAv1Params));
  });

  // The build of SVT-AV1 once shipped for macOS made blockier pictures than
  // the same settings make elsewhere, at the same size: a fault in its Arm
  // code (39.5 against 41.4 dB on a 4K camera clip). This test picture shows
  // it too: SVT-AV1 2.3 and 4.2 give it 45.1 to 46.2 dB, on x86 and on
  // Apple's chips, and that build gave 42.5.
  test(
    'AV1 from the archive goal comes as close to the original as it should',
    () async {
      if (!ArchivePreset.encodesAv1(capabilities)) {
        markTestSkipped('this FFmpeg has no SVT-AV1');
        return;
      }
      final source = await media!.clip(
        'pattern.mkv',
        video: const ['-c:v', 'ffv1'],
        size: '1280x720',
        rate: '30',
        seconds: 1,
        audio: const [],
      );
      final info = await Ffprobe(media!.paths.ffprobe).probe(source);
      final plan = const ArchivePreset().plan(info, const {
        ArchivePreset.codec: 'av1',
      }, capabilities);
      expect((plan.video as VideoEncode).encoder, 'libsvtav1');

      final output = await _convert(media!, info, plan);
      final comparison = await QualityMeter(FfmpegRunner(media!.paths.ffmpeg))
          .start(original: info, result: output);
      final result = await comparison.result;
      expect(
        result.status,
        ComparisonStatus.done,
        reason: result.errorLines.join('\n'),
      );
      // Shown in the test output, so a CI log says what each system made.
      // ignore: avoid_print
      print('AV1 from the archive goal: XPSNR ${result.lumaDb} dB');
      expect(result.lumaDb, greaterThan(44));
    },
  );

  test('a short clip converts with the default settings', () async {
    final ffprobe = Ffprobe(media!.paths.ffprobe);
    final source = await media!.clip('clip.mp4', seconds: 1);
    final info = await ffprobe.probe(source);
    final plan = const ArchivePreset().plan(info, const {}, capabilities);
    expect(plan.kind, PlanKind.encode);

    final output = await ffprobe.probe(await _convert(media!, info, plan));
    expect(output.video!.codec, 'av1');
    expect(output.audio, isNotEmpty);
  });
}

/// Converts [info] by [plan] next to it and returns the output's path.
Future<String> _convert(
  TestMedia media,
  MediaInfo info,
  ConversionPlan plan,
) async {
  final handle = await JobExecutor(FfmpegRunner(media.paths.ffmpeg)).start(
    ConversionJob(
      input: info,
      plan: plan,
      outputPath: planOutputPath(
        sourcePath: info.path,
        settings: const OutputSettings(),
        suffix: plan.nameSuffix,
        extension: plan.extension,
        exists: (path) => File(path).existsSync(),
      ),
    ),
  );
  final result = await handle.result;
  expect(
    result.status,
    ConversionStatus.done,
    reason: result.errorLines.join('\n'),
  );
  return result.outputPath!;
}
