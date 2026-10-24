import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_details.dart';
import '../../../core/media/media_info.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../detail_texts.dart';
import 'media_details_header.dart';
import 'media_details_views.dart';

enum _View { encoding, metadata, report }

/// Everything known about a video file: a frame from it and its key facts at
/// the top, then how it is encoded, every metadata tag, or FFmpeg's full
/// report.
class MediaDetailsDialog extends ConsumerStatefulWidget {
  const MediaDetailsDialog({super.key, required this.info});

  final MediaInfo info;

  @override
  ConsumerState<MediaDetailsDialog> createState() => _MediaDetailsDialogState();
}

class _MediaDetailsDialogState extends ConsumerState<MediaDetailsDialog> {
  var _view = _View.encoding;
  var _copied = false;
  late final Future<Uint8List?> _thumbnail;

  Map<String, Object?> get _raw => widget.info.raw;

  @override
  void initState() {
    super.initState();
    final info = widget.info;
    final thumbnailer = ref.read(environmentProvider).value?.thumbnailer;
    // A little way in: the very first frame is often black.
    _thumbnail = info.video == null || thumbnailer == null
        ? Future.value()
        : thumbnailer.frame(info.path, at: info.duration * 0.1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MediaDetailsHeader(info: widget.info, thumbnail: _thumbnail),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: Row(
                children: [
                  SegmentedButton<_View>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: _View.encoding,
                        icon: const Icon(Icons.dashboard_outlined, size: 18),
                        label: Text(l10n.detailsViewEncoding),
                      ),
                      ButtonSegment(
                        value: _View.metadata,
                        icon: const Icon(Icons.sell_outlined, size: 18),
                        label: Text(l10n.detailsViewMetadata),
                      ),
                      ButtonSegment(
                        value: _View.report,
                        icon: const Icon(Icons.data_object_rounded, size: 18),
                        label: Text(l10n.detailsViewReport),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (value) => setState(() {
                      _view = value.first;
                      _copied = false;
                    }),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _text(l10n)));
                      if (mounted) setState(() => _copied = true);
                    },
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                    ),
                    label: Text(_copied ? l10n.copied : l10n.copy),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: switch (_view) {
                  _View.encoding => EncodingView(raw: _raw),
                  _View.metadata => MetadataView(raw: _raw),
                  _View.report => ReportView(raw: _raw),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The current view as plain text, for copying.
  String _text(AppLocalizations l10n) {
    final buffer = StringBuffer();
    void section(String title, Iterable<(String, String)> rows) {
      buffer.writeln(title);
      for (final (label, value) in rows) {
        buffer.writeln('  $label: $value');
      }
      buffer.writeln();
    }

    switch (_view) {
      case _View.report:
        return fullReport(_raw);
      case _View.encoding:
        for (final s in orderedDetails(encodingDetails(_raw))) {
          section(groupTitle(l10n, s.group, s.number), [
            for (final row in s.rows)
              (fieldLabel(l10n, row.field), rowValue(l10n, row)),
          ]);
        }
      case _View.metadata:
        for (final s in metadataDetails(_raw)) {
          section(tagTitle(l10n, s), [
            for (final e in s.tags.entries) (e.key, e.value),
          ]);
        }
    }
    return buffer.toString().trimRight();
  }
}
