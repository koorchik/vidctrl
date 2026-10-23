import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/protocol.dart';
import '../../core/ffmpeg/capabilities.dart';
import '../../core/output/output_namer.dart';
import '../../core/scenarios/archive.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../home/scenario_texts.dart';
import '../recipe/recipe.dart';
import '../recipe/recipe_controller.dart';
import '../sources/sources_controller.dart';

// Reading what a client asked for: every value is checked, and a wrong one
// is refused with the valid ones named.

ControlError badArgument(String message) =>
    ControlError(ControlErrorKind.badArgument, message);

List<Object?> listParam(Map<String, Object?> params, String key) {
  final items = params[key];
  if (items is! List || items.isEmpty) {
    throw badArgument('"$key" must be a list with at least one item.');
  }
  return items;
}

String absolutePath(Object? path, String key) {
  if (path is! String || !p.isAbsolute(path)) {
    throw badArgument('"$key" takes absolute paths; "$path" is not one.');
  }
  return p.normalize(path);
}

/// A video's id, or its path made plain.
Object videoReference(Object? reference) =>
    reference is int ? reference : absolutePath(reference, 'videos');

SourceVideo? findVideo(SourcesState state, Object reference) {
  if (reference is int) return state.byId(reference);
  for (final video in state.videos) {
    if (p.normalize(video.path) == reference) return video;
  }
  return null;
}

/// The goal and options asked for in [params], or the panel's goal and
/// options where no goal is named; options given then change the panel's.
/// Only the options the panel offers on this computer can be given, or one
/// it does not with the choice the goal makes here anyway. The panel itself
/// is left as it is.
Recipe recipeFrom(
  Ref ref,
  Map<String, Object?> params,
  Capabilities capabilities, {
  bool withSample = false,
}) {
  final goal = params['goal'];
  final panel = ref.read(recipeProvider).recipe;
  final preset = goal == null ? findPreset(panel.presetId)! : _preset(goal);
  return Recipe(
    presetId: preset.id,
    values: {
      if (goal == null) ...panel.values,
      ..._options(preset, params['options'], capabilities),
    },
    sample: withSample ? _sample(params['sample']) : SampleChoice.none,
  );
}

Preset _preset(Object goal) {
  if (goal is String) {
    final preset = findPreset(goal);
    if (preset != null) return preset;
    for (final scenario in scenarios) {
      if (scenario.id != goal) continue;
      if (scenario.presets.length == 1) return scenario.presets.single;
      throw badArgument(
        'The goal "$goal" comes in ${scenario.presets.length} kinds; name '
        'one: ${[for (final kind in scenario.presets) kind.id].join(', ')}.',
      );
    }
  }
  final goals = [
    for (final scenario in scenarios)
      if (scenario.presets.length == 1)
        scenario.id
      else
        for (final preset in scenario.presets) preset.id,
  ];
  throw badArgument('There is no goal "$goal". Goals: ${goals.join(', ')}.');
}

OptionValues _options(
  Preset preset,
  Object? options,
  Capabilities capabilities,
) {
  if (options == null) return const {};
  if (options is! Map) {
    throw badArgument('"options" must map option ids to choice ids.');
  }
  final offered = [
    for (final option in preset.options)
      if (optionOffered(preset, option, capabilities)) option,
  ];
  final here = offered.isEmpty
      ? 'The goal ${preset.id} has no options on this computer.'
      : 'Options here: ${[for (final o in offered) o.id].join(', ')}.';
  final values = <String, String>{};
  for (final MapEntry(:key, :value) in options.entries) {
    final option = preset.options.where((o) => o.id == key).firstOrNull;
    if (option == null) {
      throw badArgument(
        preset.options.isEmpty
            ? 'The goal ${preset.id} has no options.'
            : 'The goal ${preset.id} has no option "$key". $here',
      );
    }
    if (value is! String || !option.choices.contains(value)) {
      throw badArgument(
        'The option ${option.id} of ${preset.id} has no choice "$value". '
        'Choices: ${option.choices.join(', ')}.',
      );
    }
    // As on the panel, which does not show the row here; naming what
    // happens anyway changes nothing, so a script may name it everywhere.
    final anyway = _madeAnyway(preset, option, capabilities);
    if (!offered.contains(option) && value != anyway) {
      throw badArgument(
        'The option ${option.id} of ${preset.id} cannot be chosen on this '
        'computer: it is always $anyway here. $here',
      );
    }
    values[option.id] = value;
  }
  return values;
}

/// The choice [preset] makes for [option] on a computer where the panel
/// never shows it: the format this FFmpeg can make for the archive's (HEVC
/// without AV1), the default otherwise (the processor without a graphics
/// card encoder).
String _madeAnyway(
  Preset preset,
  PresetOption option,
  Capabilities capabilities,
) => preset is ArchivePreset && option.id == ArchivePreset.codec
    ? ArchivePreset.formatFor(const {}, capabilities)
    : option.defaultChoice;

/// Whether the panel shows [option], with the goal's defaults or with one
/// other option changed: the archive's speed row appears only once HEVC is
/// chosen on a computer whose graphics card makes HEVC alone. An option this
/// computer cannot use at all is never shown.
bool optionOffered(
  Preset preset,
  PresetOption option,
  Capabilities capabilities,
) {
  bool shownWith(OptionValues values) =>
      optionVisible(preset, option, values, capabilities) ||
      advancedOptionVisible(preset, option, values);
  if (shownWith(const {})) return true;
  for (final other in preset.options) {
    for (final choice in other.choices) {
      if (shownWith({other.id: choice})) return true;
    }
  }
  return false;
}

SampleChoice _sample(Object? sample) => switch (sample) {
  null => SampleChoice.none,
  'start' => SampleChoice.start,
  'middle' => SampleChoice.middle,
  _ => throw badArgument('"sample" is start or middle, not "$sample".'),
};

/// Where results go: the panel's setting when nothing is asked; `next` for
/// a folder beside each video (`subfolder` names it, and alone implies
/// `next`); or a folder for all of them.
OutputSettings outputFrom(Ref ref, Map<String, Object?> params) {
  final out = params['out'];
  final subfolder = params['subfolder'];
  if (subfolder != null &&
      (subfolder is! String ||
          subfolder.isEmpty ||
          subfolder == '.' ||
          subfolder == '..' ||
          p.basename(subfolder) != subfolder)) {
    throw badArgument(
      '"subfolder" is the name of one folder, not "$subfolder".',
    );
  }
  if (out == null && subfolder == null) return ref.read(recipeProvider).output;
  if (out == null || out == 'next') {
    return subfolder is String
        ? OutputSettings(subfolderName: subfolder)
        : const OutputSettings();
  }
  if (subfolder != null) {
    throw badArgument('"subfolder" goes with out "next", not with a folder.');
  }
  return OutputSettings(
    mode: OutputMode.customFolder,
    customDir: absolutePath(out, 'out'),
  );
}
