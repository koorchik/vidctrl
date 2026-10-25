import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/control/process_alive.dart';

void main() {
  test(
    'a program the app started ends when the app ends unexpectedly',
    () async {
      final app = await Process.run('dart', [
        'run',
        'test/support/abandoning_app.dart',
      ], runInShell: Platform.isWindows);
      expect(app.exitCode, 0, reason: '${app.stderr}');
      final left = int.parse(
        const LineSplitter().convert('${app.stdout}').last,
      );
      addTearDown(() => Process.killPid(left, ProcessSignal.sigkill));

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (await processIsAlive(left) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await processIsAlive(left), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
