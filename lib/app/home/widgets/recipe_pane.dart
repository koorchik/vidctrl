import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scenarios/archive.dart';
import '../../../core/scenarios/option_visibility.dart';
import '../../../core/scenarios/registry.dart';
import '../../../core/scenarios/resolve_linux.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../recipe/recipe_controller.dart';
import '../../sources/preview_controller.dart';
import '../../sources/sources_controller.dart';
import '../headings.dart';
import '../scenario_texts.dart';
import '../technical_text.dart';
import 'archive_quality_dialog.dart';
import 'goal_picker.dart';
import 'option_row.dart';
import 'panel_spacing.dart';
import 'recipe_outcome.dart';
import 'web_links.dart';

/// The right-hand panel: what to do with the selected videos, and the
/// buttons that queue them.
///
/// Everything fits without scrolling at the smallest window size, in every
/// goal and language (a test holds it to that). Each control therefore takes
/// one row: labels sit beside their controls, and choices that need more
/// room open in a small window instead of expanding in place.
class RecipePane extends ConsumerWidget {
  const RecipePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final settings = ref.watch(recipeProvider);
    final recipe = settings.recipe;
    final controller = ref.read(recipeProvider.notifier);
    final selectedVideos = ref.watch(
      sourcesProvider.select((s) => s.selectedReady),
    );
    final capabilities = ref
        .watch(environmentProvider)
        .requireValue
        .capabilities;

    final selected = findPreset(recipe.presetId)!;
    final scenario = scenarioOf(selected);
    final presets = scenario.presets;
    // The technical line describes what will really happen to the first
    // selected video (its sound may need converting where a typical file's
    // does not); with nothing selected, or a video that needs no work, it
    // describes a typical camera file.
    final selectedPlan = selectedVideos.isEmpty
        ? null
        : ref.watch(
            previewProvider.select((p) => p[selectedVideos.first.id]?.plan),
          );
    final shownPlan = selectedPlan != null && selectedPlan.producesOutput
        ? selectedPlan
        : typicalPlan(selected, recipe.values, capabilities);
    // Options whose chosen variant has its own explanation under its row.
    final explainedOptions = selected.options.where(
      (option) =>
          optionVisible(selected, option, recipe.values, capabilities) &&
          choiceHint(
            l10n,
            option.id,
            selected.choice(recipe.values, option.id),
          ).isNotEmpty,
    );
    // Where two options explain themselves, the goal's explanation needs a
    // taller panel than the smallest one.
    bool goalExplained(BoxConstraints constraints) =>
        explainedOptions.length < 2 ||
        constraints.maxHeight >= PanelSpacing.explainedFrom;
    // The archive's settings were measured, not guessed; "?" tells how.
    final help = scenario == archiveScenario
        ? (
            l10n.archiveQualityHelp,
            () => showDialog<void>(
              context: context,
              builder: (_) => const ArchiveQualityDialog(),
            ),
          )
        : null;
    final advanced = [
      for (final option in selected.options)
        if (advancedOptionVisible(selected, option, recipe.values)) option,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: LayoutBuilder(
          builder: (context, constraints) => PanelSpacing(
            // More air between rows when the window has the height for it.
            roomy: constraints.maxHeight >= PanelSpacing.roomyFrom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The choices. Scrolls only as a last resort (very large
                // text settings); at normal sizes everything fits.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            PaneTitle(l10n.recipeTitleNone),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedVideos.isEmpty
                                    ? ''
                                    : l10n.selectedCount(selectedVideos.length),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        GoalPicker(
                          selected: scenario,
                          onSelect: (s) =>
                              controller.selectPreset(s.presets.first.id),
                        ),
                        if (presets.length > 1) ...[
                          if (constraints.maxHeight >= PanelSpacing.roomyFrom)
                            PanelHint(scenarioHint(l10n, scenario.id)),
                          const PanelGap(),
                          PresetPicker(
                            presets: presets,
                            selected: selected,
                            values: recipe.values,
                            capabilities: capabilities,
                            onSelect: controller.selectPreset,
                          ),
                        ],
                        // One explanation: of the variant where there are
                        // several, otherwise of the goal. Where two options
                        // explain themselves, the goal's explanation waits
                        // until it fits; it is also the goal's tooltip.
                        // Where the computer offers only one of them (no
                        // graphics card), it takes the other's room.
                        if (presets.length > 1)
                          PanelHint(presetHint(l10n, selected.id))
                        else if (goalExplained(constraints))
                          PanelHint(
                            scenarioHint(l10n, scenario.id),
                            help: help,
                          ),
                        PanelHint(
                          scenarioNotice(l10n, scenario.id),
                          notice: true,
                        ),
                        // People who edit in Resolve often shoot on
                        // Blackmagic cameras, which CamCtrl controls. Only
                        // where there is room: the smallest window has none.
                        if (scenario == resolveLinuxScenario &&
                            constraints.maxHeight >= PanelSpacing.roomyFrom)
                          const _CamctrlHint(),
                        for (final option in selected.options)
                          if (optionVisible(
                            selected,
                            option,
                            recipe.values,
                            capabilities,
                          )) ...[
                            OptionRow(
                              preset: selected,
                              option: option,
                              values: recipe.values,
                              capabilities: capabilities,
                              onChanged: (value) =>
                                  controller.setOption(option.id, value),
                            ),
                            // What the chosen variant trades away. The
                            // goal's "?" follows the first of these while
                            // its explanation waits, so it is always there.
                            PanelHint(
                              choiceHint(
                                l10n,
                                option.id,
                                selected.choice(recipe.values, option.id),
                              ),
                              help:
                                  !goalExplained(constraints) &&
                                      option == explainedOptions.first
                                  ? help
                                  : null,
                            ),
                          ],
                        SampleRow(
                          sample: recipe.sample,
                          onChanged: controller.setSample,
                        ),
                      ],
                    ),
                  ),
                ),
                // The outcome: what exactly will be made, where it goes, how
                // big it will be, and the buttons. Always at the bottom.
                const PanelGap(),
                RecipeOutcome(
                  plan: shownPlan,
                  hasMoreOptions: advanced.isNotEmpty,
                  firstSelected: selectedVideos.firstOrNull,
                  output: settings.output,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Shooting on Blackmagic? Control the camera with CamCtrl", in the style of
/// the explanations, with the second half a link. It follows Resolve's
/// explanation as its next line, closer than a new explanation would be.
class _CamctrlHint extends StatelessWidget {
  const _CamctrlHint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
      child: WebLink(
        l10n.camctrlLink,
        url: camctrlUrl,
        lead: l10n.camctrlQuestion,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
      ),
    );
  }
}
