import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/media/ffprobe.dart';
import 'package:vidctrl/core/media/media_info.dart';

import '../../support/fake_media.dart';

void main() {
  test('an ffprobe that cannot be run reads as an unreadable file', () async {
    final missing = Ffprobe(
      [
        Directory.systemTemp.path,
        'no-such-folder',
        'ffprobe',
      ].join(Platform.pathSeparator),
    );

    await expectLater(
      missing.probe('clip.mp4'),
      throwsA(isA<FfprobeException>()),
    );
  });

  group('pixel format', () {
    const depths = {
      'yuv420p': 8,
      'yuvj420p': 8,
      'nv12': 8,
      'yuv420p10le': 10,
      'yuv422p10le': 10,
      'p010le': 10,
      'yuv444p12le': 12,
      'gbrp16le': 16,
    };
    depths.forEach((pixFmt, depth) {
      test('$pixFmt is $depth-bit', () {
        expect(bitDepthOfPixFmt(pixFmt), depth);
      });
    });

    const chroma = {
      'yuv420p': ChromaSubsampling.yuv420,
      'p010le': ChromaSubsampling.yuv420,
      'yuv422p10le': ChromaSubsampling.yuv422,
      'p210le': ChromaSubsampling.yuv422,
      'yuv444p': ChromaSubsampling.yuv444,
      'gbrp10le': ChromaSubsampling.yuv444,
    };
    chroma.forEach((pixFmt, expected) {
      test('$pixFmt is ${expected.name}', () {
        expect(chromaOfPixFmt(pixFmt), expected);
      });
    });
  });

  group('variable frame rate', () {
    test('a steady camera clip is constant', () {
      expect(clip(fps: 29.97).video!.isVariableFrameRate, isFalse);
    });

    test('a rounding difference is not variable', () {
      final video = clip(fps: 29.97, nominalFps: 30000 / 1001).video!;
      expect(video.isVariableFrameRate, isFalse);
    });

    test('a phone clip averaging below its nominal rate is variable', () {
      final video = clip(fps: 27.4, nominalFps: 30).video!;
      expect(video.isVariableFrameRate, isTrue);
    });

    test('a nominal rate of twice the average is field signalling', () {
      final video = clip(fps: 25, nominalFps: 50).video!;
      expect(video.isVariableFrameRate, isFalse);
    });
  });

  group('ffprobe report', () {
    final report = <String, dynamic>{
      'format': {
        'format_name': 'mov,mp4,m4a,3gp,3g2,mj2',
        'duration': '151.251000',
        'size': '1894563210',
        'bit_rate': '100207616',
        'tags': {'creation_time': '2026-05-01T10:00:00.000000Z'},
      },
      'streams': [
        {
          'index': 0,
          'codec_type': 'video',
          'codec_name': 'hevc',
          'profile': 'Main 10',
          'width': 3840,
          'height': 2160,
          'pix_fmt': 'yuv420p10le',
          'r_frame_rate': '30000/1001',
          'avg_frame_rate': '30000/1001',
          'bit_rate': '98000000',
          'color_range': 'tv',
          'color_space': 'bt2020nc',
          'color_transfer': 'arib-std-b67',
          'color_primaries': 'bt2020',
          'side_data_list': [
            {'side_data_type': 'Display Matrix', 'rotation': -90},
          ],
        },
        {
          'index': 1,
          'codec_type': 'audio',
          'codec_name': 'pcm_s24le',
          'channels': 2,
          'sample_rate': '48000',
          'bit_rate': '2304000',
          'tags': {'language': 'eng'},
        },
        {'index': 2, 'codec_type': 'data', 'codec_tag_string': 'tmcd'},
      ],
    };

    test('reads container, picture and sound', () {
      final info = parseFfprobeJson('/videos/clip.mov', report);

      expect(info.isMovFamily, isTrue);
      expect(info.duration, const Duration(microseconds: 151251000));
      expect(info.sizeBytes, 1894563210);
      expect(info.video!.codec, 'hevc');
      expect(info.video!.bitDepth, 10);
      expect(info.video!.frameRate, closeTo(29.97, 0.001));
      expect(info.video!.color.isHdr, isTrue);
      expect(info.video!.rotation, 270);
      expect(info.audio.single.codec, 'pcm_s24le');
      expect(info.audio.single.isPcm, isTrue);
      expect(info.audio.single.language, 'eng');
    });

    test('cover art is not mistaken for the video', () {
      final withCover = <String, dynamic>{
        'format': {'format_name': 'mp3', 'duration': '10'},
        'streams': [
          {'index': 0, 'codec_type': 'audio', 'codec_name': 'mp3'},
          {
            'index': 1,
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'disposition': {'attached_pic': 1},
          },
        ],
      };

      expect(parseFfprobeJson('/music/song.mp3', withCover).video, isNull);
    });

    test('an untagged colour field stays unknown', () {
      final untagged = <String, dynamic>{
        'format': {'format_name': 'mov', 'duration': '1'},
        'streams': [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'h264',
            'color_transfer': 'unknown',
            'chroma_location': 'unspecified',
            'r_frame_rate': '0/0',
          },
        ],
      };
      final video = parseFfprobeJson('/videos/a.mov', untagged).video!;

      expect(video.color.transfer, isNull);
      expect(video.chromaLocation, isNull);
      expect(video.nominalFrameRate, isNull);
    });

    test('where the colour samples sit is read', () {
      final camera = <String, dynamic>{
        'format': {'format_name': 'mov', 'duration': '1'},
        'streams': [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'h264',
            'pix_fmt': 'yuvj420p',
            'chroma_location': 'left',
          },
        ],
      };

      expect(
        parseFfprobeJson('/videos/a.mov', camera).video!.chromaLocation,
        'left',
      );
    });
  });
}
