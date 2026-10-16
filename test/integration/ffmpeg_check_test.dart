@Tags(['ffmpeg', 'ffmpeg_check'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/runner.dart';
import 'package:vidctrl/core/media/ffprobe.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/archive.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../support/test_media.dart';

/// The quick check that the installed FFmpeg can do what the app asks of it:
/// it is found, it has the encoders the presets rely on, and one short clip
/// goes through a conversion from start to finish. It takes seconds, so it
/// is what CI runs on every system:
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

  test('a short clip converts with the default settings', () async {
    final ffprobe = Ffprobe(media!.paths.ffprobe);
    final source = await media!.clip('clip.mp4', seconds: 1);
    final info = await ffprobe.probe(source);
    final plan = const ArchivePreset().plan(info, const {}, capabilities);
    expect(plan.kind, PlanKind.encode);

    final handle = await JobExecutor(FfmpegRunner(media!.paths.ffmpeg)).start(
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

    final output = await ffprobe.probe(result.outputPath!);
    expect(output.video!.codec, 'av1');
    expect(output.audio, isNotEmpty);
  });
}
