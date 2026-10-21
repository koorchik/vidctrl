import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/ffmpeg/capabilities.dart';
import '../../../core/ffmpeg/locator.dart';
import '../../../core/platform/open_external.dart';
import '../../../core/updates/releases.dart';
import '../../../l10n/app_localizations.dart';
import '../../build_info.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../technical_text.dart';
import 'button_menu.dart';
import 'update_dialog.dart';
import 'web_links.dart';

/// Which FFmpeg the app uses; then the app's version, a check for a newer
/// one, the website, and the licences of everything that comes with the
/// app.
class AboutButton extends ConsumerWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final environment = ref.watch(environmentProvider).value;
    final build = ref.watch(buildInfoProvider);
    final releases = ref.watch(releaseSourceProvider);
    final current = Version.tryParse(build.version);

    // The Builder gives the menu the button's own place on screen.
    return Builder(
      builder: (context) => IconButton(
        // Compact, to keep the header low.
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
                    FfmpegSource.system => l10n.engineSystem,
                  }, style: TextStyle(color: scheme.onSurface)),
                  TechnicalText(_engineCaption(environment)),
                ],
              ),
            ),
          if (environment != null) const PopupMenuDivider(height: 1),
          PopupMenuItem<void>(
            enabled: false,
            child: Text(
              current == null ? l10n.developmentBuild : 'VidCtrl $current',
              style: TextStyle(color: scheme.onSurface),
            ),
          ),
          if (releases != null && current != null)
            PopupMenuItem<void>(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    UpdateDialog(current: current, source: releases),
              ),
              child: Text(l10n.checkForUpdates),
            ),
          PopupMenuItem<void>(
            onTap: () => openWithDefaultApp(websiteUrl),
            child: Text(l10n.website),
          ),
          PopupMenuItem<void>(
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'VidCtrl',
              applicationVersion: current?.toString(),
            ),
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
    FfmpegSource.system =>
      'FFmpeg $version · ${p.dirname(environment.ffmpeg.ffmpeg)}',
  };
}
