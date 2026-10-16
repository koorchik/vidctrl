import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings.dart';
import '../../theme.dart';
import 'button_menu.dart';

/// Switches between the app's looks. The choice is remembered.
class LookButton extends ConsumerWidget {
  const LookButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final chosen = ref.watch(lookProvider);
    final controller = ref.read(lookProvider.notifier);

    // The Builder gives the menu the button's own place on screen.
    return Builder(
      builder: (context) => IconButton(
        // Compact, so that the panel's title row has room for its buttons.
        visualDensity: VisualDensity.compact,
        tooltip: l10n.lookTitle,
        icon: Icon(
          Icons.palette_outlined,
          size: 20,
          color: AppLook.of(context).hues?.pink.deep,
        ),
        onPressed: () => showMenuUnder(context, [
          for (final look in Look.values)
            tickedMenuItem(
              label: switch (look) {
                Look.cozy => l10n.lookCozy,
                Look.pro => l10n.lookPro,
              },
              ticked: look == chosen,
              onTap: () => controller.select(look),
            ),
        ]),
      ),
    );
  }
}
