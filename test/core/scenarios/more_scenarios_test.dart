import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/media/media_info.dart';
import 'package:vidctrl/core/scenarios/extract_audio.dart';
import 'package:vidctrl/core/scenarios/remux.dart';
import 'package:vidctrl/core/scenarios/save_space.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';
import 'package:vidctrl/core/scenarios/strip_metadata.dart';

import '../../support/fake_media.dart';

void main() {
  const hlg = ColorInfo(
    primaries: 'bt2020',
    transfer: 'arib-std-b67',
    space: 'bt2020nc',
    range: 'tv',
  );

  group('Save space', () {
    const space = SaveSpacePreset();
    VideoEncode video(ConversionPlan plan) => plan.video as VideoEncode;
    List<String> rate(ConversionPlan plan) => [
      for (final filter in video(plan).filters)
        if (filter.startsWith('fps=')) filter.substring(4),
    ];

    test('a 4K video becomes AV1 at 1080p in a fast-start MP4', () {
      final plan = space.plan(clip(), const {}, softwareOnly);

      expect(video(plan).encoder, 'libsvtav1');
      expect(video(plan).args, containsAllInOrder(['-crf', saveSpaceCrf]));
      expect(video(plan).filters.first, startsWith('scale=1920:1920:'));
      expect(plan.muxer, 'mp4');
      expect(plan.outputArgs, containsAllInOrder(['-movflags', '+faststart']));
      expect(plan.nameSuffix, '_av1-crf$saveSpaceCrf');
    });

    test('a video that is already small enough is not resized', () {
      final plan = space.plan(
        clip(width: 1920, height: 1080),
        const {},
        softwareOnly,
      );

      expect(video(plan).filters, isEmpty);
    });

    test('a portrait video is limited by its height', () {
      final plan = space.plan(
        clip(width: 2160, height: 3840),
        const {},
        softwareOnly,
      );

      expect(video(plan).filters.first, startsWith('scale=1920:1920:'));
      expect(
        video(plan).filters.first,
        contains('force_original_aspect_ratio=decrease'),
      );
    });

    test('a changed picture says its colour samples sit on the left', () {
      final plan = space.plan(clip(), const {}, softwareOnly);

      expect(video(plan).filters.first, contains('out_chroma_loc=left'));
      expect(
        video(plan).args,
        contains('av1_metadata=chroma_sample_position=vertical'),
      );
    });

    test('more than 30 frames a second is halved', () {
      ConversionPlan at(double fps) =>
          space.plan(clip(fps: fps), const {}, softwareOnly);

      expect(rate(at(60)), ['30']);
      expect(rate(at(50)), ['25']);
      expect(rate(at(60000 / 1001)), ['30000/1001']);
      expect(rate(at(120)), ['30']);
      expect(rate(at(30)), isEmpty);
      expect(rate(at(25)), isEmpty);
    });

    test('irregular timing at 30 or less is made constant', () {
      final plan = space.plan(
        clip(fps: 29.3, nominalFps: 30),
        const {},
        softwareOnly,
      );

      expect(rate(plan), isEmpty);
      expect(plan.outputArgs, containsAllInOrder(['-fps_mode', 'cfr']));
      expect(plan.notes, contains(PlanNote.variableFrameRateFixed));
    });

    test('HDR is tone-mapped before anything else', () {
      final plan = space.plan(
        clip(pixFmt: 'yuv420p10le', color: hlg),
        const {},
        withToneMapping,
      );

      expect(video(plan).filters.first, 'zscale=t=linear:npl=100');
      expect(video(plan).filters.last, 'format=yuv420p10le');
      expect(plan.notes, [PlanNote.hdrToneMapped]);
    });

    test('without tone-mapping support the user is warned instead', () {
      final plan = space.plan(clip(color: hlg), const {}, softwareOnly);

      expect(video(plan).filters.join(), isNot(contains('tonemap')));
      expect(plan.notes, [PlanNote.hdrNotConverted]);
    });

    test('sound becomes AAC for speech; small AAC is kept', () {
      AudioAction audio(AudioStream track) =>
          space.plan(clip(audio: [track]), const {}, softwareOnly).audio;

      final large = audio(track('aac', bitRate: 320000)) as AudioEncode;
      expect(large.codec, 'aac');
      expect(large.args, ['-b:a', '96k']);
      expect(audio(track('aac', bitRate: 96000)), isA<AudioCopy>());
      expect(audio(track('aac', bitRate: null)), isA<AudioEncode>());
      expect(
        (audio(track('ac3', channels: 6)) as AudioEncode).args,
        containsAllInOrder(['-ac', '2']),
      );
    });
  });

  group('Get the sound', () {
    const extract = ExtractAudioPreset();
    ConversionPlan plan(MediaInfo input, [String format = 'original']) =>
        extract.plan(input, {'format': format}, softwareOnly);

    test('the sound is copied out untouched into a matching file', () {
      final result = plan(clip());

      expect(result.kind, PlanKind.remux);
      expect(result.video, isA<VideoNone>());
      expect(result.audio, isA<AudioCopy>());
      expect(result.extension, 'm4a');
      expect(result.firstAudioOnly, isTrue);
    });

    const containers = {
      'mp3': 'mp3',
      'opus': 'opus',
      'flac': 'flac',
      'ac3': 'ac3',
      'pcm_s24le': 'wav',
      'truehd': 'mka',
    };
    containers.forEach((codec, extension) {
      test('$codec sound is saved as .$extension', () {
        expect(plan(clip(audio: [track(codec)])).extension, extension);
      });
    });

    test('big-endian camera sound is rewritten losslessly for WAV', () {
      final result = plan(clip(audio: [track('pcm_s16be')]));

      expect((result.audio as AudioEncode).codec, 'pcm_s16le');
      expect(result.extension, 'wav');
    });

    test('asking for MP3 converts, unless it already is MP3', () {
      final converted = plan(clip(), 'mp3');
      final already = plan(clip(audio: [track('mp3')]), 'mp3');

      expect(converted.kind, PlanKind.encode);
      expect((converted.audio as AudioEncode).codec, 'libmp3lame');
      expect(already.audio, isA<AudioCopy>());
    });

    test('a silent video has nothing to extract', () {
      final result = plan(clip(audio: []));

      expect(result.kind, PlanKind.unsupported);
      expect(result.notes, [PlanNote.noAudioStream]);
    });
  });

  group('Remove personal details', () {
    const clean = StripMetadataPreset();
    ConversionPlan plan(MediaInfo input, [String mode = 'quick']) =>
        clean.plan(input, {'mode': mode}, softwareOnly);

    test('quick: everything is copied, metadata and file date are dropped', () {
      final result = plan(clip());

      expect(result.kind, PlanKind.remux);
      expect(result.video, isA<VideoCopy>());
      expect(result.audio, isA<AudioCopy>());
      expect(result.keepMetadata, isFalse);
      expect(result.keepFileDate, isFalse);
      expect(result.outputArgs, containsAllInOrder(['-map_chapters', '-1']));
    });

    test('the file stays the kind of file it was', () {
      expect(plan(clip(path: '/videos/a.mov')).extension, 'mov');
      expect(plan(clip(path: '/videos/a.mp4')).extension, 'mp4');
      expect(
        plan(clip(path: '/videos/a.mkv', container: mkvContainer)).extension,
        'mkv',
      );
    });

    test('MP4-only switches are not passed to other file types', () {
      final mkv = plan(clip(path: '/videos/a.mkv', container: mkvContainer));

      expect(mkv.outputArgs, isNot(contains('-write_tmcd')));
      expect(plan(clip()).outputArgs, contains('-write_tmcd'));
    });

    test('thorough: picture and sound are rebuilt, keeping 10-bit', () {
      final eightBit = plan(clip(), 'thorough');
      final tenBit = plan(clip(pixFmt: 'yuv420p10le'), 'thorough');

      expect(eightBit.kind, PlanKind.encode);
      expect((eightBit.video as VideoEncode).encoder, 'libx264');
      expect((tenBit.video as VideoEncode).pixFmt, 'yuv420p10le');
      expect(eightBit.audio, isA<AudioEncode>());
    });
  });

  group('Change file type', () {
    const remux = RemuxPreset();
    ConversionPlan plan(MediaInfo input, [String format = 'mp4']) =>
        remux.plan(input, {'format': format}, softwareOnly);

    test('picture and sound move into the new file untouched', () {
      final result = plan(
        clip(path: '/videos/obs.mkv', container: mkvContainer),
      );

      expect(result.kind, PlanKind.remux);
      expect(result.video, isA<VideoCopy>());
      expect(result.audio, isA<AudioCopy>());
      expect(result.extension, 'mp4');
    });

    test('a file that already is that type is left alone', () {
      expect(plan(clip(path: '/videos/a.mp4')).kind, PlanKind.skip);
      expect(plan(clip(path: '/videos/a.mov')).kind, PlanKind.remux);
    });

    test('sound the file type cannot hold is converted, and says so', () {
      final result = plan(
        clip(path: '/videos/a.mov', audio: [track('pcm_s24le')]),
      );

      expect(result.kind, PlanKind.audioOnly);
      expect((result.audio as AudioEncode).codec, 'aac');
      expect(result.notes, [PlanNote.audioConvertedToFit]);
    });

    test('lossless sound stays lossless when moving to MOV', () {
      final result = plan(
        clip(
          path: '/videos/a.mkv',
          container: mkvContainer,
          audio: [track('flac')],
        ),
        'mov',
      );

      expect((result.audio as AudioEncode).codec, 'pcm_s24le');
    });

    test('a picture the file type cannot hold is refused, not re-encoded', () {
      final result = plan(clip(path: '/videos/a.mov', video: 'prores'));

      expect(result.kind, PlanKind.unsupported);
      expect(result.notes, [PlanNote.containerCannotHold]);
    });

    test('MKV accepts anything', () {
      final result = plan(
        clip(
          path: '/videos/a.mov',
          video: 'prores',
          audio: [track('pcm_s24le')],
        ),
        'mkv',
      );

      expect(result.kind, PlanKind.remux);
      expect(result.muxer, 'matroska');
    });
  });
}
