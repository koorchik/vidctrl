import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/estimate/size_estimator.dart';
import '../../../core/media/ffprobe.dart';
import '../../../core/platform/open_external.dart';
import '../../../core/quality/quality_meter.dart';
import '../../../core/scenarios/registry.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../estimates/estimate_cache.dart';
import '../../format.dart';
import '../../providers.dart';
import '../../quality/quality_controller.dart';
import '../../queue/queue_controller.dart';
import '../../queue/queue_state.dart';
import '../../theme.dart';
import '../headings.dart';
import '../scenario_texts.dart';
import '../size_change_text.dart';
import '../technical_text.dart';
import 'command_dialog.dart';
import 'media_details_dialog.dart';

/// The conversions, in the order they run. Starts by itself; can be paused,
/// reordered and edited at any time.
class QueuePane extends ConsumerWidget {
  const QueuePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = Formatter(l10n);
    final state = ref.watch(queueProvider);
    final queue = ref.read(queueProvider.notifier);
    final progress = _overallProgress(state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PaneTitle(l10n.queueTitle),
                const SizedBox(width: 14),
                Expanded(
                  child: SizeChangeText(
                    _headline(l10n, format, state, progress),
                    larger: _grownBy(format, state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (state.busy || state.paused)
                  TextButton.icon(
                    onPressed: queue.togglePause,
                    icon: Icon(
                      state.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    label: Text(state.paused ? l10n.resume : l10n.pause),
                  ),
                if (state.hasFinished)
                  TextButton(
                    onPressed: queue.clearFinished,
                    child: Text(l10n.clearFinished),
                  ),
              ],
            ),
            if (state.busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.fraction > 0 ? progress.fraction : null,
              ),
            ],
            if (state.jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  l10n.queueEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 10),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: state.jobs.length,
                  onReorderItem: queue.reorder,
                  itemBuilder: (context, index) => _JobTile(
                    key: ValueKey(state.jobs[index].id),
                    job: state.jobs[index],
                    index: index,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _headline(
    AppLocalizations l10n,
    Formatter format,
    QueueState state,
    ({double fraction, Duration? left, int position, int total}) progress,
  ) {
    if (state.paused) return l10n.queuePaused;
    if (state.busy) {
      return [
        l10n.convertingCount(progress.position, progress.total),
        if (progress.left != null)
          l10n.progressLeft(format.wait(progress.left!)),
      ].join('  ·  ');
    }
    final (:before, :after) = _doneSizes(state);
    if (before == 0) return '';
    return '${l10n.allDone}: ${l10n.savedSummary(format.bytes(before), format.bytes(after))}'
        ', ${format.sizeChange(before, after)}';
  }

  /// What the finished whole videos weighed before and after.
  ({int before, int after}) _doneSizes(QueueState state) {
    final done = state.jobs.where(
      (j) => j.status == JobStatus.done && !j.isSample,
    );
    return (
      before: done.fold<int>(0, (s, j) => s + j.info.sizeBytes),
      after: done.fold<int>(0, (s, j) => s + (j.result?.outputBytes ?? 0)),
    );
  }

  /// The headline's "N% larger", when the finished videos grew.
  String? _grownBy(Formatter format, QueueState state) {
    if (state.busy || state.paused) return null;
    final (:before, :after) = _doneSizes(state);
    return format.largerBy(before, after);
  }

  /// Progress across the jobs of this run, weighted by how much video each
  /// converts. Waiting jobs are assumed to go at the current job's speed;
  /// quick fixes take seconds and are not counted towards the time left.
  ({double fraction, Duration? left, int position, int total}) _overallProgress(
    QueueState state,
  ) {
    double seconds(QueueJob job) =>
        (job.sample?.length ?? job.info.duration).inMilliseconds / 1000;
    final active = state.activeJob;
    final waiting = state.waiting;
    final finished = state.jobs.where(
      (j) => j.status == JobStatus.done || j.status == JobStatus.skipped,
    );
    final doneSeconds = finished.fold<double>(0, (s, j) => s + seconds(j));
    final activeSeconds = active == null ? 0.0 : seconds(active);
    final total =
        doneSeconds +
        activeSeconds +
        waiting.fold<double>(0, (s, j) => s + seconds(j));
    final fraction = total > 0
        ? (doneSeconds + activeSeconds * (active?.progress?.fraction ?? 0)) /
              total
        : 0.0;

    final speed = active?.progress?.speed;
    final remaining = active?.progress?.remaining;
    Duration? left;
    if (remaining != null && speed != null && speed > 0) {
      final waitingEncodes = waiting
          .where((j) => j.plan.kind == PlanKind.encode)
          .fold<double>(0, (s, j) => s + seconds(j));
      left =
          remaining +
          Duration(milliseconds: (waitingEncodes / speed * 1000).round());
    }
    final position = finished.length + 1;
    return (
      fraction: fraction,
      left: left,
      position: position,
      total: position + waiting.length,
    );
  }
}

/// One conversion: which video, with what settings, where it goes, and how
/// it is getting on.
class _JobTile extends ConsumerWidget {
  const _JobTile({super.key, required this.job, required this.index});

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
    final quality = ref.read(qualityProvider.notifier);
    final check = ref.watch(qualityProvider.select((checks) => checks[job.id]));

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
                if (job.plan.producesOutput)
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
          PopupMenuButton<void>(
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
                  onTap: () =>
                      _showResultDetails(context, ref, result!.outputPath!),
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
              PopupMenuItem(
                onTap: () => queue.useSettings(job.id),
                child: Text(l10n.useSettings),
              ),
              PopupMenuItem(
                onTap: () => queue.remove(job.id),
                child: Text(l10n.removeFromList),
              ),
            ],
          ),
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
        return [
          l10n.jobWaiting,
          if (whole != null)
            l10n.aboutSize(format.bytes((whole.bytes * sampleShare).round())),
        ].join('  ·  ');
      case JobStatus.running:
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
        return l10n.jobSkipped;
      case JobStatus.failed:
        return l10n.statusFailed;
      case JobStatus.cancelled:
        return l10n.statusCancelled;
    }
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (job.status) {
      JobStatus.done || JobStatus.skipped => SuccessColors.of(context).text,
      JobStatus.failed => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
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

  void _showError(BuildContext context, AppLocalizations l10n) {
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
    final scenario = scenarios.firstWhere((s) => s.presets.contains(preset));
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
    final format = Formatter(l10n);
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
      case QualityMeasured(:final lumaDb, :final vmaf, :final closeness):
        final (words, color) = switch (closeness) {
          Closeness.same => (
            l10n.closenessSame,
            SuccessColors.of(context).text,
          ),
          Closeness.veryClose => (
            l10n.closenessVeryClose,
            scheme.onSurfaceVariant,
          ),
          Closeness.differs => (l10n.closenessDiffers, scheme.tertiary),
        };
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  words,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: TechnicalText(
                  [
                    if (vmaf != null) l10n.vmafScore(format.score(vmaf)),
                    l10n.xpsnrScore(format.score(lumaDb)),
                  ].join('  ·  '),
                ),
              ),
            ],
          ),
        );
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
