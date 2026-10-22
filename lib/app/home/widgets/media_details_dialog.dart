import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/media/media_details.dart';
import '../../../core/media/media_info.dart';
import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../headings.dart';
import '../technical_text.dart';

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
            _Header(info: widget.info, thumbnail: _thumbnail),
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
                  _View.encoding => _EncodingView(raw: _raw),
                  _View.metadata => _MetadataView(raw: _raw),
                  _View.report => _ReportView(raw: _raw),
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
        for (final s in _ordered(encodingDetails(_raw))) {
          section(groupTitle(l10n, s.group, s.number), [
            for (final row in s.rows)
              (fieldLabel(l10n, row.field), rowValue(l10n, row)),
          ]);
        }
      case _View.metadata:
        for (final s in metadataDetails(_raw)) {
          section(_tagTitle(l10n, s), [
            for (final e in s.tags.entries) (e.key, e.value),
          ]);
        }
    }
    return buffer.toString().trimRight();
  }
}

/// A frame of the video, its name and where it is, and the facts people ask
/// about first.
class _Header extends StatelessWidget {
  const _Header({required this.info, required this.thumbnail});

  final MediaInfo info;
  final Future<Uint8List?> thumbnail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = Formatter(l10n);
    final video = info.video;
    final audio = info.audio.firstOrNull;
    final rate = video?.frameRate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(
            thumbnail: thumbnail,
            duration: format.clock(info.duration),
            audioOnly: video == null,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  p.basename(info.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.dirname(info.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (video != null) ...[
                      _Fact(
                        Icons.aspect_ratio_rounded,
                        '${format.resolution(video)}  '
                        '${video.width}×${video.height}',
                        kind: 0,
                      ),
                      _Fact(Icons.movie_outlined, sourceFormat(video), kind: 1),
                      if (video.color.isHdr)
                        _Fact(
                          Icons.hdr_on_rounded,
                          video.color.transfer == 'smpte2084' ? 'HDR10' : 'HLG',
                          highlight: true,
                        ),
                      if (rate != null)
                        _Fact(
                          Icons.speed_rounded,
                          '${_trim(rate.toStringAsFixed(2))} fps',
                          kind: 2,
                        ),
                    ],
                    if (audio != null)
                      _Fact(
                        Icons.graphic_eq_rounded,
                        '${audioFormat(audio)}  ${_channels(audio.channels)}',
                        kind: 3,
                      ),
                    _Fact(
                      Icons.sd_storage_outlined,
                      format.bytes(info.sizeBytes),
                      kind: 4,
                    ),
                    if (info.bitRate case final bitRate?)
                      _Fact(
                        Icons.data_usage_rounded,
                        formatBitrate(bitRate),
                        kind: 5,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.close,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  static String _trim(String number) =>
      number.replaceFirst(RegExp(r'\.?0+$'), '');

  static String _channels(int channels) => switch (channels) {
    1 => 'mono',
    2 => 'stereo',
    6 => '5.1',
    8 => '7.1',
    _ => '$channels ch',
  };
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.thumbnail,
    required this.duration,
    required this.audioOnly,
  });

  final Future<Uint8List?> thumbnail;
  final String duration;
  final bool audioOnly;

  @override
  Widget build(BuildContext context) {
    final look = AppLook.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(look.panelRadius),
      child: SizedBox(
        width: 192,
        height: 108,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Shown until the frame arrives, and for files without one.
            ColoredBox(
              color: look.badge.soft,
              child: Icon(
                audioOnly ? Icons.graphic_eq_rounded : Icons.movie_outlined,
                size: 40,
                color: look.badge.deep.withValues(alpha: 0.7),
              ),
            ),
            FutureBuilder<Uint8List?>(
              future: thumbnail,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                );
              },
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(look.tagRadius),
                ),
                child: Text(
                  duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One key fact as a small rounded label.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, {this.highlight = false, this.kind = 0});

  final IconData icon;
  final String text;

  /// For facts worth noticing, such as HDR.
  final bool highlight;

  /// Which fact of the row this is; each gets its own colour, where the
  /// look has colours.
  final int kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    final hue = highlight ? null : look.hues?.at(kind);
    final background = highlight
        ? scheme.tertiaryContainer
        : hue?.soft ?? scheme.surfaceContainerHighest;
    final foreground = highlight
        ? scheme.onTertiaryContainer
        : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(look.tagRadius),
        border: Border.all(
          color: highlight
              ? scheme.tertiary.withValues(alpha: 0.4)
              : hue?.soft ?? scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: hue?.deep ?? foreground.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picture first, then sound, then the file as a whole.
List<DetailSection> _ordered(List<DetailSection> sections) {
  const order = [
    DetailGroup.video,
    DetailGroup.audio,
    DetailGroup.file,
    DetailGroup.timecode,
    DetailGroup.subtitle,
    DetailGroup.data,
    DetailGroup.attachment,
    DetailGroup.chapters,
  ];
  return [
    for (final group in order) ...sections.where((s) => s.group == group),
  ];
}

/// Cards laid out side by side where there is room: three abreast in a wide
/// window, two in a narrower one. Picture tracks and chapters, which have the
/// most to show, take the full width.
class _Cards extends StatelessWidget {
  const _Cards({required this.cards});

  final List<({bool wide, Widget child})> cards;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        final abreast = full >= 840 ? 3 : (full >= 560 ? 2 : 1);
        final narrow = (full - _gap * (abreast - 1)) / abreast;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final card in cards)
              SizedBox(
                // A whisker less than the exact share, so rounding never
                // pushes the last card of a row onto the next one.
                width: card.wide ? full : narrow - 0.01,
                child: card.child,
              ),
          ],
        );
      },
    );
  }
}

class _EncodingView extends StatelessWidget {
  const _EncodingView({required this.raw});

  final Map<String, Object?> raw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Cards(
      cards: [
        for (final section in _ordered(encodingDetails(raw)))
          (
            wide:
                section.group == DetailGroup.video ||
                section.group == DetailGroup.chapters,
            child: _Card(
              group: section.group,
              title: groupTitle(l10n, section.group, section.number),
              subtitle: section.rows
                  .where((r) => r.field == DetailField.codec)
                  .map((r) => r.value)
                  .firstOrNull,
              child: _FieldGrid(
                rows: [
                  for (final row in section.rows)
                    if (row.field != DetailField.codec) row,
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A track's values as a grid: a small label above each value.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.rows});

  final List<DetailRow> rows;

  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // As many columns as fit cells of a readable width, five at most.
        const narrowest = 118.0;
        final columns = ((width + _gap) / (narrowest + _gap)).floor().clamp(
          1,
          5,
        );
        final cell = (width - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: 10,
          children: [
            for (final row in rows)
              SizedBox(
                width: wideFields.contains(row.field) ? width : cell - 0.01,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fieldLabel(l10n, row.field),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      rowValue(l10n, row),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetadataView extends StatelessWidget {
  const _MetadataView({required this.raw});

  final Map<String, Object?> raw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // One card under another: tag values are lines of text, which read
    // best at the full width.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _Cards._gap,
      children: [
        for (final section in metadataDetails(raw))
          _Card(
            group: section.group,
            title: _tagTitle(l10n, section),
            child: section.tags.isEmpty
                ? Text(
                    l10n.noTags,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : _TagList(tags: section.tags),
          ),
      ],
    );
  }
}

/// A card's tags, one to a line: the name, and its value beside it. A name
/// too long to leave its value room has the value on the next line instead.
class _TagList extends StatelessWidget {
  const _TagList({required this.tags});

  final Map<String, String> tags;

  static const _markWidth = 22.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Names take at most two fifths of a line, so even a narrow card
        // leaves its values a readable width.
        final room = constraints.maxWidth - _markWidth - _gap;
        final besideNames = [
          for (final key in tags.keys)
            if (_nameWidth(key) <= room * 0.4) key,
        ];
        final nameColumn = besideNames.map(_nameWidth).fold(60.0, max);
        return Column(
          children: [
            for (final MapEntry(:key, :value) in tags.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _markWidth,
                      child: isPersonalTag(key)
                          ? Tooltip(
                              message: l10n.personalTag,
                              child: Icon(
                                Icons.person_pin_circle_outlined,
                                size: 16,
                                color: scheme.tertiary,
                              ),
                            )
                          : null,
                    ),
                    if (besideNames.contains(key)) ...[
                      SizedBox(width: nameColumn, child: _name(key, scheme)),
                      const SizedBox(width: _gap),
                      Expanded(child: _value(value, theme)),
                    ] else
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_name(key, scheme), _value(value, theme)],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _name(String key, ColorScheme scheme) => Text(
    key,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: monoFontFamily,
      fontSize: 12.5,
      height: 1.5,
      color: scheme.onSurfaceVariant,
    ),
  );

  Widget _value(String value, ThemeData theme) =>
      SelectableText(value, style: theme.textTheme.bodyMedium);
}

/// The room a tag name takes on one line. A character of the fixed-width
/// font at this size is 7.5 pixels wide.
double _nameWidth(String key) => key.length * 7.6 + 6;

class _ReportView extends StatelessWidget {
  const _ReportView({required this.raw});

  final Map<String, Object?> raw;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppLook.of(context).panelRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SelectableText(
        fullReport(raw),
        style: const TextStyle(
          fontFamily: monoFontFamily,
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    );
  }
}

/// One track or the file as a whole: an icon, a title and its content.
class _Card extends StatelessWidget {
  const _Card({
    required this.group,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final DetailGroup group;
  final String title;

  /// Shown under the title, e.g. the track's codec.
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    // Each kind of track has its colour, where the look has colours.
    final mark = look.hues?.at(group.index) ?? look.badge;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(look.panelRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: mark.soft,
                  borderRadius: BorderRadius.circular(look.tagRadius),
                ),
                child: Icon(_icon(group), size: 17, color: mark.deep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ControlLabel(title, strong: true),
                    if (subtitle != null)
                      Tooltip(
                        message: subtitle,
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  static IconData _icon(DetailGroup group) => switch (group) {
    DetailGroup.file => Icons.insert_drive_file_outlined,
    DetailGroup.video => Icons.movie_outlined,
    DetailGroup.audio => Icons.graphic_eq_rounded,
    DetailGroup.subtitle => Icons.subtitles_outlined,
    DetailGroup.timecode => Icons.timer_outlined,
    DetailGroup.data => Icons.data_object_rounded,
    DetailGroup.attachment => Icons.attach_file_rounded,
    DetailGroup.chapters => Icons.bookmarks_outlined,
  };
}

String _tagTitle(AppLocalizations l10n, TagSection section) =>
    section.group == DetailGroup.chapters
    ? l10n.groupChapter(section.number)
    : groupTitle(l10n, section.group, section.number);

String groupTitle(AppLocalizations l10n, DetailGroup group, int number) =>
    switch (group) {
      DetailGroup.file => l10n.groupFile,
      DetailGroup.video => l10n.groupVideo(number),
      DetailGroup.audio => l10n.groupAudio(number),
      DetailGroup.subtitle => l10n.groupSubtitle(number),
      DetailGroup.timecode => l10n.groupTimecode,
      DetailGroup.data => l10n.groupData(number),
      DetailGroup.attachment => l10n.groupAttachment(number),
      DetailGroup.chapters => l10n.groupChapters,
    };

String fieldLabel(AppLocalizations l10n, DetailField field) => switch (field) {
  DetailField.container => l10n.fieldContainer,
  DetailField.size => l10n.fieldSize,
  DetailField.duration => l10n.fieldDuration,
  DetailField.bitrate => l10n.fieldBitrate,
  DetailField.tracks => l10n.fieldTracks,
  DetailField.codec => l10n.fieldCodec,
  DetailField.resolution => l10n.fieldResolution,
  DetailField.aspectRatio => l10n.fieldAspectRatio,
  DetailField.frameRate => l10n.fieldFrameRate,
  DetailField.bitDepth => l10n.fieldBitDepth,
  DetailField.chroma => l10n.fieldChroma,
  DetailField.pixelFormat => l10n.fieldPixelFormat,
  DetailField.colorPrimaries => l10n.fieldColorPrimaries,
  DetailField.colorTransfer => l10n.fieldColorTransfer,
  DetailField.colorMatrix => l10n.fieldColorMatrix,
  DetailField.colorRange => l10n.fieldColorRange,
  DetailField.hdr => l10n.fieldHdr,
  DetailField.masteringDisplay => l10n.fieldMasteringDisplay,
  DetailField.lightLevel => l10n.fieldLightLevel,
  DetailField.scanType => l10n.fieldScanType,
  DetailField.rotation => l10n.fieldRotation,
  DetailField.frames => l10n.fieldFrames,
  DetailField.channels => l10n.fieldChannels,
  DetailField.sampleRate => l10n.fieldSampleRate,
  DetailField.sampleFormat => l10n.fieldSampleFormat,
  DetailField.language => l10n.fieldLanguage,
  DetailField.title => l10n.fieldTitle,
  DetailField.defaultTrack => l10n.fieldDefaultTrack,
  DetailField.timecode => l10n.fieldTimecode,
  DetailField.fileName => l10n.fieldFileName,
  DetailField.chapter => l10n.fieldChapter,
};

/// The translated word, if any, followed by the technical value.
String rowValue(AppLocalizations l10n, DetailRow row) {
  final note = switch (row.note) {
    DetailNote.variable => l10n.noteVariable,
    DetailNote.progressive => l10n.noteProgressive,
    DetailNote.interlaced => l10n.noteInterlaced,
    DetailNote.notStated => l10n.noteNotStated,
    DetailNote.yes => l10n.noteYes,
    DetailNote.no => l10n.noteNo,
    null => null,
  };
  return [?note, if (row.value.isNotEmpty) row.value].join(': ');
}
