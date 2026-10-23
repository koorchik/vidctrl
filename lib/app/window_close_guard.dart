import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import 'estimates/estimate_cache.dart';
import 'quality/quality_controller.dart';
import 'queue/queue_controller.dart';

/// Asks before closing the window while videos are being converted, so a
/// stray click does not throw away an hour of work, and stops FFmpeg before
/// the app goes.
class WindowCloseGuard extends ConsumerStatefulWidget {
  const WindowCloseGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowCloseGuard> createState() => _WindowCloseGuardState();
}

class _WindowCloseGuardState extends ConsumerState<WindowCloseGuard>
    with WindowListener {
  /// The question is on screen.
  bool _asking = false;

  /// Set once the app is on its way out. Destroying the window makes the
  /// plugin report a second close, and destroying it again when it no longer
  /// exists crashes the app on Linux.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (_asking || _leaving) return;
    if (ref.exists(queueProvider) && ref.read(queueProvider).busy) {
      _asking = true;
      final quit = await _confirmQuit();
      _asking = false;
      if (!quit || !mounted) return;
    }
    _leaving = true;
    try {
      // FFmpeg has to stop before the app goes: left alone it would carry on
      // converting, and the unfinished file would stay behind.
      if (ref.exists(queueProvider)) {
        await ref.read(queueProvider.notifier).shutDown();
      }
      if (ref.exists(estimateCacheProvider)) {
        await ref.read(estimateCacheProvider.notifier).leave();
      }
      if (ref.exists(qualityProvider)) {
        await ref.read(qualityProvider.notifier).stop();
      }
    } finally {
      await windowManager.destroy();
    }
  }

  Future<bool> _confirmQuit() async {
    final l10n = AppLocalizations.of(context)!;
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.quitTitle),
        content: Text(l10n.quitBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.quit),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.keepConverting),
          ),
        ],
      ),
    );
    return quit ?? false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
