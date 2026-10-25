import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/platform/sleep_inhibitor.dart';

import '../../support/eventually.dart';

/// What the operating system itself says keeps it awake, by the reason
/// VidCtrl gives.
Future<bool> systemSeesVidCtrl() async {
  final ProcessResult listing;
  if (Platform.isLinux) {
    listing = await Process.run('systemd-inhibit', ['--list', '--no-pager']);
  } else if (Platform.isMacOS) {
    listing = await Process.run('pmset', ['-g', 'assertions']);
  } else {
    // Lists the power requests of every program; needs an administrator,
    // which the build servers are.
    listing = await Process.run('powercfg', ['/requests']);
  }
  return '${listing.stdout}'.contains(
    Platform.isMacOS ? 'caffeinate' : 'Converting videos',
  );
}

void main() {
  test(
    'the computer is kept awake for as long as asked, and says so',
    () async {
      final inhibitor = SleepInhibitor.forPlatform();
      final changes = <bool>[];
      final listening = inhibitor.changes.listen(changes.add);
      addTearDown(listening.cancel);
      addTearDown(inhibitor.release);

      await inhibitor.acquire();
      if (Platform.isLinux && !inhibitor.isActive) {
        // systemd may refuse a program outside a desktop session, as on a
        // build server; then nothing claims the computer stays awake.
        expect(await systemSeesVidCtrl(), isFalse);
        markTestSkipped('systemd refused to keep this computer awake');
        return;
      }

      expect(inhibitor.isActive, isTrue);
      expect(await systemSeesVidCtrl(), isTrue);

      await inhibitor.release();
      expect(inhibitor.isActive, isFalse);
      await eventually(() => changes.length == 2);
      expect(changes, [true, false]);
      // The helper may take a moment to end.
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (await systemSeesVidCtrl() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await systemSeesVidCtrl(), isFalse);
    },
  );
}
