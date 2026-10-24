import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/media/media_details.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../detail_texts.dart';
import '../headings.dart';

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

class EncodingView extends StatelessWidget {
  const EncodingView({super.key, required this.raw});

  final Map<String, Object?> raw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Cards(
      cards: [
        for (final section in orderedDetails(encodingDetails(raw)))
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

class MetadataView extends StatelessWidget {
  const MetadataView({super.key, required this.raw});

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
            title: tagTitle(l10n, section),
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

class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.raw});

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
