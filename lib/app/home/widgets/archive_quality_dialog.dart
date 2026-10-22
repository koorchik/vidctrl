import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../headings.dart';

/// How the archive keeps the quality: the case for a master copy, the two
/// measures and the levels they must reach, how the settings were chosen
/// and that each release is checked. Opened from the "?" at the end of the
/// archive's explanation. The levels are those in `archive.dart` and
/// `quality_meter.dart`; the release check is
/// `test/integration/ffmpeg_check_test.dart`.
class ArchiveQualityDialog extends StatelessWidget {
  const ArchiveQualityDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final success = SuccessColors.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.verified_rounded, color: success.text),
          const SizedBox(width: 10),
          Expanded(child: Text(l10n.archiveQualityTitle)),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.archiveQualityIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Measure(
                      value: l10n.archiveQualityXpsnrValue,
                      name: 'XPSNR',
                      meaning: l10n.archiveQualityXpsnr,
                    ),
                    const SizedBox(width: 10),
                    _Measure(
                      value: '95',
                      name: 'VMAF',
                      meaning: l10n.archiveQualityVmaf,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _Point(l10n.archiveQualityTunedTitle, l10n.archiveQualityTuned),
              _Point(
                l10n.archiveQualityCheckedTitle,
                l10n.archiveQualityChecked,
              ),
              _Point(l10n.archiveQualityYoursTitle, l10n.archiveQualityYours),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

/// A measure: the level it must reach, large, its name, and what it means.
class _Measure extends StatelessWidget {
  const _Measure({
    required this.value,
    required this.name,
    required this.meaning,
  });

  final String value;
  final String name;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(look.controlRadius),
          border: look.flat ? Border.all(color: scheme.outlineVariant) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: SuccessColors.of(context).text,
                  ),
                ),
                const SizedBox(width: 8),
                ControlLabel(name, strong: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              meaning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A heading and its paragraph.
class _Point extends StatelessWidget {
  const _Point(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ControlLabel(title, strong: true),
          const SizedBox(height: 2),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
