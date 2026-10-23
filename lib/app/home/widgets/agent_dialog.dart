import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/open_external.dart';
import '../../../l10n/app_localizations.dart';
import '../../control/agent_prompt.dart';
import '../../theme.dart';
import '../headings.dart';

/// Opens "Use with an AI agent".
Future<void> showAgentDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const AgentDialog());

/// What was copied last, for its button to say so for a moment.
enum _Copied { prompt, program }

/// "Use with an AI agent": the text to paste into an agent so it can drive
/// this window through `vidctrl-client`, with the program's real path in it,
/// and which agents can use it. It changes nothing; it only copies text.
class AgentDialog extends ConsumerStatefulWidget {
  const AgentDialog({super.key});

  @override
  ConsumerState<AgentDialog> createState() => _AgentDialogState();
}

class _AgentDialogState extends ConsumerState<AgentDialog> {
  _Copied? _copied;
  Timer? _forget;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _forget?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, _Copied what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = what);
    _forget?.cancel();
    _forget = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    final client = ref.watch(clientExecutableProvider);
    final prompt = client == null
        ? null
        : agentPrompt(
            clientPath: client,
            languageName: agentLanguageNames[l10n.localeName] ?? 'English',
            os: ref.watch(operatingSystemProvider),
          );
    const mono = TextStyle(fontFamily: monoFontFamily, fontSize: 12.5);
    final box = BoxDecoration(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(look.panelRadius),
      border: Border.all(color: scheme.outlineVariant),
    );

    Widget kind(IconData icon, Hue? hue, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: hue?.deep ?? scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    // Tight, to leave the prompt as much room as a small window allows.
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Text(l10n.agentTitle),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 120).clamp(320, 840),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.agentIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: ControlLabel(l10n.agentPromptLabel)),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: prompt == null
                      ? null
                      : () => _copy(prompt, _Copied.prompt),
                  icon: Icon(
                    _copied == _Copied.prompt
                        ? Icons.check_rounded
                        : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _copied == _Copied.prompt ? l10n.copied : l10n.copy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                width: double.infinity,
                decoration: box,
                // Always shown, so a prompt cut off at a small window is
                // plainly one to scroll.
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: prompt == null
                        ? Text(l10n.agentMissing)
                        : SelectableText(
                            prompt,
                            style: mono.copyWith(height: 1.35),
                          ),
                  ),
                ),
              ),
            ),
            if (client != null) ...[
              const SizedBox(height: 12),
              ControlLabel(l10n.agentProgramLabel),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: box,
                      child: SelectableText(client, maxLines: 1, style: mono),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _copied == _Copied.program
                        ? l10n.copied
                        : l10n.copy,
                    onPressed: () => _copy(client, _Copied.program),
                    icon: Icon(
                      _copied == _Copied.program
                          ? Icons.check_rounded
                          : Icons.copy_rounded,
                      size: 18,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => revealInFileManager(client),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text(l10n.showInFolder),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            kind(
              Icons.terminal_rounded,
              look.hues?.green,
              l10n.agentKindCommands,
            ),
            kind(
              Icons.chat_bubble_outline_rounded,
              look.hues?.amber,
              l10n.agentKindChat,
            ),
            kind(Icons.shield_outlined, look.hues?.blue, l10n.agentKindSandbox),
          ],
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
