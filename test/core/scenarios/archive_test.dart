import 'package:flutter_test/flutter_test.dart';
import 'package:tvv_videoconvertor/core/ffmpeg/capabilities.dart';
import 'package:tvv_videoconvertor/core/media/media_info.dart';
import 'package:tvv_videoconvertor/core/scenarios/archive.dart';
import 'package:tvv_videoconvertor/core/scenarios/scenario.dart';

import '../../support/fake_media.dart';

void main() {
  const preset = ArchivePreset();

  ConversionPlan plan(
    MediaInfo input, [
    OptionValues values = const {},
    Capabilities capabilities = softwareOnly,
  ]) => preset.plan(input, values, capabilities);

  VideoEncode video(ConversionPlan plan) => plan.video as VideoEncode;

  group('AV1, the default', () {
    test('encodes 10-bit 4:2:0 into a fast-start MP4', () {
      final result = plan(clip());

      expect(result.kind, PlanKind.encode);
      expect(video(result).encoder, 'libsvtav1');
      expect(video(result).pixFmt, 'yuv420p10le');
      expect(video(result).args, containsAllInOrder(['-crf', '24']));
      expect(result.muxer, 'mp4');
      expect(result.nameSuffix, '_av1-crf24');
    });

    test('uses the encoder parameters this SVT-AV1 version accepts', () {
      final result = plan(clip());

      expect(
        video(result).args,
        containsAllInOrder(['-svtav1-params', 'tune=0']),
      );
    });

    test('omits encoder parameters when the library accepts none', () {
      const bare = Capabilities(ffmpegVersion: 'test', encoders: {'libsvtav1'});
      final result = plan(clip(), const {}, bare);

      expect(video(result).args, isNot(contains('-svtav1-params')));
    });

    test('becomes HEVC when this FFmpeg cannot make AV1', () {
      const noAv1 = Capabilities(
        ffmpegVersion: 'test',
        encoders: {'libx265', 'aac'},
      );
      final result = plan(clip(), const {}, noAv1);

      expect(ArchivePreset.encodesAv1(noAv1), isFalse);
      expect(video(result).encoder, 'libx265');
      expect(result.outputArgs, containsAllInOrder(['-tag:v', 'hvc1']));
    });

    test('4:2:2 sources are reduced with an explicit Lanczos step', () {
      final result = plan(clip(pixFmt: 'yuv422p10le'));

      expect(video(result).filters, [
        'scale=flags=lanczos+accurate_rnd',
        'format=yuv420p10le',
      ]);
      expect(result.notes, contains(PlanNote.chromaReduced));
    });

    test('4:2:0 sources need no filter', () {
      expect(video(plan(clip())).filters, isEmpty);
    });
  });

  group('HEVC', () {
    test('is tagged so Apple players recognise it', () {
      final result = plan(clip(), {'codec': 'hevc'});

      expect(video(result).encoder, 'libx265');
      expect(video(result).args, containsAllInOrder(['-crf', '21']));
      expect(video(result).args, containsAllInOrder(['-profile:v', 'main10']));
      expect(result.outputArgs, containsAllInOrder(['-tag:v', 'hvc1']));
      expect(result.nameSuffix, '_hevc-crf21');
    });
  });

  group('the camera details', () {
    test('make and model are kept, which MP4 otherwise drops', () {
      for (final codec in ['av1', 'hevc']) {
        expect(
          plan(clip(), {'codec': codec}).outputArgs,
          containsAllInOrder(['-movflags', '+faststart+use_metadata_tags']),
        );
      }
    });

    test("the original's file type tags are not carried over", () {
      final result = plan(clip());

      for (final tag in ['major_brand', 'minor_version', 'compatible_brands']) {
        expect(result.outputArgs, containsAllInOrder(['-metadata', '$tag=']));
      }
    });
  });

  group('graphics card', () {
    const fast = {'speed': 'gpu'};

    test('makes AV1 when AV1 is chosen', () {
      final caps = withGpu({'hevc_nvenc', 'av1_nvenc', 'h264_nvenc'});
      final result = plan(clip(), fast, caps);

      expect(video(result).encoder, 'av1_nvenc');
      expect(video(result).args, containsAllInOrder(['-cq', '28']));
      expect(result.cost.usesGpuEncoder, isTrue);
    });

    test('makes HEVC when HEVC is chosen, even if it could make AV1', () {
      final caps = withGpu({'hevc_nvenc', 'av1_nvenc'});
      final result = plan(clip(), {...fast, 'codec': 'hevc'}, caps);

      expect(video(result).encoder, 'hevc_nvenc');
      expect(video(result).pixFmt, 'p010le');
      expect(video(result).args, containsAllInOrder(['-cq', '24']));
      expect(result.outputArgs, containsAllInOrder(['-tag:v', 'hvc1']));
    });

    test('is not used for a format the card cannot make', () {
      final caps = withGpu({'hevc_nvenc'});

      expect(ArchivePreset.gpuEncoder(caps, 'av1'), isNull);
      expect(video(plan(clip(), fast, caps)).encoder, 'libsvtav1');
    });

    test('is not offered without a working hardware encoder', () {
      expect(ArchivePreset.gpuEncoder(softwareOnly, 'av1'), isNull);
      expect(ArchivePreset.gpuEncoder(softwareOnly, 'hevc'), isNull);
      expect(video(plan(clip(), fast)).encoder, 'libsvtav1');
    });

    test('NVIDIA may use all the bitrate the level allows, and no more', () {
      final caps = withGpu({'hevc_nvenc', 'av1_nvenc'});
      for (final codec in ['av1', 'hevc']) {
        final uhd = video(plan(clip(), {...fast, 'codec': codec}, caps));
        final hd = video(
          plan(clip(width: 1920, height: 1080), {
            ...fast,
            'codec': codec,
          }, caps),
        );

        expect(uhd.args, containsAllInOrder(['-maxrate', '40M']));
        expect(uhd.args, containsAllInOrder(['-level', '5.1']));
        expect(hd.args, containsAllInOrder(['-maxrate', '20M']));
        expect(hd.args, containsAllInOrder(['-level', '4.1']));
      }
      // The main tier, which every player supports.
      expect(
        video(plan(clip(), {...fast, 'codec': 'hevc'}, caps)).args,
        containsAllInOrder(['-tier', 'main']),
      );
    });

    test('Apple hardware gets its 0-100 quality scale', () {
      final caps = withGpu({'hevc_videotoolbox'});
      final result = plan(clip(), {...fast, 'codec': 'hevc'}, caps);

      expect(video(result).args, containsAllInOrder(['-q:v', '75']));
    });
  });

  group('audio', () {
    test('modest AAC is kept untouched', () {
      final result = plan(clip());

      expect(result.audio, isA<AudioCopy>());
    });

    test('PCM from an editor export becomes AAC', () {
      final result = plan(clip(audio: [track('pcm_s24le', bitRate: 2304000)]));
      final audio = result.audio as AudioEncode;

      expect(audio.codec, 'aac');
      expect(audio.args, ['-b:a', '320k']);
    });

    test('lossless FLAC, as DaVinci Resolve exports, becomes 320k AAC', () {
      final result = plan(clip(audio: [track('flac', bitRate: 1400000)]));
      final audio = result.audio as AudioEncode;

      expect(audio.codec, 'aac');
      expect(audio.args, ['-b:a', '320k']);
    });

    test('AAC already at 320k is kept; anything above is brought down', () {
      final kept = plan(clip(audio: [track('aac', bitRate: 320000)]));
      final reduced = plan(clip(audio: [track('aac', bitRate: 512000)]));

      expect(kept.audio, isA<AudioCopy>());
      expect((reduced.audio as AudioEncode).args, ['-b:a', '320k']);
    });

    test('a single channel needs less', () {
      final result = plan(clip(audio: [track('pcm_s24le', channels: 1)]));

      expect((result.audio as AudioEncode).args, ['-b:a', '192k']);
    });

    test('surround sound gets a higher bitrate', () {
      final result = plan(clip(audio: [track('pcm_s24le', channels: 6)]));

      expect((result.audio as AudioEncode).args, ['-b:a', '512k']);
    });
  });

  test('a file without a picture is not handled', () {
    final result = plan(clip(video: null));

    expect(result.kind, PlanKind.unsupported);
  });
}
