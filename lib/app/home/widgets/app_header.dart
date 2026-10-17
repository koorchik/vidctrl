import 'package:flutter/material.dart';

import 'about_button.dart';
import 'language_button.dart';
import 'look_button.dart';
import 'web_links.dart';

/// The line along the top of the window: the app's name and website on the
/// left, and the buttons that concern the whole app on the right. It is on
/// every screen, so the website, the About menu, the look and the language
/// are there even when FFmpeg is missing.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  /// It takes the place of the margin above the panes.
  static const height = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Image.asset('assets/app_icon.png', width: 22, height: 22),
          const SizedBox(width: 8),
          Text(
            'VidCtrl',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          WebLink(websiteAddress, url: websiteUrl),
          // The buttons end where the panel below them does.
          const Spacer(),
          const AboutButton(),
          const LookButton(),
          const LanguageButton(),
        ],
      ),
    );
  }
}
