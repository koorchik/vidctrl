import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/scenarios/option_visibility.dart';
import 'package:vidctrl/core/scenarios/registry.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../../support/fake_media.dart';

void main() {
  PresetOption option(Preset preset, String id) =>
      preset.options.firstWhere((o) => o.id == id);

  group('archive', () {
    final archive = findPreset('archive.master')!;

    bool shown(String id, Capabilities capabilities) =>
        optionVisible(archive, option(archive, id), const {}, capabilities);

    test('the format is a choice only where the FFmpeg has AV1', () {
      expect(shown('codec', softwareOnly), isTrue);
      const noAv1 = Capabilities(ffmpegVersion: 'test', encoders: {'libx265'});
      expect(shown('codec', noAv1), isFalse);
    });

    test('the graphics card is offered only where it can encode', () {
      expect(shown('speed', softwareOnly), isFalse);
      expect(shown('speed', withGpu({'av1_nvenc', 'hevc_nvenc'})), isTrue);
    });
  });

  group('Resolve Studio', () {
    final studio = findPreset('resolve.studio')!;

    test('the size of the picture matters only when it is converted', () {
      bool qualityShown(String convert) => optionVisible(
        studio,
        option(studio, 'quality'),
        {'convertVideo': convert},
        softwareOnly,
      );

      expect(qualityShown('no'), isFalse);
      expect(qualityShown('yes'), isTrue);
    });

    test('the codec is for More options, and only when it changes '
        'something', () {
      final codec = option(studio, 'codec');
      expect(optionVisible(studio, codec, const {}, softwareOnly), isFalse);
      expect(advancedOptionVisible(studio, codec, const {}), isFalse);
      expect(
        advancedOptionVisible(studio, codec, {'convertVideo': 'yes'}),
        isTrue,
      );
      expect(
        advancedOptionVisible(studio, codec, {
          'convertVideo': 'yes',
          'quality': 'smallest',
        }),
        isFalse,
      );
    });

    test('a yes/no option is a switch', () {
      expect(isSwitch(option(studio, 'convertVideo')), isTrue);
      expect(isSwitch(option(studio, 'quality')), isFalse);
    });
  });
}
