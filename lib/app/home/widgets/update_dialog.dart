import 'package:flutter/material.dart';

import '../../../core/platform/open_external.dart';
import '../../../core/updates/releases.dart';
import '../../../l10n/app_localizations.dart';

/// Looks for the newest release and says whether it is newer than this
/// version, with a way to its downloads when it is.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.current, required this.source});

  final Version current;
  final ReleaseSource source;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late final Future<Release> _latest = widget.source.latest();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Release>(
      future: _latest,
      builder: (context, snapshot) {
        final close = TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        );
        if (snapshot.hasError) {
          return AlertDialog(
            title: Text(l10n.updateFailedTitle),
            content: Text(l10n.updateFailedBody),
            actions: [close],
          );
        }
        final latest = snapshot.data;
        if (latest == null) {
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text(l10n.updateChecking),
              ],
            ),
            actions: [close],
          );
        }
        if (!(latest.version > widget.current)) {
          return AlertDialog(
            title: Text(l10n.updateNoneTitle),
            content: Text(l10n.updateNoneBody('${widget.current}')),
            actions: [close],
          );
        }
        return AlertDialog(
          title: Text(l10n.updateAvailableTitle),
          content: Text(
            l10n.updateAvailableBody('${latest.version}', '${widget.current}'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateLater),
            ),
            FilledButton(
              onPressed: () {
                openWithDefaultApp('${latest.page}');
                Navigator.of(context).pop();
              },
              child: Text(l10n.updateDownload),
            ),
          ],
        );
      },
    );
  }
}
