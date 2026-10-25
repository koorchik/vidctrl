import 'dart:async';
import 'dart:io';

import 'windows_process.dart';

/// Makes [process] end when this app ends, also when the app cannot stop it
/// itself: killed, crashed, or quit some other way than closing its window.
/// Closing the window stops FFmpeg first; this is for every other end, which
/// would leave it converting for nothing.
///
/// On Windows the process goes into a job that Windows ends together with
/// the app. Elsewhere a small shell waits on a pipe from the app, which the
/// system closes when the app ends for any reason, and then kills the
/// process; it is ended itself when the process ends first. Where that
/// cannot be done, the process runs as before.
Future<void> endWithApp(Process process) async {
  if (Platform.isWindows) {
    endWithThisProcess(process.pid);
    return;
  }
  final Process watchdog;
  try {
    watchdog = await Process.start('/bin/sh', [
      '-c',
      r'read _; kill -KILL "$1" 2>/dev/null',
      'sh',
      '${process.pid}',
    ]);
  } on ProcessException {
    return;
  }
  unawaited(watchdog.stdout.drain<void>());
  unawaited(watchdog.stderr.drain<void>());
  unawaited(process.exitCode.then((_) => watchdog.kill(ProcessSignal.sigkill)));
}
