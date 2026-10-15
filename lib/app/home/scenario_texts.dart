import 'package:flutter/material.dart';

import '../../core/ffmpeg/capabilities.dart';
import '../../core/scenarios/archive.dart';
import '../../core/scenarios/scenario.dart';
import '../../l10n/app_localizations.dart';

/// The words and icons shown for scenarios, presets and their options.
///
/// The conversion engine knows these only by id. A new scenario needs its
/// texts added here and in the ARB files; no other UI code changes.

IconData scenarioIcon(String scenarioId) => switch (scenarioId) {
  'archive' => Icons.inventory_2_rounded,
  'resolve' => Icons.movie_edit,
  'share' => Icons.smartphone_rounded,
  'audio' => Icons.music_note_rounded,
  'privacy' => Icons.shield_outlined,
  'remux' => Icons.swap_horiz_rounded,
  _ => Icons.auto_awesome_rounded,
};

String scenarioTitle(AppLocalizations l10n, String scenarioId) =>
    switch (scenarioId) {
      'archive' => l10n.scenarioArchiveTitle,
      'resolve' => l10n.scenarioResolveTitle,
      'share' => l10n.scenarioShareTitle,
      'audio' => l10n.scenarioAudioTitle,
      'privacy' => l10n.scenarioPrivacyTitle,
      'remux' => l10n.scenarioRemuxTitle,
      _ => scenarioId,
    };

String scenarioHint(AppLocalizations l10n, String scenarioId) =>
    switch (scenarioId) {
      'archive' => l10n.scenarioArchiveHint,
      'resolve' => l10n.scenarioResolveHint,
      'share' => l10n.scenarioShareHint,
      'audio' => l10n.scenarioAudioHint,
      'privacy' => l10n.scenarioPrivacyHint,
      'remux' => l10n.scenarioRemuxHint,
      _ => '',
    };

String presetTitle(AppLocalizations l10n, String presetId) =>
    switch (presetId) {
      'resolve.studio' => l10n.presetResolveStudio,
      'resolve.free' => l10n.presetResolveFree,
      _ => presetId,
    };

String presetHint(AppLocalizations l10n, String presetId) => switch (presetId) {
  'resolve.studio' => l10n.presetResolveStudioHint,
  'resolve.free' => l10n.presetResolveFreeHint,
  _ => '',
};

String optionTitle(AppLocalizations l10n, String presetId, String optionId) =>
    switch (optionId) {
      'convertVideo' => l10n.convertVideoTitle,
      'codec' when presetId.startsWith('archive') => l10n.archiveFormatTitle,
      'codec' => l10n.optionCodecTitle,
      'speed' => l10n.archiveSpeedTitle,
      'size' => l10n.optionSizeTitle,
      'format' => l10n.optionFormatTitle,
      'mode' => l10n.optionModeTitle,
      // Resolve's quality levels are told apart by the size they make.
      'quality' => l10n.sizeTitle,
      _ => optionId,
    };

String optionHint(AppLocalizations l10n, String optionId) => switch (optionId) {
  'convertVideo' => l10n.convertVideoHint,
  'mode' => l10n.modeThoroughHint,
  _ => '',
};

String choiceLabel(AppLocalizations l10n, String presetId, String choice) =>
    switch (choice) {
      'av1' => l10n.archiveAv1,
      'hevc' => l10n.archiveHevc,
      'cpu' => l10n.archiveCpu,
      'gpu' => l10n.archiveGpu,
      'smallest' => l10n.sizeSmallest,
      'smaller' => l10n.sizeSmaller,
      'balanced' => l10n.sizeBalanced,
      'best' => l10n.sizeBest,
      'small' => l10n.shareSmall,
      'standard' => l10n.shareStandard,
      'original' => l10n.formatOriginal,
      'quick' => l10n.modeQuick,
      'thorough' => l10n.modeThorough,
      // File type names are written the same everywhere.
      'mp3' ||
      'm4a' ||
      'wav' ||
      'flac' ||
      'mp4' ||
      'mkv' ||
      'mov' => choice.toUpperCase(),
      // Format names are the same in every language.
      'prores' => 'ProRes',
      'dnxhr' => 'DNxHR',
      _ => choice,
    };

/// What a choice trades away, shown under its row for the chosen one and on
/// hover for each: the size of the file, the time it takes, where it plays.
String choiceHint(AppLocalizations l10n, String optionId, String choice) =>
    switch ((optionId, choice)) {
      ('codec', 'av1') => l10n.archiveAv1Hint,
      ('codec', 'hevc') => l10n.archiveHevcHint,
      ('speed', 'cpu') => l10n.archiveCpuHint,
      ('speed', 'gpu') => l10n.archiveGpuHint,
      _ => '',
    };

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

/// The options changed for a job, in the words the panel uses: "File size:
/// Best quality", "Also convert the picture". A job made with the goal as it
/// comes reads as just the goal. Options that had no effect are left out, as
/// the panel hides them; expert options are left to the technical line,
/// where their names belong.
List<String> chosenOptions(
  AppLocalizations l10n,
  Preset preset,
  OptionValues values,
  Capabilities capabilities,
) {
  final chosen = <String>[];
  for (final option in preset.options) {
    if (!optionVisible(preset, option, values, capabilities)) continue;
    final choice = preset.choice(values, option.id);
    if (choice == option.defaultChoice) continue;
    final title = optionTitle(l10n, preset.id, option.id);
    if (isSwitch(option)) {
      if (choice == 'yes') chosen.add(title);
    } else {
      chosen.add('$title: ${choiceLabel(l10n, preset.id, choice)}');
    }
  }
  return chosen;
}
