import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../theme.dart';
import 'agent_dialog.dart';

/// Opens "Use with an AI agent". Not on the "engine missing" screen, where
/// an agent would have nothing to do.
class AgentButton extends ConsumerWidget {
  const AgentButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(environmentProvider).value == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      // Compact, to keep the header low.
      visualDensity: VisualDensity.compact,
      tooltip: l10n.agentTitle,
      icon: Icon(
        Icons.smart_toy_outlined,
        size: 20,
        color:
            AppLook.of(context).hues?.violet.deep ??
            Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () => showAgentDialog(context),
    );
  }
}
