import 'dart:io';

import 'package:path/path.dart' as p;

import 'protocol.dart';

/// Finds the VidCtrl window that came with `vidctrl-client` and starts it.
/// The client finds it through its own resolved path, so a link to the
/// client on the `PATH` still leads into the bundle.
class AppLauncher {
  AppLauncher({
    required this.os,
    required this.clientExecutable,
    required this.environment,
  });

  /// A `Platform.operatingSystem` value.
  final String os;

  /// The client's own path, links followed.
  final String clientExecutable;
  final Map<String, String> environment;

  /// `VIDCTRL_APP` when set; else the app beside the client: `vidctrl` in
  /// the Linux bundle, `vidctrl.exe` on Windows, the `.app` around
  /// `Contents/MacOS` on macOS. Null when there is none.
  String? get appPath {
    final given = environment['VIDCTRL_APP'];
    if (given != null && given.isNotEmpty) return given;
    final dir = p.dirname(clientExecutable);
    switch (os) {
      case 'macos':
        final contents = p.dirname(dir);
        final bundle = p.dirname(contents);
        if (p.basename(dir) != 'MacOS' ||
            p.basename(contents) != 'Contents' ||
            p.extension(bundle) != '.app' ||
            !Directory(bundle).existsSync()) {
          return null;
        }
        return bundle;
      case 'windows':
        return _ifFile(p.join(dir, 'vidctrl.exe'));
      default:
        return _ifFile(p.join(dir, 'vidctrl'));
    }
  }

  static String? _ifFile(String path) => File(path).existsSync() ? path : null;

  /// Starts the window on its own, to outlive the client. Throws
  /// [ControlErrorKind.notRunning] when there is nothing to start.
  Future<void> start() async {
    final app = appPath;
    if (app == null) {
      throw const ControlError(
        ControlErrorKind.notRunning,
        'VidCtrl was not found next to vidctrl-client; start it, or set '
        'VIDCTRL_APP.',
      );
    }
    if (FileSystemEntity.typeSync(app) == FileSystemEntityType.notFound) {
      throw ControlError(
        ControlErrorKind.notRunning,
        'VIDCTRL_APP names $app, where there is no VidCtrl.',
      );
    }
    try {
      if (os == 'macos') {
        // As a Finder launch: its own process, the Dock icon, one window.
        final result = await Process.run('open', [app]);
        if (result.exitCode != 0) {
          throw ProcessException('open', [app], '${result.stderr}'.trim());
        }
      } else {
        await Process.start(app, const [], mode: ProcessStartMode.detached);
      }
    } on ProcessException catch (e) {
      throw ControlError(
        ControlErrorKind.notRunning,
        'VidCtrl could not be started from $app: ${e.message}',
      );
    }
  }
}
