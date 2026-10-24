import 'archive.dart';
import 'extract_audio.dart';
import 'remux.dart';
import 'resolve_linux.dart';
import 'save_space.dart';
import 'scenario.dart';
import 'strip_metadata.dart';

/// Every scenario the app offers, in display order. This list is the single
/// place a new scenario has to be added.
const scenarios = <Scenario>[
  archiveScenario,
  saveSpaceScenario,
  resolveLinuxScenario,
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

/// The goal that offers [preset].
Scenario scenarioOf(Preset preset) =>
    scenarios.firstWhere((s) => s.presets.contains(preset));
