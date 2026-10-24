import 'dart:io';

import 'package:path/path.dart' as p;

/// Opens a file or a web address with the system's default application,
/// e.g. a converted sample in the video player or a page in the browser.
Future<void> openWithDefaultApp(String path) async {
  if (Platform.isWindows) {
    // `start` is a shell built-in; the empty string is the window title.
    await _start('cmd', ['/c', 'start', '', path]);
  } else {
    await _start(Platform.isMacOS ? 'open' : 'xdg-open', [path]);
  }
}

/// Shows a file in the system file manager, selected where that is possible.
Future<void> revealInFileManager(String path) async {
  if (Platform.isWindows) {
    await _start('explorer', ['/select,', path]);
  } else if (Platform.isMacOS) {
    await _start('open', ['-R', path]);
  } else {
    // Linux has no universal "select this file" command; opening the folder
    // works on every desktop.
    await _start('xdg-open', [p.dirname(path)]);
  }
}

/// Starts [program]; nothing waits for it. A computer without it (no
/// `xdg-open`) just opens nothing.
Future<void> _start(String program, List<String> arguments) async {
  try {
    await Process.start(program, arguments);
  } on ProcessException {
    // Nothing to open it with.
  }
}
