import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_info.dart';
import '../../../core/media/video_files.dart';
import '../../../core/platform/open_external.dart';
import '../../../core/quality/quality_meter.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../queue/queue_controller.dart';
import '../../queue/queue_state.dart';
import '../../sources/preview_controller.dart';
import '../../sources/sources_controller.dart';
import '../../theme.dart';
import '../headings.dart';
import '../technical_text.dart';
import 'busy_mark.dart';
import 'closeness_line.dart';
import 'quality_report.dart';
import 'command_dialog.dart';
import 'media_details_dialog.dart';

/// The videos the user added. Selecting videos tells the "What to do" panel
/// which ones its settings are for.
class VideosPane extends ConsumerWidget {
  const VideosPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final format = Formatter(l10n);
    final state = ref.watch(sourcesProvider);
    final sources = ref.read(sourcesProvider.notifier);
    final selectable = state.videos
        .where((v) => v.status != SourceStatus.unreadable)
        .length;
    final selected = state.selectedIds.length;
    final totalBytes = state.videos.fold<int>(
      0,
      (sum, v) => sum + (v.info?.sizeBytes ?? 0),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: state.videos.isEmpty
            ? const _EmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Tooltip(
                        message: l10n.selectAll,
                        child: Checkbox(
                          tristate: true,
                          value: selected == 0
                              ? false
                              : (selected >= selectable ? true : null),
                          onChanged: (_) => selected >= selectable
                              ? sources.clearSelection()
                              : sources.selectAll(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PaneTitle(l10n.yourVideos),
                            Text(
                              '${l10n.videoCount(state.videos.length)}  ·  '
                              '${format.bytes(totalBytes)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _AddButtons(compact: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: state.videos.length,
                      itemBuilder: (context, index) =>
                          _VideoTile(video: state.videos[index]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddButtons extends ConsumerWidget {
  const _AddButtons({this.compact = false});

  /// Text buttons for the header; larger buttons for the empty list.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sources = ref.read(sourcesProvider.notifier);

    Future<void> pickFiles() async {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(
            label: 'Video',
            extensions: dialogExtensions(linux: Platform.isLinux),
          ),
        ],
      );
      await sources.addPaths(files.map((f) => f.path));
    }

    Future<void> pickFolder() async {
      final folder = await getDirectoryPath();
      if (folder != null) await sources.addPaths([folder]);
    }

    if (compact) {
      return Wrap(
        children: [
          TextButton.icon(
            onPressed: pickFiles,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addVideos),
          ),
          TextButton.icon(
            onPressed: pickFolder,
            icon: const Icon(Icons.folder_outlined),
            label: Text(l10n.addFolder),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: pickFiles,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.addVideos),
        ),
        OutlinedButton.icon(
          onPressed: pickFolder,
          icon: const Icon(Icons.folder_outlined),
          label: Text(l10n.addFolder),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: look.badge.soft,
                borderRadius: BorderRadius.circular(look.paneRadius),
                border: look.flat
                    ? Border.all(color: scheme.outlineVariant)
                    : null,
              ),
              child: Icon(
                Icons.video_library_rounded,
                size: 40,
                color: look.badge.deep,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.dropZoneTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.dropZoneHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            const _AddButtons(),
          ],
        ),
      ),
    );
  }
}

/// One added video: what it is, whether it is selected, and for selected
/// videos what the current settings would do to it.
class _VideoTile extends ConsumerWidget {
  const _VideoTile({required this.video});

  final SourceVideo video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    final format = Formatter(l10n);
    final sources = ref.read(sourcesProvider.notifier);
    final selected = ref.watch(
      sourcesProvider.select((s) => s.selectedIds.contains(video.id)),
    );
    final preview = ref.watch(previewProvider.select((p) => p[video.id]));
    // Counted into a record, which compares by value, so the row is not
    // rebuilt on every progress report of a conversion.
    final (:queued, :done) = ref.watch(
      queueProvider.select((q) {
        final jobs = q.jobs.where((job) => job.sourceId == video.id);
        return (
          queued: jobs.where((job) => job.isPending).length,
          done: jobs.where((job) => job.status == JobStatus.done).length,
        );
      }),
    );
    final info = video.info;
    final unreadable = video.status == SourceStatus.unreadable;

    final facts = switch (video.status) {
      SourceStatus.probing => l10n.statusChecking,
      SourceStatus.unreadable => l10n.statusUnreadable,
      SourceStatus.ready => format.summary(info!),
    };
    final badges = [
      if (queued > 0) l10n.inQueueCount(queued),
      if (done > 0) l10n.doneCount(done),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? look.selectedRow : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(look.panelRadius),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? look.selectedBorderWidth : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: unreadable ? null : () => sources.select(video.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: unreadable
                      ? null
                      : (_) => sources.toggle(video.id),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              format.fileName(video.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (info?.video != null) ...[
                            const SizedBox(width: 8),
                            TechnicalText(sourceFormat(info!.video!)),
                          ],
                          if (preview?.estimate?.choice case final choice?
                              when selected &&
                                  info != null &&
                                  QualityBadge.shows(choice)) ...[
                            const SizedBox(width: 8),
                            QualityBadge(choice: choice, original: info),
                          ],
                        ],
                      ),
                      Text(
                        [facts, if (badges.isNotEmpty) badges].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: unreadable
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (selected && preview != null && info != null)
                        _PreviewLine(preview: preview, info: info),
                    ],
                  ),
                ),
                // To see what a file is before deciding what to do with it,
                // say among a folder's worth just added.
                IconButton(
                  tooltip: l10n.play,
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    color: look.hues?.green.deep,
                  ),
                  onPressed: () => openWithDefaultApp(video.path),
                ),
                if (info != null)
                  PopupMenuButton<void>(
                    tooltip: l10n.more,
                    icon: const Icon(Icons.more_horiz_rounded),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => MediaDetailsDialog(info: info),
                        ),
                        child: Text(l10n.videoDetails),
                      ),
                      PopupMenuItem(
                        onTap: () => showCommandForVideo(context, ref, video),
                        child: Text(l10n.showCommand),
                      ),
                    ],
                  ),
                IconButton(
                  tooltip: l10n.remove,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => sources.remove(video.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the current settings would do to the video, in plain words.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.preview, required this.info});

  final Preview preview;
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = SuccessColors.of(context);
    final format = Formatter(l10n);
    final estimate = preview.estimate;
    final expected = preview.keptAsIs || estimate == null
        ? null
        : '→ ${l10n.aboutSize(format.bytes(estimate.bytes))}';
    // What is being worked out, shown with a spinner.
    final working = preview.keptAsIs || estimate != null
        ? null
        : preview.choosing || preview.measuring
        ? measuringWords(
            l10n,
            choosing: preview.choosing,
            comparing: canComparePlan(preview.plan),
          )
        : null;

    final (text, color) = switch (preview.plan.kind) {
      PlanKind.skip => (l10n.statusReadyAsIs, success.text),
      PlanKind.remux || PlanKind.audioOnly => (
        [l10n.statusQuickFix, ?expected].join('  '),
        scheme.primary,
      ),
      PlanKind.unsupported => (
        switch (preview.plan.notes.firstOrNull) {
          PlanNote.noAudioStream => l10n.statusNoSound,
          PlanNote.containerCannotHold => l10n.statusCannotHold,
          _ => l10n.statusUnsupported,
        },
        scheme.error,
      ),
      PlanKind.encode when preview.keptAsIs => (
        l10n.statusKeptAsIs,
        scheme.onSurfaceVariant,
      ),
      PlanKind.encode => (
        [l10n.statusFullConversion, ?expected].join('  '),
        scheme.onSurface,
      ),
    };
    final notes = [
      for (final note in preview.plan.notes)
        ?switch (note) {
          PlanNote.variableFrameRateFixed => l10n.noteVariableFrameRate,
          PlanNote.hevc422MayPlayChoppily => l10n.noteHevc422,
          PlanNote.experimentalAv1Intermediate => l10n.noteExperimentalAv1,
          PlanNote.hdrToneMapped => l10n.noteHdrToneMapped,
          PlanNote.hdrNotConverted => l10n.noteHdrNotConverted,
          PlanNote.audioConvertedToFit => l10n.noteAudioConvertedToFit,
          _ => null,
        },
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
              if (working != null) ...[
                const SizedBox(width: 10),
                const BusyMark(),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    working,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (preview.plan.kind == PlanKind.encode)
            if (estimate?.choice case final choice?)
              QualityChoiceLine(choice: choice, original: info)
            else if (estimate?.quality case final score?)
              ClosenessLine(score: score),
          for (final note in notes)
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
