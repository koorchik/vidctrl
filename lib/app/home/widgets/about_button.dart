import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/ffmpeg/capabilities.dart';
import '../../../core/ffmpeg/locator.dart';
import '../../../core/platform/open_external.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../settings.dart';
import '../../theme.dart';
import '../technical_text.dart';
import 'button_menu.dart';
import 'web_links.dart';

/// Which FFmpeg the app uses, a way to use another, the website, and the
/// licences of everything that comes with the app.
class AboutButton extends ConsumerWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final environment = ref.watch(environmentProvider).value;
    final chosenFolder = ref.watch(ffmpegFolderProvider);

    // The Builder gives the menu the button's own place on screen.
    return Builder(
      builder: (context) => IconButton(
        // Compact, so that the panel's title row has room for its buttons.
        visualDensity: VisualDensity.compact,
        tooltip: l10n.aboutTitle,
        icon: Icon(
          Icons.info_outline_rounded,
          size: 20,
          color: AppLook.of(context).hues?.blue.deep,
        ),
        onPressed: () => showMenuUnder(context, [
          if (environment != null)
            PopupMenuItem<void>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(switch (environment.ffmpeg.source) {
                    FfmpegSource.bundled => l10n.engineBuiltIn,
                    FfmpegSource.chosen => l10n.engineChosen,
                    FfmpegSource.system => l10n.engineSystem,
                  }, style: TextStyle(color: scheme.onSurface)),
                  TechnicalText(_engineCaption(environment)),
                ],
              ),
            ),
          PopupMenuItem<void>(
            onTap: () async {
              if (await chooseFfmpegFolder(context, ref) && context.mounted) {
                await _useFrom(context, ref, environment);
              }
            },
            child: Text(l10n.engineChooseFolder),
          ),
          if (chosenFolder != null)
            PopupMenuItem<void>(
              onTap: () async {
                await ref.read(ffmpegFolderProvider.notifier).select(null);
                if (context.mounted) await _useFrom(context, ref, environment);
              },
              child: Text(l10n.engineUseBuiltIn),
            ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem<void>(
            onTap: () => openWithDefaultApp(websiteUrl),
            child: Text(l10n.website),
          ),
          PopupMenuItem<void>(
            onTap: () =>
                showLicensePage(context: context, applicationName: 'VidCtrl'),
            child: Text(l10n.licences),
          ),
        ]),
      ),
    );
  }
}

/// "FFmpeg 8.1.3", with the folder it is in unless it is the app's own.
String _engineCaption(AppEnvironment environment) {
  final version = shortFfmpegVersion(environment.capabilities.ffmpegVersion);
  return switch (environment.ffmpeg.source) {
    FfmpegSource.bundled => 'FFmpeg $version',
    _ => 'FFmpeg $version · ${p.dirname(environment.ffmpeg.ffmpeg)}',
  };
}

/// Asks for the folder of the user's own FFmpeg and remembers it. A folder
/// without ffmpeg and ffprobe is refused with a message. Returns whether a
/// folder was taken.
Future<bool> chooseFfmpegFolder(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final folder = await getDirectoryPath();
  if (folder == null || !context.mounted) return false;
  if (FfmpegLocator().inFolder(folder) == null) {
    await _tell(context, l10n.engineFolderWrong);
    return false;
  }
  await ref.read(ffmpegFolderProvider.notifier).select(folder);
  return true;
}

/// After another FFmpeg is chosen: everything the app holds is built on the
/// one in [environment], so the new one is used from the next start. Without
/// one (still starting, or none found) nothing is built yet, and the app
/// looks again at once.
Future<void> _useFrom(
  BuildContext context,
  WidgetRef ref,
  AppEnvironment? environment,
) async {
  if (environment == null) {
    ref.invalidate(environmentProvider);
    return;
  }
  await _tell(context, AppLocalizations.of(context)!.engineNextStart);
}

Future<void> _tell(BuildContext context, String message) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
