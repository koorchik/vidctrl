import 'package:flutter/material.dart';

import '../../../core/ffmpeg/capabilities.dart';
import '../../../core/scenarios/registry.dart';
import '../../../core/scenarios/scenario.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../scenario_texts.dart';
import '../technical_text.dart';
import 'option_row.dart';
import 'panel_spacing.dart';

/// The goals as a compact grid of three columns. The chosen goal is
/// explained under the grid; the others explain themselves on hover.
class GoalPicker extends StatelessWidget {
  const GoalPicker({super.key, required this.selected, required this.onSelect});

  final Scenario selected;
  final ValueChanged<Scenario> onSelect;

  static const _gap = 6.0;
  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth =
            (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final scenario in scenarios)
              SizedBox(
                width: tileWidth,
                child: _ScenarioTile(
                  scenario: scenario,
                  selected: scenario == selected,
                  onTap: () => onSelect(scenario),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({
    required this.scenario,
    required this.selected,
    required this.onTap,
  });

  final Scenario scenario;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    // Where the look has colours, each goal has its own: a pale tile with
    // the icon in the full colour, and the chosen one deeper and outlined.
    final hue = look.hues?.at(scenarios.indexOf(scenario));
    final Color fill, edge, iconColor;
    if (hue != null) {
      fill = selected ? hue.soft : Color.lerp(scheme.surface, hue.soft, 0.45)!;
      edge = selected ? hue.deep : Color.lerp(hue.soft, hue.deep, 0.2)!;
      iconColor = hue.deep;
    } else {
      fill = selected ? scheme.primaryContainer : scheme.surface;
      edge = selected ? scheme.primary : scheme.outlineVariant;
      iconColor = selected
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant;
    }
    final subtitle = scenarioSubtitle(l10n, scenario.id);
    final textColor = selected && hue == null
        ? scheme.onPrimaryContainer
        : null;
    return Tooltip(
      message: scenarioHint(l10n, scenario.id),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(look.controlRadius),
          side: BorderSide(
            color: edge,
            width: selected ? look.selectedBorderWidth : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: PanelSpacing.tileHeight(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(scenarioIcon(scenario.id), size: 20, color: iconColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scenarioTitle(l10n, scenario.id),
                          maxLines: subtitle.isEmpty ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontSize: 12.5,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11.5,
                              height: 1.2,
                              letterSpacing: 0,
                              fontWeight: FontWeight.w400,
                              color: textColor ?? scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The variants of a goal that has several ("Free" and "Studio"), each with
/// a small caption saying what it makes.
class PresetPicker extends StatelessWidget {
  const PresetPicker({
    super.key,
    required this.presets,
    required this.selected,
    required this.values,
    required this.capabilities,
    required this.onSelect,
  });

  final List<Preset> presets;
  final Preset selected;
  final OptionValues values;
  final Capabilities capabilities;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final preset in presets)
          ButtonSegment(
            value: preset.id,
            label: SegmentLabel(
              presetTitle(l10n, preset.id),
              caption: presetCaption(l10n, preset, values, capabilities),
            ),
          ),
      ],
      selected: {selected.id},
      onSelectionChanged: (ids) => onSelect(ids.first),
    );
  }
}
