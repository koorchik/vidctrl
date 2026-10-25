import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../queue/keeping_awake.dart';
import '../../queue/queue_controller.dart';
import '../../queue/queue_state.dart';
import '../../queue/queue_summary.dart';
import '../../theme.dart';
import '../headings.dart';
import 'job_tile.dart';
import '../size_change_text.dart';

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
    final progress = overallProgress(state);
    final keepingAwake = ref.watch(keepingAwakeProvider);

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
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress.fraction > 0 ? progress.fraction : null,
                    ),
                  ),
                  if (keepingAwake) ...[
                    const SizedBox(width: 12),
                    const _KeepingAwake(),
                  ],
                ],
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
                  itemBuilder: (context, index) => JobTile(
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
    QueueProgress progress,
  ) {
    if (state.paused) return l10n.queuePaused;
    if (state.busy) {
      return [
        l10n.convertingCount(progress.position, progress.total),
        if (progress.left != null)
          l10n.progressLeft(format.wait(progress.left!)),
      ].join('  ·  ');
    }
    final (:before, :after) = doneSizes(state);
    if (before == 0) return '';
    final toLookAt = state.jobs
        .where((j) => j.status == JobStatus.done && j.needsALook)
        .length;
    return '${l10n.allDone}: ${l10n.savedSummary(format.bytes(before), format.bytes(after))}'
        ', ${format.sizeChange(before, after)}'
        '${toLookAt > 0 ? '  ·  ${l10n.toCheckByEye(toLookAt)}' : ''}';
  }

  /// The headline's "N% larger", when the finished videos grew.
  String? _grownBy(Formatter format, QueueState state) {
    if (state.busy || state.paused) return null;
    final (:before, :after) = doneSizes(state);
    return format.largerBy(before, after);
  }
}

/// Says that the computer will not go to sleep while converting; shown only
/// while its operating system has agreed to that.
class _KeepingAwake extends StatelessWidget {
  const _KeepingAwake();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: l10n.keepingAwakeHint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(AppLook.of(context).tagRadius),
          border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bedtime_off_outlined,
              size: 13,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              l10n.keepingAwake,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
