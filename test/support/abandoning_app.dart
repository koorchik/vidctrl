import 'dart:io';

import 'package:vidctrl/core/platform/end_with_app.dart';

/// An app that starts a long-running program, as it starts FFmpeg, prints
/// that program's process id and then ends without stopping it, as a crash
/// would. Run by `end_with_app_test.dart`.
Future<void> main() async {
  final long = Platform.isWindows
      ? await Process.start('ping', ['-n', '120', '127.0.0.1'])
      : await Process.start('sleep', ['120']);
  await endWithApp(long);
  stdout.writeln(long.pid);
  await stdout.flush();
  exit(0);
}
