import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/media/media_info.dart';
import 'package:vidctrl/core/scenarios/archive.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

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
      expect(video(result).args, containsAllInOrder(['-crf', '35']));
      expect(result.muxer, 'mp4');
      expect(result.nameSuffix, '_av1-crf35');
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
        'scale=flags=lanczos+accurate_rnd:out_chroma_loc=left',
        'format=yuv420p10le',
      ]);
      expect(result.notes, contains(PlanNote.chromaReduced));
    });

    test('4:2:0 sources need no filter', () {
      expect(video(plan(clip())).filters, isEmpty);
    });
  });

  group('where the colour samples sit', () {
    List<String> marks(ConversionPlan plan) {
      final args = video(plan).args;
      final at = args.indexOf('-bsf:v');
      return at < 0 ? const [] : args.sublist(at, at + 2);
    }

    // A camera's 8-bit video loses the place on its way to 10 bits, so AV1
    // is told it after encoding.
    for (final (location, mark) in [
      ('left', ['-bsf:v', 'av1_metadata=chroma_sample_position=vertical']),
      ('topleft', ['-bsf:v', 'av1_metadata=chroma_sample_position=colocated']),
      // AV1 has no name for these.
      ('center', <String>[]),
      (null, <String>[]),
    ]) {
      test(
        'AV1 of a video with "$location" says ${mark.isEmpty ? 'nothing' : mark.last}',
        () {
          expect(marks(plan(clip(chromaLocation: location))), mark);
        },
      );
    }

    test('a 4:2:2 video made 4:2:0 gets the MPEG place, and says so', () {
      final result = plan(clip(pixFmt: 'yuv422p10le'));

      expect(video(result).filters.first, contains('out_chroma_loc=left'));
      expect(marks(result), [
        '-bsf:v',
        'av1_metadata=chroma_sample_position=vertical',
      ]);
    });

    test('AV1 from the graphics card says it too', () {
      final result = plan(clip(chromaLocation: 'left'), {
        'speed': 'gpu',
      }, withGpu({'av1_nvenc'}));

      expect(video(result).encoder, 'av1_nvenc');
      expect(marks(result), contains(endsWith('=vertical')));
    });

    test('HEVC needs no mark: it says "left" when it says nothing', () {
      final result = plan(clip(chromaLocation: 'left'), {'codec': 'hevc'});

      expect(marks(result), isEmpty);
    });
  });

  group('irregular frame timing', () {
    final vfr = clip(fps: 27.4, nominalFps: 30);

    // A filter, not `-fps_mode cfr`, which repeats a long frame of a screen
    // recording over the frames after it.
    for (final (name, values, capabilities) in [
      ('AV1', const <String, String>{}, softwareOnly),
      ('HEVC', const {'codec': 'hevc'}, softwareOnly),
      ('the graphics card', const {'speed': 'gpu'}, withGpu({'av1_nvenc'})),
    ]) {
      test('is made constant by a filter, in $name', () {
        final result = plan(vfr, values, capabilities);

        expect(video(result).filters, ['fps=30']);
        expect(result.outputArgs, isNot(contains('-fps_mode')));
        expect(result.outputArgs, isNot(contains('-r')));
        expect(result.notes, contains(PlanNote.variableFrameRateFixed));
      });
    }

    test('comes before making the picture 4:2:0', () {
      final result = plan(clip(fps: 27.4, nominalFps: 30, pixFmt: 'yuv422p'));

      expect(video(result).filters.first, 'fps=30');
      expect(video(result).filters, contains(startsWith('scale=')));
    });

    test('a constant rate is left as it is', () {
      expect(video(plan(clip())).filters, isEmpty);
    });
  });

  group('HEVC', () {
    test('is tagged so Apple players recognise it', () {
      final result = plan(clip(), {'codec': 'hevc'});

      expect(video(result).encoder, 'libx265');
      expect(video(result).args, containsAllInOrder(['-crf', '24']));
      expect(video(result).args, containsAllInOrder(['-profile:v', 'main10']));
      expect(result.outputArgs, containsAllInOrder(['-tag:v', 'hvc1']));
      expect(result.nameSuffix, '_hevc-crf24');
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
      expect(video(result).args, containsAllInOrder(['-cq', '32']));
      expect(result.cost.usesGpuEncoder, isTrue);
    });

    test('makes HEVC when HEVC is chosen, even if it could make AV1', () {
      final caps = withGpu({'hevc_nvenc', 'av1_nvenc'});
      final result = plan(clip(), {...fast, 'codec': 'hevc'}, caps);

      expect(video(result).encoder, 'hevc_nvenc');
      expect(video(result).pixFmt, 'p010le');
      expect(video(result).args, containsAllInOrder(['-cq', '26']));
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

      expect(video(result).args, containsAllInOrder(['-q:v', '65']));
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

  group('a better quality for one video', () {
    test('AV1 may go from its standard 35 down to 20', () {
      final range = preset.qualityRange(plan(clip()))!;

      expect((range.standard, range.best), (35, 20));
    });

    test('HEVC from its standard 24 down to 16', () {
      final range = preset.qualityRange(plan(clip(), {'codec': 'hevc'}))!;

      expect((range.standard, range.best), (24, 16));
    });

    test('a graphics card has no number to change', () {
      final result = plan(clip(), {'speed': 'gpu'}, withGpu({'av1_nvenc'}));

      expect(preset.qualityRange(result), isNull);
    });

    test('the raised number is used and named', () {
      final raised = preset.withQuality(plan(clip()), 23);

      expect(video(raised).args, containsAllInOrder(['-crf', '23']));
      expect(video(raised).args, isNot(contains('35')));
      expect(raised.nameSuffix, '_av1-crf23');
      // Everything else stays.
      expect(raised.muxer, 'mp4');
      expect(video(raised).args, contains('-svtav1-params'));
    });

    test('a result that needs a look says so in its name', () {
      final marked = preset.withQuality(plan(clip()), 20, belowTarget: true);

      expect(marked.nameSuffix, '_av1-crf20-check');
    });

    test('a graphics card result is only marked', () {
      final gpu = plan(clip(), {'speed': 'gpu'}, withGpu({'av1_nvenc'}));

      final marked = preset.withQuality(gpu, null, belowTarget: true);

      expect(marked.nameSuffix, '_av1-nvenc-cq32-check');
      expect(video(marked).args, video(gpu).args);
    });
  });

  test('a file without a picture is not handled', () {
    final result = plan(clip(video: null));

    expect(result.kind, PlanKind.unsupported);
  });
}
