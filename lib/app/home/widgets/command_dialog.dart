import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffmpeg/command_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../queue/queue_controller.dart';
import '../../sources/sources_controller.dart';
import '../../theme.dart';

/// Shows the command [video] would run with the panel's current settings,
/// as "Show the command" does wherever it is offered.
void showCommandForVideo(
  BuildContext context,
  WidgetRef ref,
  SourceVideo video,
) {
  final args = ref.read(queueProvider.notifier).commandForVideo(video);
  if (args == null) return;
  unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => CommandDialog(args: args),
    ),
  );
}

/// Shows the FFmpeg command for one video, for people who want to see exactly
/// what happens, run it themselves or adjust it.
///
/// Two forms: the whole command on one line, or one option per line with a
/// comment on each. Both can be pasted into a terminal as they are.
class CommandDialog extends StatefulWidget {
  const CommandDialog({super.key, required this.args, this.shell});

  /// The arguments as shown to people (see `buildFfmpegArgs(forDisplay:)`).
  final List<String> args;

  /// Defaults to the terminal of the platform the app runs on.
  final ShellStyle? shell;

  @override
  State<CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<CommandDialog> {
  bool _explained = false;
  bool _copied = false;

  String _text(AppLocalizations l10n) => _explained
      ? explainedCommand(
          'ffmpeg',
          widget.args,
          shell: widget.shell,
          describe: (part) => describeArg(l10n, part.meaning),
        )
      : singleLineCommand('ffmpeg', widget.args, shell: widget.shell);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = _text(l10n);

    return AlertDialog(
      title: Text(l10n.commandTitle),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 120).clamp(320, 980),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.commandIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(l10n.commandOneLine),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(l10n.commandExplained),
                    ),
                  ],
                  selected: {_explained},
                  onSelectionChanged: (value) => setState(() {
                    _explained = value.first;
                    _copied = false;
                  }),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _copy(text),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(_copied ? l10n.copied : l10n.copy),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(
                        AppLook.of(context).panelRadius,
                      ),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        // The explained form is laid out in columns, so it
                        // scrolls sideways instead of wrapping.
                        scrollDirection: Axis.horizontal,
                        physics: _explained
                            ? null
                            : const NeverScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _explained ? double.infinity : 900,
                          ),
                          child: SelectableText(
                            text,
                            style: const TextStyle(
                              fontFamily: monoFontFamily,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

/// The comment shown next to one part of the command.
String describeArg(AppLocalizations l10n, ArgMeaning meaning) =>
    switch (meaning) {
      ArgMeaning.hideBanner => l10n.cmdHideBanner,
      ArgMeaning.seek => l10n.cmdSeek,
      ArgMeaning.input => l10n.cmdInput,
      ArgMeaning.length => l10n.cmdLength,
      ArgMeaning.keepPicture => l10n.cmdKeepPicture,
      ArgMeaning.keepSound => l10n.cmdKeepSound,
      ArgMeaning.noPicture => l10n.cmdNoPicture,
      ArgMeaning.noSound => l10n.cmdNoSound,
      ArgMeaning.keepMetadata => l10n.cmdKeepMetadata,
      ArgMeaning.dropMetadata => l10n.cmdDropMetadata,
      ArgMeaning.pictureCopy => l10n.cmdPictureCopy,
      ArgMeaning.pictureEncoder => l10n.cmdPictureEncoder,
      ArgMeaning.soundCopy => l10n.cmdSoundCopy,
      ArgMeaning.soundEncoder => l10n.cmdSoundEncoder,
      ArgMeaning.speedPreset => l10n.cmdSpeedPreset,
      ArgMeaning.quality => l10n.cmdQuality,
      ArgMeaning.profile => l10n.cmdProfile,
      ArgMeaning.encoderTuning => l10n.cmdEncoderTuning,
      ArgMeaning.pixelFormat => l10n.cmdPixelFormat,
      ArgMeaning.filter => l10n.cmdFilter,
      ArgMeaning.soundBitrate => l10n.cmdSoundBitrate,
      ArgMeaning.constantFrameRate => l10n.cmdConstantFrameRate,
      ArgMeaning.frameRate => l10n.cmdFrameRate,
      ArgMeaning.keyframeInterval => l10n.cmdKeyframeInterval,
      ArgMeaning.playerTag => l10n.cmdPlayerTag,
      ArgMeaning.fastStart => l10n.cmdFastStart,
      ArgMeaning.fastStartKeepingTags => l10n.cmdFastStartKeepingTags,
      ArgMeaning.dropTag => l10n.cmdDropTag,
      ArgMeaning.levelLimit => l10n.cmdLevelLimit,
      ArgMeaning.container => l10n.cmdContainer,
      ArgMeaning.output => l10n.cmdOutput,
      ArgMeaning.other => '',
    };
