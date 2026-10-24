import 'package:flutter/material.dart';

import '../../../core/ffmpeg/capabilities.dart';
import '../../../core/scenarios/option_visibility.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../recipe/recipe.dart';
import '../headings.dart';
import '../scenario_texts.dart';
import '../technical_text.dart';
import 'panel_spacing.dart';

class PanelHint extends StatelessWidget {
  const PanelHint(this.text, {super.key, this.notice = false, this.help});

  final String text;

  /// A "?" at the end that explains more in a window of its own: what it
  /// says on hover, and what opens the window.
  final (String, VoidCallback)? help;

  /// Something worth noticing, such as a limit the goal sets: in the
  /// scheme's colour for those, and a little bolder.
  final bool notice;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final help = this.help;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (help != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Tooltip(
                    message: help.$1,
                    child: InkWell(
                      onTap: help.$2,
                      customBorder: const CircleBorder(),
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        semanticLabel: help.$1,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: notice ? FontWeight.w500 : null,
          color: notice
              ? theme.colorScheme.tertiary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A control with its label to the left, on one row.
class LabeledRow extends StatelessWidget {
  const LabeledRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: PanelSpacing.gap(context)),
      child: Row(
        children: [
          SizedBox(width: PanelSpacing.labelWidth, child: ControlLabel(label)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// One option of a preset: a row of choices, or a switch for yes/no.
class OptionRow extends StatelessWidget {
  const OptionRow({
    super.key,
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
        padding: EdgeInsets.only(top: PanelSpacing.gap(context) - 2),
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
            label: SegmentLabel(
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
      return LabeledRow(label: title, child: choices);
    }
    return Padding(
      padding: EdgeInsets.only(top: PanelSpacing.gap(context)),
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
class SegmentLabel extends StatelessWidget {
  const SegmentLabel(
    this.text, {
    super.key,
    this.caption,
    this.technicalCaption = true,
  });

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
          vertical: PanelSpacing.segmentPadding(context),
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

/// Whether to convert the whole video or a sample of it, from its start or
/// its middle.
class SampleRow extends StatelessWidget {
  const SampleRow({super.key, required this.sample, required this.onChanged});

  final SampleChoice sample;
  final ValueChanged<SampleChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LabeledRow(
      label: l10n.convertTitle,
      child: SegmentedButton<SampleChoice>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: SampleChoice.none,
            label: SegmentLabel(l10n.convertWhole),
          ),
          ButtonSegment(
            value: SampleChoice.start,
            label: SegmentLabel(
              l10n.convertSampleShort,
              caption: l10n.sampleFirst,
              technicalCaption: false,
            ),
          ),
          ButtonSegment(
            value: SampleChoice.middle,
            label: SegmentLabel(
              l10n.convertSampleShort,
              caption: l10n.sampleMiddle,
              technicalCaption: false,
            ),
          ),
        ],
        selected: {sample},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}
