import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/estimate/size_estimator.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../../support/fake_media.dart';

void main() {
  group('where samples are taken', () {
    Duration seconds(double s) => Duration(milliseconds: (s * 1000).round());

    test('a short video is encoded completely', () {
      final samples = estimationSamples(seconds(5));

      expect(samples, hasLength(1));
      expect(samples.single.start, Duration.zero);
      expect(samples.single.length, seconds(5));
    });

    test('a clip under half a minute is sampled once, in the middle', () {
      final samples = estimationSamples(seconds(20));

      expect(samples.single.start, seconds(8.5));
      expect(samples.single.length, seconds(3));
    });

    test('longer videos are sampled at several points along their length', () {
      expect(estimationSamples(seconds(90)), hasLength(2));
      expect(estimationSamples(const Duration(minutes: 10)), hasLength(3));
      expect(estimationSamples(const Duration(hours: 2)), hasLength(6));
    });

    test('no sample reaches past the end', () {
      const length = Duration(minutes: 3);
      for (final sample in estimationSamples(length)) {
        expect(sample.start + sample.length, lessThanOrEqualTo(length));
        expect(sample.start, greaterThanOrEqualTo(Duration.zero));
      }
    });
  });

  group('sound size', () {
    const minute = 60;
    ConversionPlan withAudio(AudioAction audio, {bool firstOnly = false}) =>
        ConversionPlan(
          kind: PlanKind.encode,
          audio: audio,
          firstAudioOnly: firstOnly,
        );

    test('copied sound keeps its size', () {
      final bytes = audioOutputBytes(
        clip(audio: [track('aac', bitRate: 160000)]),
        withAudio(const AudioCopy()),
      );

      expect(bytes, 160000 * minute ~/ 8);
    });

    test('encoded sound takes the bitrate it is given', () {
      final bytes = audioOutputBytes(
        clip(),
        withAudio(const AudioEncode(codec: 'aac', args: ['-b:a', '256k'])),
      );

      expect(bytes, 256000 * minute ~/ 8);
    });

    test('PCM size follows sample rate, channels and bit depth', () {
      final bytes = audioOutputBytes(
        clip(),
        withAudio(const AudioEncode(codec: 'pcm_s24le')),
      );

      expect(bytes, 48000 * 2 * 24 * minute ~/ 8);
    });

    test('only the first track counts when only it is taken', () {
      final two = clip(audio: [track('aac'), track('aac')]);

      expect(
        audioOutputBytes(two, withAudio(const AudioCopy(), firstOnly: true)),
        audioOutputBytes(two, withAudio(const AudioCopy())) ~/ 2,
      );
    });
  });

  group('calculated without encoding', () {
    test('a copy is as large as what it copies', () {
      const plan = ConversionPlan(kind: PlanKind.remux);
      final info = clip(videoBitRate: 80000000);

      expect(
        estimateWithoutEncoding(info, plan)!.bytes,
        80000000 * 60 ~/ 8 + 160000 * 60 ~/ 8,
      );
    });

    test('a quality-targeted encode has to be measured', () {
      const plan = ConversionPlan(
        kind: PlanKind.encode,
        video: VideoEncode(encoder: 'libx265', pixFmt: 'yuv420p10le'),
      );

      expect(estimateWithoutEncoding(clip(), plan), isNull);
    });

    test('nothing is estimated for a file that is skipped', () {
      expect(
        estimateWithoutEncoding(clip(), const ConversionPlan.skip()),
        isNull,
      );
    });
  });

  test('samples are scaled up to the whole video, sound added', () {
    const plan = ConversionPlan(
      kind: PlanKind.encode,
      video: VideoEncode(encoder: 'libx265', pixFmt: 'yuv420p10le'),
    );
    final estimate = extrapolateSamples(
      info: clip(audio: []),
      plan: plan,
      sampleBytes: 3000000,
      sampled: const Duration(seconds: 6),
      spent: const Duration(seconds: 12),
    );

    expect(estimate.bytes, 30000000);
    expect(estimate.time, const Duration(minutes: 2));
    expect(estimate.measured, isTrue);
  });
}
