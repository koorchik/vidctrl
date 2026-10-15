import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/output/output_namer.dart';
import '../../core/scenarios/archive.dart';
import '../../core/scenarios/registry.dart';
import '../settings.dart';
import 'recipe.dart';

class RecipeState {
  const RecipeState({
    required this.recipe,
    this.output = const OutputSettings(),
  });

  final Recipe recipe;
  final OutputSettings output;

  RecipeState copyWith({Recipe? recipe, OutputSettings? output}) =>
      RecipeState(recipe: recipe ?? this.recipe, output: output ?? this.output);
}

final recipeProvider = NotifierProvider<RecipeController, RecipeState>(
  RecipeController.new,
);

/// The "What to do" panel: the goal, its options, whole video or sample, and
/// where results go. The goal and folder are remembered between runs; the
/// sample choice is not, so nobody starts a session making samples by
/// accident.
class RecipeController extends Notifier<RecipeState> {
  static const _goalKey = 'goal';
  static const _outputKey = 'output';

  @override
  RecipeState build() {
    final store = ref.read(settingsStoreProvider);
    return RecipeState(
      recipe:
          _restoreGoal(store.read(_goalKey)) ??
          Recipe(presetId: archiveScenario.presets.first.id),
      output: _restoreOutput(store.read(_outputKey)),
    );
  }

  /// Choosing the goal that is already chosen keeps its options, which may
  /// have been set under "More options".
  void selectPreset(String presetId) {
    if (findPreset(presetId) == null || presetId == state.recipe.presetId) {
      return;
    }
    _setGoal(state.recipe.copyWith(presetId: presetId, values: const {}));
  }

  void setOption(String optionId, String value) {
    _setGoal(
      state.recipe.copyWith(values: {...state.recipe.values, optionId: value}),
    );
  }

  void setSample(SampleChoice sample) {
    state = state.copyWith(recipe: state.recipe.copyWith(sample: sample));
  }

  void setOutput(OutputSettings output) {
    state = state.copyWith(output: output);
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(
            _outputKey,
            output.mode == OutputMode.customFolder
                ? {'folder': output.customDir}
                : null,
          ),
    );
  }

  /// Puts a queued job's settings back into the panel, to adjust them and
  /// queue again.
  void load(Recipe recipe) => _setGoal(recipe);

  void _setGoal(Recipe recipe) {
    state = state.copyWith(recipe: recipe);
    unawaited(
      ref.read(settingsStoreProvider).write(_goalKey, {
        'preset': recipe.presetId,
        'values': recipe.values,
      }),
    );
  }

  /// The goal used last time, if it still exists. Choices this computer
  /// cannot make, such as the graphics card, fall back in the plan itself.
  Recipe? _restoreGoal(Object? saved) {
    if (saved is! Map) return null;
    final preset = findPreset('${saved['preset']}');
    if (preset == null) return null;
    final values = saved['values'];
    return Recipe(
      presetId: preset.id,
      values: values is Map
          ? {for (final e in values.entries) '${e.key}': '${e.value}'}
          : const {},
    );
  }

  OutputSettings _restoreOutput(Object? saved) {
    if (saved is Map && saved['folder'] is String) {
      return OutputSettings(
        mode: OutputMode.customFolder,
        customDir: saved['folder'] as String,
      );
    }
    return const OutputSettings();
  }
}
