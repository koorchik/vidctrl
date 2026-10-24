import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/technical_text.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';
import 'package:vidctrl/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  String summary(AudioAction audio) => technicalSummary(
    l10n,
    ConversionPlan(kind: PlanKind.audioOnly, audio: audio, extension: 'mp4'),
  );

  group('sound in the technical line', () {
    test('an encoder given a bitrate says it', () {
      expect(
        summary(const AudioEncode(codec: 'aac', args: ['-b:a', '320k'])),
        contains('AAC 320k'),
      );
    });

    test('a bitrate flag without its value is left out', () {
      expect(
        summary(const AudioEncode(codec: 'aac', args: ['-b:a'])),
        contains('AAC'),
      );
    });
  });

  group('format names', () {
    VideoEncode encode(String encoder, [List<String> args = const []]) =>
        VideoEncode(encoder: encoder, pixFmt: 'yuv420p10le', args: args);

    for (final (encoder, args, name) in const [
      ('libx265', <String>[], 'HEVC'),
      ('libsvtav1', <String>[], 'AV1'),
      ('libx264', <String>[], 'H.264'),
      ('hevc_nvenc', <String>[], 'HEVC · NVIDIA'),
      ('av1_nvenc', <String>[], 'AV1 · NVIDIA'),
      ('hevc_qsv', <String>[], 'HEVC · Intel'),
      ('av1_amf', <String>[], 'AV1 · AMD'),
      ('hevc_videotoolbox', <String>[], 'HEVC · Apple'),
      ('hevc_vaapi', <String>[], 'HEVC · VAAPI'),
      ('prores_ks', ['-profile:v', '0'], 'ProRes Proxy'),
      ('prores_ks', ['-profile:v', '1'], 'ProRes LT'),
      ('prores_ks', ['-profile:v', '2'], 'ProRes 422'),
      ('prores_ks', ['-profile:v', '3'], 'ProRes 422 HQ'),
      ('dnxhd', ['-profile:v', 'dnxhr_hq'], 'DNxHR HQ'),
    ]) {
      test('$encoder ${args.join(' ')} is $name', () {
        expect(codecName(encode(encoder, args)), name);
      });
    }

    test('a copy has no format of its own', () {
      expect(codecName(const VideoCopy()), isNull);
    });
  });

  group('quality settings', () {
    for (final (args, shown) in const [
      (['-crf', '20'], 'CRF 20'),
      (['-cq', '28'], 'CQ 28'),
      (['-global_quality', '24'], 'ICQ 24'),
      (['-qvbr_quality_level', '30'], 'QVBR 30'),
      (['-q:v', '60'], 'Q 60'),
      (<String>[], null),
      (['-crf'], null),
    ]) {
      test('${args.join(' ')} reads $shown', () {
        expect(
          qualitySetting(
            VideoEncode(encoder: 'libx265', pixFmt: 'yuv420p10le', args: args),
          ),
          shown,
        );
      });
    }
  });
}
