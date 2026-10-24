import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/estimate/size_estimator.dart';
import '../../../core/media/ffprobe.dart';
import '../../../core/platform/open_external.dart';
import '../../../core/quality/quality_meter.dart';
import '../../../core/scenarios/registry.dart';
import '../../../l10n/app_localizations.dart';
import '../../estimates/estimate_cache.dart';
import '../../format.dart';
import '../../providers.dart';
import '../../quality/quality_controller.dart';
import '../../queue/queue_controller.dart';
import '../../queue/queue_state.dart';
import '../../theme.dart';
import '../scenario_texts.dart';
import '../size_change_text.dart';
import '../technical_text.dart';
import 'closeness_line.dart';
import 'quality_report.dart';
import 'command_dialog.dart';
import 'media_details_dialog.dart';

/// One conversion: which video, with what settings, where it goes, and how
/// it is getting on.
class JobTile extends ConsumerWidget {
  const JobTile({super.key, required this.job, required this.index});

  final QueueJob job;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    final format = Formatter(l10n);
    final queue = ref.read(queueProvider.notifier);
    final key = estimateKey(job.path, job.recipe);
    final whole =
        estimateWithoutEncoding(job.info, job.plan) ??
        ref.watch(estimateCacheProvider.select((c) => c.estimates[key]));
    final result = job.result;
    final check = ref.watch(qualityProvider.select((checks) => checks[job.id]));
    // The quality chosen for the video, or before the job knows it, what the
    // video list measured.
    final choice =
        job.quality ?? (job.status == JobStatus.waiting ? whole?.choice : null);
    // The converted whole video, to show its frame.
    final converted = job.status == JobStatus.done && !job.isSample
        ? result?.outputPath
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(look.panelRadius),
        border: Border.all(
          color: job.isActive ? scheme.primary : scheme.outlineVariant,
          width: job.isActive ? look.selectedBorderWidth : 1,
        ),
      ),
      child: Row(
        children: [
          _StatusIcon(job: job),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        format.fileName(job.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (job.isSample) ...[
                      const SizedBox(width: 8),
                      _Chip(l10n.sampleChip),
                    ],
                    if (choice != null && QualityBadge.shows(choice)) ...[
                      const SizedBox(width: 8),
                      QualityBadge(
                        choice: choice,
                        original: job.info,
                        result: converted,
                      ),
                    ],
                  ],
                ),
                _GoalLine(job: job),
                if (job.isActive) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (job.progress?.fraction ?? 0) > 0
                        ? job.progress!.fraction
                        : null,
                  ),
                ],
                const SizedBox(height: 2),
                SizeChangeText(
                  _statusLine(l10n, format, whole),
                  larger:
                      job.status == JobStatus.done &&
                          !job.isSample &&
                          job.result?.outputBytes != null
                      ? format.largerBy(
                          job.info.sizeBytes,
                          job.result!.outputBytes!,
                        )
                      : null,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _statusColor(context),
                  ),
                ),
                if (choice != null)
                  QualityChoiceLine(
                    choice: choice,
                    original: job.info,
                    result: converted,
                  )
                else if (whole?.quality case final score?
                    when job.status == JobStatus.waiting && check == null)
                  ClosenessLine(score: score),
                if (check != null) _QualityLine(check: check),
                if (job.status == JobStatus.done && job.isSample)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: () => queue.convertWhole(job.id),
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: Text(l10n.convertWholeVideo),
                    ),
                  ),
                if (job.outputPath.isNotEmpty)
                  TechnicalText(
                    [
                      '→ ${job.isSample ? 'Samples/' : ''}'
                          '${p.basename(job.outputPath)}',
                      technicalSummary(l10n, job.plan),
                    ].join('   ·   '),
                  ),
              ],
            ),
          ),
          ..._actions(context, ref, l10n),
          _JobMenu(job: job),
          if (job.status == JobStatus.waiting)
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: l10n.dragToReorder,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: scheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final queue = ref.read(queueProvider.notifier);
    final output = job.result?.outputPath;
    final hues = AppLook.of(context).hues;
    switch (job.status) {
      case JobStatus.waiting:
        return [
          IconButton(
            tooltip: l10n.remove,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => queue.remove(job.id),
          ),
        ];
      case JobStatus.running:
      case JobStatus.paused:
        return [
          IconButton(
            tooltip: l10n.cancel,
            icon: const Icon(Icons.close_rounded),
            onPressed: queue.cancelActive,
          ),
        ];
      case JobStatus.done:
        return [
          if (output != null) ...[
            IconButton(
              tooltip: l10n.play,
              icon: Icon(Icons.play_arrow_rounded, color: hues?.green.deep),
              onPressed: () => openWithDefaultApp(output),
            ),
            IconButton(
              tooltip: l10n.showInFolder,
              icon: Icon(Icons.folder_open_rounded, color: hues?.amber.deep),
              onPressed: () => revealInFileManager(output),
            ),
          ],
        ];
      case JobStatus.failed:
      case JobStatus.cancelled:
        return [
          if (job.status == JobStatus.failed)
            TextButton(
              onPressed: () => _showError(context, l10n),
              child: Text(l10n.details),
            ),
          IconButton(
            tooltip: l10n.retry,
            icon: Icon(Icons.refresh_rounded, color: hues?.blue.deep),
            onPressed: () => queue.retry(job.id),
          ),
        ];
      case JobStatus.skipped:
        return const [];
    }
  }

  String _statusLine(
    AppLocalizations l10n,
    Formatter format,
    OutputEstimate? whole,
  ) {
    final result = job.result;
    final sampleShare = job.isSample
        ? job.sample!.length.inMicroseconds /
              job.info.duration.inMicroseconds.clamp(1, 1 << 62)
        : 1.0;
    switch (job.status) {
      case JobStatus.waiting:
        final keptAsIs =
            job.keptAsIs ||
            (job.quality == null && whole?.choice?.converts == false);
        return [
          l10n.jobWaiting,
          if (whole != null && !keptAsIs)
            l10n.aboutSize(format.bytes((whole.bytes * sampleShare).round())),
        ].join('  ·  ');
      case JobStatus.running:
        if (job.attempt case final attempt?) {
          return attempt > 1
              ? l10n.jobChoosingQuality(attempt - 1)
              : l10n.jobCheckingQuality;
        }
        final progress = job.progress;
        if (progress == null || progress.fraction <= 0) {
          return l10n.statusStarting;
        }
        return [
          '${(progress.fraction * 100).floor()}%',
          if (progress.remaining != null)
            l10n.progressLeft(format.wait(progress.remaining!)),
          if (progress.predictedBytes != null)
            l10n.aboutSize(format.bytes(progress.predictedBytes!)),
        ].join('  ·  ');
      case JobStatus.paused:
        return l10n.pausedAt(((job.progress?.fraction ?? 0) * 100).floor());
      case JobStatus.done:
        final bytes = result?.outputBytes ?? 0;
        if (job.isSample) {
          final scaled = wholeVideoEstimate(job, result!);
          return l10n.sampleResult(
            format.bytes(bytes),
            format.bytes(scaled?.bytes ?? 0),
            format.wait(scaled?.time ?? Duration.zero),
          );
        }
        return [
          '${format.bytes(job.info.sizeBytes)} → ${format.bytes(bytes)}',
          format.sizeChange(job.info.sizeBytes, bytes),
          l10n.tookTime(format.wait(result?.elapsed ?? Duration.zero)),
        ].join('  ·  ');
      case JobStatus.skipped:
        return job.keptAsIs ? l10n.jobLeftAsIs : l10n.jobSkipped;
      case JobStatus.failed:
        return l10n.statusFailed;
      case JobStatus.cancelled:
        return l10n.statusCancelled;
    }
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (job.status) {
      JobStatus.skipped when job.keptAsIs => scheme.tertiary,
      JobStatus.done || JobStatus.skipped => SuccessColors.of(context).text,
      JobStatus.failed => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
  }

  void _showError(BuildContext context, AppLocalizations l10n) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.statusFailed),
          content: SingleChildScrollView(
            child: SelectableText(
              job.result?.errorLines.join('\n') ?? '',
              style: const TextStyle(fontFamily: monoFontFamily, fontSize: 13),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// The job's goal in plain words, with the technical summary beside it.
class _GoalLine extends ConsumerWidget {
  const _GoalLine({required this.job});

  final QueueJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final capabilities = ref
        .watch(environmentProvider)
        .requireValue
        .capabilities;
    final preset = findPreset(job.recipe.presetId)!;
    final scenario = scenarioOf(preset);
    // What was chosen, in the words of the panel: goal, variant, options.
    final plain = [
      scenarioTitle(l10n, scenario.id),
      if (scenario.presets.length > 1) presetTitle(l10n, preset.id),
      ...chosenOptions(l10n, preset, job.recipe.values, capabilities),
    ].join(' · ');
    // In the goal's own colour, where the look gives goals colours.
    final look = AppLook.of(context);
    final color =
        look.hues?.at(scenarios.indexOf(scenario)).deep ?? look.jobGoal;
    return Row(
      children: [
        Icon(scenarioIcon(scenario.id), size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            plain,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      // With the border, as tall as the file name beside it.
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppLook.of(context).tagRadius),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.job});

  final QueueJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final look = AppLook.of(context);
    final success = SuccessColors.of(context);
    final (icon, background, foreground) = switch (job.status) {
      // Worth a look before the original goes.
      JobStatus.done when job.needsALook => (
        Icons.visibility_rounded,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      JobStatus.skipped when job.keptAsIs => (
        Icons.inventory_2_outlined,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      JobStatus.done || JobStatus.skipped => (
        Icons.check_rounded,
        success.container,
        success.onContainer,
      ),
      JobStatus.failed => (
        Icons.error_outline_rounded,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      JobStatus.running => (
        Icons.autorenew_rounded,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      JobStatus.paused => (
        Icons.pause_rounded,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      JobStatus.cancelled => (
        Icons.block_rounded,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      JobStatus.waiting => (
        job.isSample ? Icons.visibility_outlined : Icons.schedule_rounded,
        look.waiting.soft,
        look.waiting.deep,
      ),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(look.controlRadius),
      ),
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}

/// What comparing a result with its original has shown: how close it comes,
/// in plain words, and the score in small type. While the comparison runs,
/// how far it has got and a way to stop it.
class _QualityLine extends ConsumerWidget {
  const _QualityLine({required this.check});

  final QualityCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall;
    switch (check) {
      case QualityComparing(:final fraction):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: fraction > 0 ? fraction : null),
            Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.comparingWithOriginal((fraction * 100).floor()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  tooltip: l10n.stopComparing,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.stop_rounded),
                  onPressed: ref.read(qualityProvider.notifier).cancel,
                ),
              ],
            ),
          ],
        );
      case QualityMeasured(:final lumaDb, :final vmaf):
        return ClosenessLine(score: QualityScore(lumaDb, vmaf: vmaf));
      case QualityFailed():
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            l10n.compareFailed,
            style: style?.copyWith(color: scheme.error),
          ),
        );
    }
  }
}

/// The job's ⋯ menu: its command, the details of the original and the
/// result, comparing, playing, and the queue's actions.
class _JobMenu extends ConsumerWidget {
  const _JobMenu({required this.job});

  final QueueJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final queue = ref.read(queueProvider.notifier);
    final quality = ref.read(qualityProvider.notifier);
    final result = job.result;
    return PopupMenuButton<void>(
      tooltip: l10n.more,
      icon: const Icon(Icons.more_horiz_rounded),
      itemBuilder: (context) => [
        if (queue.commandFor(job) case final args?)
          PopupMenuItem(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => CommandDialog(args: args),
            ),
            child: Text(l10n.showCommand),
          ),
        PopupMenuItem(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => MediaDetailsDialog(info: job.info),
          ),
          child: Text(l10n.originalDetails),
        ),
        if (job.status == JobStatus.done && result?.outputPath != null)
          PopupMenuItem(
            onTap: () => _showResultDetails(context, ref, result!.outputPath!),
            child: Text(l10n.resultDetails),
          ),
        if (quality.canCompare(job))
          PopupMenuItem(
            enabled: !quality.busy,
            onTap: () => quality.compare(job),
            child: Text(l10n.compareWithOriginal),
          ),
        PopupMenuItem(
          onTap: () => openWithDefaultApp(job.path),
          child: Text(l10n.playOriginal),
        ),
        if (job.status == JobStatus.skipped && job.keptAsIs)
          PopupMenuItem(
            onTap: () => queue.convertAnyway(job.id),
            child: Text(l10n.convertAnyway),
          ),
        PopupMenuItem(
          onTap: () => queue.useSettings(job.id),
          child: Text(l10n.useSettings),
        ),
        PopupMenuItem(
          onTap: () => queue.remove(job.id),
          child: Text(l10n.removeFromList),
        ),
      ],
    );
  }

  Future<void> _showResultDetails(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    final ffprobe = ref.read(environmentProvider).requireValue.ffprobe;
    try {
      final info = await ffprobe.probe(path);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => MediaDetailsDialog(info: info),
      );
    } on FfprobeException {
      // The result was moved or deleted since; nothing to show.
    }
  }
}
