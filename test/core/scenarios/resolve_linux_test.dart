import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/media/media_info.dart';
import 'package:vidctrl/core/scenarios/resolve_linux.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../../support/fake_media.dart';

void main() {
  const studio = ResolveLinuxPreset.studio;
  const free = ResolveLinuxPreset.free;

  ConversionPlan plan(
    ResolveLinuxPreset preset,
    MediaInfo input, [
    OptionValues values = const {},
    Capabilities capabilities = softwareOnly,
  ]) => preset.plan(input, values, capabilities);

  group('Studio', () {
    test('Nikon H.265 10-bit with PCM audio needs nothing', () {
      final result = plan(
        studio,
        clip(video: 'hevc', pixFmt: 'yuv420p10le', audio: [track('pcm_s24le')]),
      );

      expect(result.kind, PlanKind.skip);
      expect(result.notes, contains(PlanNote.alreadyCompatible));
    });

    test('H.264 with AAC keeps the video and converts only the audio', () {
      final result = plan(studio, clip());

      expect(result.kind, PlanKind.audioOnly);
      expect(result.video, isA<VideoCopy>());
      expect((result.audio as AudioEncode).codec, 'pcm_s24le');
      expect(result.muxer, 'mov');
      expect(result.extension, 'mov');
    });

    test('one AAC track among PCM tracks still triggers the audio fix', () {
      final result = plan(
        studio,
        clip(audio: [track('pcm_s16le'), track('aac')]),
      );

      expect(result.kind, PlanKind.audioOnly);
    });

    test('MP3 audio is converted, as only constant-bitrate MP3 is read', () {
      expect(
        plan(studio, clip(audio: [track('mp3')])).kind,
        PlanKind.audioOnly,
      );
    });

    test('AC-3 audio is converted: Resolve plays it silent or distorted', () {
      for (final container in [movContainer, mkvContainer]) {
        final result = plan(
          studio,
          clip(container: container, audio: [track('ac3')]),
        );

        expect(result.kind, PlanKind.audioOnly, reason: container);
        expect((result.audio as AudioEncode).codec, 'pcm_s24le');
      }
    });

    test('Opus in an MP4 is read as is', () {
      expect(plan(studio, clip(audio: [track('opus')])).kind, PlanKind.skip);
    });

    test('Opus in an MKV is silent in Resolve, so it becomes PCM', () {
      final result = plan(
        studio,
        clip(container: mkvContainer, audio: [track('opus')]),
      );

      expect(result.kind, PlanKind.audioOnly);
      expect(result.muxer, 'mov');
    });

    test('VP9 with Opus from a WebM moves to an MP4, the Opus copied', () {
      final result = plan(
        studio,
        clip(container: mkvContainer, video: 'vp9', audio: [track('opus')]),
      );

      expect(result.kind, PlanKind.remux);
      expect(result.muxer, 'mp4');
      expect(result.audio, isA<AudioCopy>());
    });

    test(
      'a copied picture keeps its sync: no B-frame delay in the edit list',
      () {
        for (final input in [
          clip(),
          clip(container: 'mpegts', audio: [track('pcm_s16le')]),
          clip(video: 'av1'),
        ]) {
          expect(plan(studio, input).outputArgs, [
            '-movflags',
            '+negative_cts_offsets',
          ], reason: input.formatName);
        }
      },
    );

    test('a picture from an AVI is copied without time offsets', () {
      final result = plan(
        studio,
        clip(container: 'avi', audio: [track('pcm_s16le')]),
      );

      expect(result.kind, PlanKind.remux);
      expect(result.outputArgs, isEmpty);
    });

    test('MPEG-4 Part 2 from an AVI is re-encoded, as moved it does not '
        'decode', () {
      final result = plan(
        studio,
        clip(container: 'avi', video: 'mpeg4', audio: [track('mp3')]),
      );

      expect(result.kind, PlanKind.encode);
      expect((result.video as VideoEncode).encoder, 'prores_ks');
    });

    test('MPEG-4 Part 2 in a MOV is kept', () {
      expect(
        plan(studio, clip(video: 'mpeg4', audio: [track('pcm_s16le')])).kind,
        PlanKind.skip,
      );
    });

    test('a file with no audio at all is ready as is', () {
      expect(plan(studio, clip(audio: [])).kind, PlanKind.skip);
    });

    test('readable streams in an unreadable container are only re-wrapped', () {
      final result = plan(
        studio,
        clip(container: 'avi', audio: [track('pcm_s16le')]),
      );

      expect(result.kind, PlanKind.remux);
      expect(result.audio, isA<AudioCopy>());
    });

    test('AV1 goes to MP4 with FLAC, as MOV cannot hold it', () {
      final result = plan(studio, clip(video: 'av1'));

      expect(result.kind, PlanKind.audioOnly);
      expect(result.muxer, 'mp4');
      expect((result.audio as AudioEncode).codec, 'flac');
    });

    test('H.265 4:2:2 is kept, with a warning about the graphics card', () {
      final result = plan(
        studio,
        clip(video: 'hevc', pixFmt: 'yuv422p10le', audio: [track('pcm_s24le')]),
      );

      expect(result.kind, PlanKind.skip);
      expect(result.notes, contains(PlanNote.hevc422MayPlayChoppily));
    });

    test('variable frame rate forces a constant-rate re-encode', () {
      final result = plan(studio, clip(fps: 27.4, nominalFps: 30));

      expect(result.kind, PlanKind.encode);
      expect((result.video as VideoEncode).filters, ['fps=30']);
      expect(result.outputArgs, isEmpty);
      expect(result.notes, contains(PlanNote.variableFrameRateFixed));
    });

    test('the AV1 intermediate is made constant-rate before 4:2:0', () {
      final result = plan(
        free,
        clip(fps: 27.4, nominalFps: 30, pixFmt: 'yuv422p10le'),
        {'quality': 'smallest'},
      );

      final filters = (result.video as VideoEncode).filters;
      expect(filters.first, 'fps=30');
      expect(filters, contains(startsWith('scale=')));
      expect(result.outputArgs, isEmpty);
    });

    test('"convert video too" re-encodes H.264 like the free edition', () {
      final result = plan(studio, clip(), {'convertVideo': 'yes'});

      expect(result.kind, PlanKind.encode);
      expect((result.video as VideoEncode).encoder, 'prores_ks');
    });

    test('a file without a picture is not something this preset handles', () {
      final result = plan(studio, clip(video: null));

      expect(result.kind, PlanKind.unsupported);
      expect(result.notes, [PlanNote.noVideoStream]);
    });
  });

  group('Free', () {
    test('H.264 becomes 10-bit ProRes 422 with PCM audio by default', () {
      final result = plan(free, clip());
      final video = result.video as VideoEncode;

      expect(result.kind, PlanKind.encode);
      expect(video.encoder, 'prores_ks');
      expect(video.pixFmt, 'yuv422p10le');
      expect(video.args, containsAllInOrder(['-profile:v', '2']));
      expect((result.audio as AudioEncode).codec, 'pcm_s24le');
      expect(result.muxer, 'mov');
    });

    test('H.265 with PCM is not ready: the free edition cannot decode it', () {
      final result = plan(
        free,
        clip(video: 'hevc', audio: [track('pcm_s24le')]),
      );

      expect(result.kind, PlanKind.encode);
    });

    test('ProRes with PCM is ready as is', () {
      final result = plan(
        free,
        clip(
          video: 'prores',
          pixFmt: 'yuv422p10le',
          audio: [track('pcm_s24le')],
        ),
      );

      expect(result.kind, PlanKind.skip);
    });

    const proresProfiles = {'best': '3', 'balanced': '2', 'smaller': '1'};
    proresProfiles.forEach((quality, profile) {
      test('quality "$quality" selects ProRes profile $profile', () {
        final video =
            plan(free, clip(), {'quality': quality}).video as VideoEncode;

        expect(video.args, containsAllInOrder(['-profile:v', profile]));
      });
    });

    test('ProRes 422 size estimate follows the published bitrate', () {
      // UHD at 30 fps is 589 Mbit/s: one minute is about 4.4 GB plus audio.
      final result = plan(free, clip(fps: 30));

      expect(result.estimatedBytes, closeTo(4.43e9, 0.05e9));
    });

    test('the estimate scales with resolution', () {
      final uhd = plan(free, clip(fps: 30)).estimatedBytes!;
      final hd = plan(
        free,
        clip(fps: 30, width: 1920, height: 1080),
      ).estimatedBytes!;

      expect(hd / uhd, closeTo(0.25, 0.01));
    });

    test('DNxHR picks the 10-bit profile for 10-bit sources', () {
      final video =
          plan(free, clip(video: 'hevc', pixFmt: 'yuv420p10le'), {
                'codec': 'dnxhr',
              }).video
              as VideoEncode;

      expect(video.encoder, 'dnxhd');
      expect(video.pixFmt, 'yuv422p10le');
      expect(video.args, containsAllInOrder(['-profile:v', 'dnxhr_hqx']));
    });

    test('DNxHR stays 8-bit for 8-bit sources', () {
      final video =
          plan(free, clip(), {'codec': 'dnxhr', 'quality': 'smaller'}).video
              as VideoEncode;

      expect(video.pixFmt, 'yuv422p');
      expect(video.args, containsAllInOrder(['-profile:v', 'dnxhr_sq']));
    });

    test('"smallest" uses the graphics card for AV1 when it can', () {
      final result = plan(free, clip(), {
        'quality': 'smallest',
      }, withGpu({'av1_nvenc'}));

      expect((result.video as VideoEncode).encoder, 'av1_nvenc');
      expect(result.muxer, 'mp4');
      expect(result.notes, contains(PlanNote.experimentalAv1Intermediate));
      expect(result.cost.usesGpuEncoder, isTrue);
    });

    test('"smallest" falls back to software AV1 without a suitable card', () {
      final result = plan(free, clip(), {'quality': 'smallest'});

      expect((result.video as VideoEncode).encoder, 'libsvtav1');
    });

    test('"smallest" AV1 says where its colour samples sit', () {
      for (final capabilities in [
        softwareOnly,
        withGpu({'av1_nvenc'}),
      ]) {
        final video =
            plan(free, clip(chromaLocation: 'left'), {
                  'quality': 'smallest',
                }, capabilities).video
                as VideoEncode;

        expect(
          video.args,
          containsAllInOrder([
            '-bsf:v',
            'av1_metadata=chroma_sample_position=vertical',
          ]),
          reason: video.encoder,
        );
      }
    });

    test('an unknown option value falls back to the default', () {
      final video =
          plan(free, clip(), {'quality': 'nonsense'}).video as VideoEncode;

      expect(video.args, containsAllInOrder(['-profile:v', '2']));
    });
  });
}
