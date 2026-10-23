import 'dart:io';

/// Whether a process with this id runs; tests stand in for the system.
typedef ProcessAlive = Future<bool> Function(int pid);

/// Whether process [pid] runs on this computer. When the system cannot be
/// asked, it counts as running: a window wrongly thought gone would be
/// taken over, which is worse than being told to try again.
Future<bool> processIsAlive(int pid) async {
  if (pid <= 0) return false;
  try {
    if (Platform.isLinux) return Directory('/proc/$pid').existsSync();
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/NH',
      ]);
      if (result.exitCode != 0) return true;
      return RegExp('\\b$pid\\b').hasMatch('${result.stdout}');
    }
    // macOS and the rest: signal 0 checks without disturbing it.
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  } on Object {
    return true;
  }
}
