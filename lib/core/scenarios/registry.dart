import 'archive.dart';
import 'extract_audio.dart';
import 'remux.dart';
import 'resolve_linux.dart';
import 'scenario.dart';
import 'share_phone.dart';
import 'strip_metadata.dart';

/// Every scenario the app offers, in display order. This list is the single
/// place a new scenario has to be added.
const scenarios = <Scenario>[
  archiveScenario,
  resolveLinuxScenario,
  sharePhoneScenario,
  extractAudioScenario,
  stripMetadataScenario,
  remuxScenario,
];

Preset? findPreset(String id) {
  for (final scenario in scenarios) {
    for (final preset in scenario.presets) {
      if (preset.id == id) return preset;
    }
  }
  return null;
}
