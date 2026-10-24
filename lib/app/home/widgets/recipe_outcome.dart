import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/output/output_namer.dart';
import '../../../core/quality/quality_meter.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../estimates/batch_estimate.dart';
import '../../format.dart';
import '../../queue/queue_controller.dart';
import '../../recipe/recipe_controller.dart';
import '../../sources/preview_controller.dart';
import '../../sources/sources_controller.dart';
import '../../theme.dart';
import '../size_change_text.dart';
import '../technical_text.dart';
import 'busy_mark.dart';
import 'command_dialog.dart';
import 'more_options_dialog.dart';

/// A text button that takes as little height as a line of text.
class LinkButton extends StatelessWidget {
  const LinkButton({super.key, required this.label, required this.onPressed});

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

/// Where results are saved, on one line.
class SaveLocation extends ConsumerWidget {
  const SaveLocation({super.key, required this.output});

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
        LinkButton(
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
class AddControls extends ConsumerWidget {
  const AddControls({super.key});

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
    final choosing = selected.any((v) => previews[v.id]?.choosing ?? false);
    final comparing = selected.any((v) {
      final plan = previews[v.id]?.plan;
      return plan != null && canComparePlan(plan);
    });
    final working = measuringWords(
      l10n,
      choosing: choosing,
      comparing: comparing,
    );

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
        if (measuring) working,
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Seen to be under way while sizes are still measured.
                  if (measuring && addableSelected > 0) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: BusyMark(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
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
                ],
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

/// The bottom of the panel: what exactly will be made, the links to more,
/// where it goes, how big it will be, and the buttons.
class RecipeOutcome extends ConsumerWidget {
  const RecipeOutcome({
    super.key,
    required this.plan,
    required this.hasMoreOptions,
    required this.firstSelected,
    required this.output,
  });

  /// What the technical line describes.
  final ConversionPlan plan;

  /// Whether the goal has options under "More options".
  final bool hasMoreOptions;

  /// The video "Show the command" shows the command for; none without a
  /// selection.
  final SourceVideo? firstSelected;
  final OutputSettings output;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final look = AppLook.of(context);
    final video = firstSelected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: look.hues?.violet.deep ?? muted,
            ),
            const SizedBox(width: 6),
            Expanded(child: TechnicalText(technicalSummary(l10n, plan))),
          ],
        ),
        // Each link may take up to half the row and shortens beyond
        // that; a lone link sits at the right.
        Row(
          mainAxisAlignment: hasMoreOptions
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.end,
          children: [
            if (hasMoreOptions)
              Flexible(
                child: LinkButton(
                  label: l10n.moreOptions,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const MoreOptionsDialog(),
                  ),
                ),
              ),
            if (video != null)
              Flexible(
                child: LinkButton(
                  label: l10n.showCommand,
                  onPressed: () => showCommandForVideo(context, ref, video),
                ),
              ),
          ],
        ),
        SaveLocation(output: output),
        const SizedBox(height: 4),
        const AddControls(),
      ],
    );
  }
}
