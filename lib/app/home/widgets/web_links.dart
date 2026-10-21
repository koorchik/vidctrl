import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/open_external.dart';

/// The app's page on the web.
const websiteUrl = 'https://camctrl.app/vidctrl';

/// Where the app is downloaded: the website's own section, which knows every
/// way the app is offered, so the app need not.
const downloadUrl = '$websiteUrl#download';

/// CamCtrl, a remote control for Blackmagic cameras from the same maker.
const camctrlUrl = 'https://camctrl.app';

/// The website's address as people type it.
final websiteAddress = websiteUrl.replaceFirst('https://', '');

/// Words that open a web page in the browser: in the accent colour, and
/// underlined while pointed at. [lead] goes before them in plain text, in the
/// same paragraph, so the two wrap together and take only the room they need.
class WebLink extends StatefulWidget {
  const WebLink(
    this.label, {
    super.key,
    required this.url,
    this.lead,
    this.style,
  });

  final String label;
  final String url;
  final String? lead;

  /// The text's size; small text when not given.
  final TextStyle? style;

  @override
  State<WebLink> createState() => _WebLinkState();
}

class _WebLinkState extends State<WebLink> {
  late final _tap = TapGestureRecognizer()
    ..onTap = () => openWithDefaultApp(widget.url);
  bool _pointed = false;

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lead = widget.lead;
    return Text.rich(
      TextSpan(
        children: [
          if (lead != null)
            TextSpan(
              text: '$lead ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          TextSpan(
            text: widget.label,
            recognizer: _tap,
            mouseCursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _pointed = true),
            onExit: (_) => setState(() => _pointed = false),
            style: TextStyle(
              color: scheme.primary,
              decoration: _pointed ? TextDecoration.underline : null,
              decorationColor: scheme.primary,
            ),
          ),
        ],
      ),
      style: widget.style ?? theme.textTheme.bodySmall,
    );
  }
}
