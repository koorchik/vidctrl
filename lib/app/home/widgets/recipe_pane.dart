import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/ffmpeg/capabilities.dart';
import '../../../core/output/output_namer.dart';
import '../../../core/scenarios/registry.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../providers.dart';
import '../../queue/queue_controller.dart';
import '../../recipe/recipe.dart';
import '../../recipe/recipe_controller.dart';
import '../../sources/preview_controller.dart';
import '../../sources/sources_controller.dart';
import '../../theme.dart';
import '../headings.dart';
import '../scenario_texts.dart';
import '../size_change_text.dart';
import '../technical_text.dart';
import 'about_button.dart';
import 'command_dialog.dart';
import 'language_button.dart';
import 'look_button.dart';

/// The right-hand panel: what to do with the selected videos, and the
/// buttons that queue them.
///
/// Everything fits without scrolling at the smallest window size, in every
/// goal and language (a test holds it to that). Each control therefore takes
/// one row: labels sit beside their controls, and choices that need more
/// room open in a small window instead of expanding in place.
class RecipePane extends ConsumerWidget {
  const RecipePane({super.key});

  /// Width of the label column of the option rows.
  static const labelWidth = 84.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final look = AppLook.of(context);
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
    final scenario = scenarios.firstWhere((s) => s.presets.contains(selected));
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
    final advanced = [
      for (final option in selected.options)
        if (advancedOptionVisible(selected, option, recipe.values)) option,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: LayoutBuilder(
          builder: (context, constraints) => _Spacing(
            // More air between rows when the window has the height for it.
            roomy: constraints.maxHeight >= _Spacing.roomyFrom,
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
                            // The gap is inside, so that it gives way too
                            // when the title and buttons take the row.
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                  selectedVideos.isEmpty
                                      ? ''
                                      : l10n.selectedCount(
                                          selectedVideos.length,
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: muted,
                                  ),
                                ),
                              ),
                            ),
                            const AboutButton(),
                            const LookButton(),
                            const LanguageButton(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _ScenarioGrid(
                          selected: scenario,
                          onSelect: (s) =>
                              controller.selectPreset(s.presets.first.id),
                        ),
                        if (presets.length > 1) ...[
                          if (constraints.maxHeight >= _Spacing.roomyFrom)
                            _Hint(scenarioHint(l10n, scenario.id)),
                          const _Gap(),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              for (final preset in presets)
                                ButtonSegment(
                                  value: preset.id,
                                  label: _SegmentLabel(
                                    presetTitle(l10n, preset.id),
                                    caption: presetCaption(
                                      l10n,
                                      preset,
                                      recipe.values,
                                      capabilities,
                                    ),
                                  ),
                                ),
                            ],
                            selected: {selected.id},
                            onSelectionChanged: (ids) =>
                                controller.selectPreset(ids.first),
                          ),
                        ],
                        // One explanation: of the variant where there are
                        // several, otherwise of the goal. Where the options
                        // explain themselves, the goal's explanation needs
                        // the roomier window; it is also the goal's tooltip.
                        if (presets.length > 1)
                          _Hint(presetHint(l10n, selected.id))
                        else if (explainedOptions.isEmpty ||
                            constraints.maxHeight >= _Spacing.roomyFrom)
                          _Hint(scenarioHint(l10n, scenario.id)),
                        for (final option in selected.options)
                          if (optionVisible(
                            selected,
                            option,
                            recipe.values,
                            capabilities,
                          )) ...[
                            _OptionRow(
                              preset: selected,
                              option: option,
                              values: recipe.values,
                              capabilities: capabilities,
                              onChanged: (value) =>
                                  controller.setOption(option.id, value),
                            ),
                            // What the chosen variant trades away.
                            _Hint(
                              choiceHint(
                                l10n,
                                option.id,
                                selected.choice(recipe.values, option.id),
                              ),
                            ),
                          ],
                        _LabeledRow(
                          label: l10n.convertTitle,
                          child: SegmentedButton<SampleChoice>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: SampleChoice.none,
                                label: _SegmentLabel(l10n.convertWhole),
                              ),
                              ButtonSegment(
                                value: SampleChoice.start,
                                label: _SegmentLabel(
                                  l10n.convertSampleShort,
                                  caption: l10n.sampleFirst,
                                  technicalCaption: false,
                                ),
                              ),
                              ButtonSegment(
                                value: SampleChoice.middle,
                                label: _SegmentLabel(
                                  l10n.convertSampleShort,
                                  caption: l10n.sampleMiddle,
                                  technicalCaption: false,
                                ),
                              ),
                            ],
                            selected: {recipe.sample},
                            onSelectionChanged: (value) =>
                                controller.setSample(value.first),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // The outcome: what exactly will be made, where it goes, how
                // big it will be, and the buttons. Always at the bottom.
                const _Gap(),
                Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 14,
                      color: look.hues?.violet.deep ?? muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TechnicalText(technicalSummary(l10n, shownPlan)),
                    ),
                  ],
                ),
                // Each link may take up to half the row and shortens beyond
                // that; a lone link sits at the right.
                Row(
                  mainAxisAlignment: advanced.isEmpty
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.spaceBetween,
                  children: [
                    if (advanced.isNotEmpty)
                      Flexible(
                        child: _LinkButton(
                          label: l10n.moreOptions,
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const _MoreOptionsDialog(),
                          ),
                        ),
                      ),
                    if (selectedVideos.isNotEmpty)
                      Flexible(
                        child: _LinkButton(
                          label: l10n.showCommand,
                          onPressed: () {
                            final args = ref
                                .read(queueProvider.notifier)
                                .commandForVideo(selectedVideos.first);
                            if (args == null) return;
                            showDialog<void>(
                              context: context,
                              builder: (_) => CommandDialog(args: args),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                _SaveLocation(output: settings.output),
                const SizedBox(height: 4),
                const _AddControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How much air the panel's rows get. Compact at the smallest window size,
/// where everything must still fit; roomier when there is height to spare.
class _Spacing extends InheritedWidget {
  const _Spacing({required this.roomy, required super.child});

  /// Panel height from which the roomier spacing is used.
  static const roomyFrom = 700.0;

  final bool roomy;

  /// False outside the panel, e.g. in the extra-options window.
  static bool isRoomy(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Spacing>()?.roomy ?? false;

  /// Space between rows.
  static double gap(BuildContext context) => isRoomy(context) ? 16 : 10;

  /// Height of a goal tile.
  static double tileHeight(BuildContext context) => isRoomy(context) ? 58 : 50;

  /// Space above and below the text of a segmented button.
  static double segmentPadding(BuildContext context) =>
      isRoomy(context) ? 6 : 2;

  @override
  bool updateShouldNotify(_Spacing oldWidget) => roomy != oldWidget.roomy;
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => SizedBox(height: _Spacing.gap(context));
}

/// The goals as a compact grid of three columns. The chosen goal is
/// explained under the grid; the others explain themselves on hover.
class _ScenarioGrid extends StatelessWidget {
  const _ScenarioGrid({required this.selected, required this.onSelect});

  final Scenario selected;
  final ValueChanged<Scenario> onSelect;

  static const _gap = 6.0;
  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth =
            (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final scenario in scenarios)
              SizedBox(
                width: tileWidth,
                child: _ScenarioTile(
                  scenario: scenario,
                  selected: scenario == selected,
                  onTap: () => onSelect(scenario),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({
    required this.scenario,
    required this.selected,
    required this.onTap,
  });

  final Scenario scenario;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    // Where the look has colours, each goal has its own: a pale tile with
    // the icon in the full colour, and the chosen one deeper and outlined.
    final hue = look.hues?.at(scenarios.indexOf(scenario));
    final Color fill, edge, iconColor;
    if (hue != null) {
      fill = selected ? hue.soft : Color.lerp(scheme.surface, hue.soft, 0.45)!;
      edge = selected ? hue.deep : Color.lerp(hue.soft, hue.deep, 0.2)!;
      iconColor = hue.deep;
    } else {
      fill = selected ? scheme.primaryContainer : scheme.surface;
      edge = selected ? scheme.primary : scheme.outlineVariant;
      iconColor = selected
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant;
    }
    return Tooltip(
      message: scenarioHint(l10n, scenario.id),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(look.controlRadius),
          side: BorderSide(
            color: edge,
            width: selected ? look.selectedBorderWidth : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: _Spacing.tileHeight(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(scenarioIcon(scenario.id), size: 20, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      scenarioTitle(l10n, scenario.id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 12.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: selected && hue == null
                            ? scheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A control with its label to the left, on one row.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: _Spacing.gap(context)),
      child: Row(
        children: [
          SizedBox(width: RecipePane.labelWidth, child: ControlLabel(label)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// One option of a preset: a row of choices, or a switch for yes/no.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.preset,
    required this.option,
    required this.values,
    required this.capabilities,
    required this.onChanged,
  });

  final Preset preset;
  final PresetOption option;
  final OptionValues values;
  final Capabilities capabilities;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final title = optionTitle(l10n, preset.id, option.id);
    final value = preset.choice(values, option.id);

    if (isSwitch(option)) {
      return Padding(
        padding: EdgeInsets.only(top: _Spacing.gap(context) - 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(
                    optionHint(l10n, option.id),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value == 'yes',
              onChanged: (on) => onChanged(on ? 'yes' : 'no'),
            ),
          ],
        ),
      );
    }
    final choices = SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final choice in option.choices)
          ButtonSegment(
            value: choice,
            tooltip: switch (choiceHint(l10n, option.id, choice)) {
              '' => null,
              final hint => hint,
            },
            label: _SegmentLabel(
              choiceLabel(l10n, preset.id, choice),
              caption: choiceCaption(
                l10n,
                preset,
                option.id,
                choice,
                values,
                capabilities,
              ),
            ),
          ),
      ],
      selected: {value},
      onSelectionChanged: (chosen) => onChanged(chosen.first),
    );
    // Beside the label there is room for three choices; more get the full
    // width, so their labels stay the same size.
    if (option.choices.length <= 3) {
      return _LabeledRow(label: title, child: choices);
    }
    return Padding(
      padding: EdgeInsets.only(top: _Spacing.gap(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ControlLabel(title),
          ),
          choices,
        ],
      ),
    );
  }
}

/// A segmented-button label, optionally with a small caption under it. It
/// shrinks slightly rather than wrapping when a translation is long.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text, {this.caption, this.technicalCaption = true});

  final String text;
  final String? caption;

  /// Whether the caption is a technical name rather than plain words.
  final bool technicalCaption;

  @override
  Widget build(BuildContext context) {
    // The caption is a quieter shade of the label's own colour, which is
    // not the same on the chosen segment as on the others.
    final quiet = DefaultTextStyle.of(context).style.color
        ?.withValues(alpha: 0.7);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: _Spacing.segmentPadding(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, maxLines: 1, softWrap: false),
            if (caption case final caption?)
              technicalCaption
                  ? TechnicalText(caption, color: quiet, caption: true)
                  : _Caption(caption, color: quiet),
          ],
        ),
      ),
    );
  }
}

/// A plain-language caption under a segment label.
class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      maxLines: 1,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
        // As large as a technical caption, so the rows match.
        fontSize: captionFontSize,
        height: captionLineHeight / captionFontSize,
      ),
    );
  }
}

/// A text button that takes as little height as a line of text.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onPressed,
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

/// Options most people never need, in a small window of their own so the
/// panel does not grow.
class _MoreOptionsDialog extends ConsumerWidget {
  const _MoreOptionsDialog();

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
                _OptionRow(
                  preset: preset,
                  option: option,
                  values: recipe.values,
                  capabilities: capabilities,
                  onChanged: (value) => ref
                      .read(recipeProvider.notifier)
                      .setOption(option.id, value),
                ),
                // What the chosen variant trades away, as on the panel.
                _Hint(
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

/// Where results are saved, on one line.
class _SaveLocation extends ConsumerWidget {
  const _SaveLocation({required this.output});

  final OutputSettings output;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = ref.read(recipeProvider.notifier);
    final custom = output.mode == OutputMode.customFolder
        ? output.customDir
        : null;

    return Row(
      children: [
        Icon(
          Icons.folder_outlined,
          size: 18,
          color:
              AppLook.of(context).hues?.amber.deep ??
              theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: custom ?? l10n.saveNextToOriginals,
            child: Text(
              custom == null ? l10n.saveNextToOriginals : p.basename(custom),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            ),
          ),
        ),
        if (custom != null)
          IconButton(
            tooltip: l10n.saveReset,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.undo_rounded, size: 18),
            onPressed: () => controller.setOutput(const OutputSettings()),
          ),
        _LinkButton(
          label: l10n.saveChooseFolder,
          onPressed: () async {
            final folder = await getDirectoryPath();
            if (folder == null) return;
            controller.setOutput(
              OutputSettings(mode: OutputMode.customFolder, customDir: folder),
            );
          },
        ),
      ],
    );
  }
}

/// What Add to queue would do, and the buttons.
class _AddControls extends ConsumerWidget {
  const _AddControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = Formatter(l10n);
    final sources = ref.watch(sourcesProvider);
    final recipe = ref.watch(recipeProvider.select((s) => s.recipe));
    final previews = ref.watch(previewProvider);
    // Rebuilt when jobs change, so "already in the queue" stays true.
    ref.watch(queueProvider.select((q) => q.jobs));
    final queue = ref.read(queueProvider.notifier);

    final selected = sources.selectedReady;
    final all = sources.ready;
    final addableSelected = queue.addable(selected);
    final addableAll = queue.addable(all);
    final batch = batchEstimate(selected, previews);
    final measuring = selected.any((v) => previews[v.id]?.measuring ?? false);

    final String summary;
    String? larger;
    if (selected.isEmpty) {
      summary = l10n.selectVideosHint;
    } else if (addableSelected == 0) {
      summary = l10n.alreadyQueued;
    } else if (recipe.isSample) {
      summary = l10n.samplesCount(addableSelected);
    } else if (batch != null) {
      larger = format.largerBy(batch.before, batch.after);
      summary = [
        '${l10n.videoCount(selected.length)}  ·  ${format.bytes(batch.before)}'
            ' → ${l10n.aboutSize(format.bytes(batch.after))}',
        format.sizeChange(batch.before, batch.after),
        if (batch.time != null) l10n.takesAbout(format.wait(batch.time!)),
      ].join('  ·  ');
    } else {
      summary = [
        l10n.videoCount(selected.length),
        if (measuring) l10n.estimating,
      ].join('  ·  ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          // Two lines are always reserved, so the buttons do not move when
          // the summary changes length.
          child: SizedBox(
            height: 36,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: SizeChangeText(
                summary,
                larger: larger,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: addableSelected > 0 ? queue.addSelected : null,
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text(l10n.addToQueue),
              ),
            ),
            // Only when it would do something the main button does not.
            if (all.length > selected.length) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: addableAll > 0 ? queue.addAll : null,
                child: Text(l10n.addAllToQueue(all.length)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Expected total size and time for [videos], or null while nothing has been
/// worked out yet.
///
/// Videos not measured yet are assumed to shrink like the measured ones, in
/// proportion to their size, and to take time in proportion to their length.
({int before, int after, Duration? time})? batchEstimate(
  List<SourceVideo> videos,
  Map<int, Preview> previews,
) {
  final known = [
    for (final video in videos)
      if (previews[video.id]?.estimate case final estimate?) (video, estimate),
  ];
  if (known.isEmpty) return null;
  int size(SourceVideo v) => v.info?.sizeBytes ?? 0;
  int length(SourceVideo v) => v.info?.duration.inMilliseconds ?? 0;

  final before = videos.fold(0, (sum, v) => sum + size(v));
  final knownBefore = known.fold(0, (sum, k) => sum + size(k.$1));
  final knownAfter = known.fold(0, (sum, k) => sum + k.$2.bytes);
  // The ratio is taken first: byte counts multiplied together overflow.
  final after = knownBefore > 0
      ? (knownAfter * (before / knownBefore)).round()
      : knownAfter;

  // Only re-encodes take noticeable time; quick fixes take seconds.
  final timed = known.where((k) => k.$2.time != null).toList();
  final encodes = videos.where(
    (v) => previews[v.id]?.plan.kind == PlanKind.encode,
  );
  final timedLength = timed.fold(0, (sum, k) => sum + length(k.$1));
  final encodeLength = encodes.fold(0, (sum, v) => sum + length(v));
  final timedSpent = timed.fold(Duration.zero, (sum, k) => sum + k.$2.time!);
  final time = timedLength > 0
      ? timedSpent * (encodeLength / timedLength)
      : null;
  return (before: before, after: after, time: time);
}
