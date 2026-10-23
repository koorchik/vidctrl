import 'package:flutter/material.dart';

import '../../../core/quality/quality_meter.dart';
import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../theme.dart';
import '../technical_text.dart';

/// How close a picture comes to its original: in plain words, coloured by
/// the verdict, and the scores in small type. For a finished comparison and
/// for what the expected-size samples showed alike.
class ClosenessLine extends StatelessWidget {
  const ClosenessLine({super.key, required this.score});

  final QualityScore score;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = Formatter(l10n);
    final (words, color) = switch (score.closeness) {
      Closeness.same => (l10n.closenessSame, SuccessColors.of(context).text),
      Closeness.veryClose => (l10n.closenessVeryClose, scheme.onSurfaceVariant),
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
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: TechnicalText(
              [
                if (score.vmaf case final vmaf?)
                  l10n.vmafScore(format.score(vmaf)),
                l10n.xpsnrScore(format.score(score.lumaDb)),
              ].join('  ·  '),
            ),
          ),
        ],
      ),
    );
  }
}
