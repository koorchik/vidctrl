import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../queue/queue_controller.dart';
import '../../queue/queue_state.dart';
import '../../queue/queue_summary.dart';
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
