import '../ffmpeg/capabilities.dart';
import 'archive.dart';
import 'scenario.dart';

// Which of a preset's options the panel shows, and how: the same rules
// decide which options a client may set.

/// Options that have no effect with the current choices are hidden rather
/// than shown disabled, and so are those this computer cannot do: nobody can
/// pick the graphics card on a machine without a usable one.
bool optionVisible(
  Preset preset,
  PresetOption option,
  OptionValues values,
  Capabilities capabilities,
) {
  if (option.advanced) return false;
  if (preset is ArchivePreset) {
    return switch (option.id) {
      ArchivePreset.codec => ArchivePreset.encodesAv1(capabilities),
      ArchivePreset.speed =>
        ArchivePreset.gpuEncoder(
              capabilities,
              ArchivePreset.formatFor(values, capabilities),
            ) !=
            null,
      _ => true,
    };
  }
  if (preset.id == 'resolve.studio' && option.id == 'quality') {
    return preset.choice(values, 'convertVideo') == 'yes';
  }
  return true;
}

/// A yes/no option is shown as a switch instead of two buttons.
bool isSwitch(PresetOption option) =>
    option.choices.length == 2 &&
    option.choices.contains('yes') &&
    option.choices.contains('no');

/// Options for people who want more control, shown under "More options".
/// As with the basic ones, an option that would change nothing is hidden.
bool advancedOptionVisible(
  Preset preset,
  PresetOption option,
  OptionValues values,
) {
  if (!option.advanced) return false;
  if (option.id == 'codec') {
    final convertsPicture =
        preset.id == 'resolve.free' ||
        preset.choice(values, 'convertVideo') == 'yes';
    return convertsPicture && preset.choice(values, 'quality') != 'smallest';
  }
  return true;
}
