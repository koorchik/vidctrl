import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/updates/releases.dart';
import '../../../l10n/app_localizations.dart';
import '../../build_info.dart';
import '../../theme.dart';
import 'update_dialog.dart';

/// Beside the website's address once the app has found a release newer than
/// itself: which one, in the colour of things worth noticing, and the way to
/// its download.
class NewVersionTag extends ConsumerWidget {
  const NewVersionTag({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(newerReleaseProvider).value;
    final source = ref.watch(releaseSourceProvider);
    final current = Version.tryParse(ref.watch(buildInfoProvider).version);
    if (release == null || source == null || current == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppLook.of(context).tagRadius);
    return Tooltip(
      message: l10n.updateAvailableBody('${release.version}', '$current'),
      child: Material(
        color: scheme.tertiaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.4)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) =>
                UpdateDialog(current: current, source: source, known: release),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_circle_up_rounded,
                  size: 14,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.newVersionTag('${release.version}'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
