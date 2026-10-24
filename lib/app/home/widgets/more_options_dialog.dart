import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scenarios/option_visibility.dart';
import '../../../core/scenarios/registry.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../recipe/recipe_controller.dart';
import '../scenario_texts.dart';
import 'option_row.dart';

/// Options most people never need, in a small window of their own so the
/// panel does not grow.
class MoreOptionsDialog extends ConsumerWidget {
  const MoreOptionsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final recipe = ref.watch(recipeProvider.select((s) => s.recipe));
    final capabilities = ref
        .watch(environmentProvider)
        .requireValue
        .capabilities;
    final preset = findPreset(recipe.presetId)!;
    return AlertDialog(
      title: Text(l10n.moreOptions.replaceAll('…', '')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in preset.options)
              if (advancedOptionVisible(preset, option, recipe.values)) ...[
                OptionRow(
                  preset: preset,
                  option: option,
                  values: recipe.values,
                  capabilities: capabilities,
                  onChanged: (value) => ref
                      .read(recipeProvider.notifier)
                      .setOption(option.id, value),
                ),
                // What the chosen variant trades away, as on the panel.
                PanelHint(
                  choiceHint(
                    l10n,
                    option.id,
                    preset.choice(recipe.values, option.id),
                  ),
                ),
              ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
