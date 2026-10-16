import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/media/media_details.dart';

void main() {
  Map<String, Object?> recorded() =>
      jsonDecode(File('test/fixtures/hlg_clip_ffprobe.json').readAsStringSync())
          as Map<String, Object?>;

  DetailSection section(
    List<DetailSection> sections,
    DetailGroup group, [
    int number = 1,
  ]) => sections.firstWhere((s) => s.group == group && s.number == number);

  String value(DetailSection section, DetailField field) =>
      section.rows.firstWhere((r) => r.field == field).value;

  group('encoding view of a recorded HLG clip', () {
    final sections = encodingDetails(recorded());

    test('describes the file', () {
      final file = section(sections, DetailGroup.file);

      expect(value(file, DetailField.container), 'QuickTime / MOV');
      expect(value(file, DetailField.duration), '0:00:02.002');
      expect(value(file, DetailField.tracks), '3');
    });

    test('describes the picture, HDR included', () {
      final video = section(sections, DetailGroup.video);

      expect(value(video, DetailField.codec), contains('HEVC'));
      expect(value(video, DetailField.codec), contains('Main 10'));
      expect(value(video, DetailField.resolution), '1280×720');
      expect(value(video, DetailField.frameRate), '29.97 fps (30000/1001)');
      expect(value(video, DetailField.bitDepth), '10-bit');
      expect(value(video, DetailField.chroma), '4:2:0');
      expect(value(video, DetailField.colorTransfer), 'arib-std-b67');
      expect(value(video, DetailField.hdr), 'HLG');
    });

    test('describes the sound', () {
      final audio = section(sections, DetailGroup.audio);

      expect(value(audio, DetailField.channels), '2 (stereo)');
      expect(value(audio, DetailField.sampleRate), '48 kHz');
      expect(value(audio, DetailField.sampleFormat), 's32, 24-bit');
    });

    test('shows the timecode track with its value', () {
      final timecode = section(sections, DetailGroup.timecode);

      expect(value(timecode, DetailField.timecode), '01:00:00:00');
    });
  });

  group('encoding view of unusual files', () {
    Map<String, Object?> withStreams(List<Map<String, Object?>> streams) => {
      'format': {'format_name': 'mov', 'duration': '60'},
      'streams': streams,
    };

    test('variable frame rate is called out', () {
      final video = section(
        encodingDetails(
          withStreams([
            {
              'codec_type': 'video',
              'codec_name': 'h264',
              'avg_frame_rate': '27400/1000',
              'r_frame_rate': '30/1',
              'pix_fmt': 'yuv420p',
            },
          ]),
        ),
        DetailGroup.video,
      );
      final row = video.rows.firstWhere(
        (r) => r.field == DetailField.frameRate,
      );

      expect(row.note, DetailNote.variable);
      expect(row.value, '27.40 fps avg, 30/1 nominal');
    });

    test('PQ with mastering and light-level data', () {
      final video = section(
        encodingDetails(
          withStreams([
            {
              'codec_type': 'video',
              'codec_name': 'hevc',
              'color_transfer': 'smpte2084',
              'side_data_list': [
                {
                  'side_data_type': 'Mastering display metadata',
                  'min_luminance': '50/10000',
                  'max_luminance': '10000000/10000',
                },
                {
                  'side_data_type': 'Content light level metadata',
                  'max_content': 1000,
                  'max_average': 400,
                },
              ],
            },
          ]),
        ),
        DetailGroup.video,
      );

      expect(value(video, DetailField.hdr), 'HDR10 (PQ)');
      expect(value(video, DetailField.masteringDisplay), '0.005–1000 cd/m²');
      expect(value(video, DetailField.lightLevel), 'MaxCLL 1000 · MaxFALL 400');
    });

    test('several sound tracks are numbered', () {
      final sections = encodingDetails(
        withStreams([
          {
            'codec_type': 'audio',
            'codec_name': 'aac',
            'tags': {'language': 'eng'},
          },
          {
            'codec_type': 'audio',
            'codec_name': 'aac',
            'tags': {'language': 'ukr'},
          },
        ]),
      );

      expect(
        value(section(sections, DetailGroup.audio, 2), DetailField.language),
        'ukr',
      );
    });

    test('an unstated colour is said to be unstated', () {
      final video = section(
        encodingDetails(
          withStreams([
            {'codec_type': 'video', 'codec_name': 'h264'},
          ]),
        ),
        DetailGroup.video,
      );
      final row = video.rows.firstWhere(
        (r) => r.field == DetailField.colorPrimaries,
      );

      expect(row.note, DetailNote.notStated);
    });
  });

  group('metadata view', () {
    test('lists every tag of the file and of each track', () {
      final sections = metadataDetails(recorded());

      expect(sections.first.group, DetailGroup.file);
      expect(sections.first.tags['make'], 'Example Camera Co');
      expect(sections.first.tags['title'], 'Example title');
      expect(
        sections.firstWhere((s) => s.group == DetailGroup.video).tags,
        containsPair('handler_name', 'VideoHandler'),
      );
    });
  });

  test('the full report is the indented JSON', () {
    expect(fullReport(recorded()), contains('\n  "streams": ['));
  });

  test('numbers read naturally', () {
    expect(formatBitrate(98000000), '98.0 Mbit/s');
    expect(formatBitrate(256000), '256 kbit/s');
    expect(formatBytes(1894563210), '1.89 GB');
    expect(formatDuration(151.251), '0:02:31.251');
  });

  group('personal tags', () {
    const personal = [
      'title',
      'artist',
      'creation_time',
      'location',
      'location-eng',
      'make',
      'model',
      'com.apple.quicktime.location.ISO6709',
      'com.apple.quicktime.make',
      'timecode',
    ];
    for (final tag in personal) {
      test('"$tag" is marked as personal', () {
        expect(isPersonalTag(tag), isTrue);
      });
    }

    const technical = [
      'major_brand',
      'compatible_brands',
      'encoder',
      'handler_name',
      'vendor_id',
      'language',
    ];
    for (final tag in technical) {
      test('"$tag" is not', () {
        expect(isPersonalTag(tag), isFalse);
      });
    }
  });
}
