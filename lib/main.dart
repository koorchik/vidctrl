import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/control/control_controller.dart';
import 'app/home/home_screen.dart';
import 'app/licenses.dart';
import 'app/settings.dart';
import 'app/window.dart';
import 'app/window_close_guard.dart';
import 'core/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLicenses();
  await windowManager.ensureInitialized();
  // The sizes are what the app has inside the window; without the frame
  // added the smallest window was smaller than the panel is made for.
  final frame = await _windowFrame();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: defaultWindowSize + frame,
      minimumSize: minimumWindowSize + frame,
      center: true,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final settings = await FileSettingsStore.open(
    p.join((await getApplicationSupportDirectory()).path, 'settings.json'),
  );

  final container = ProviderContainer(
    overrides: [settingsStoreProvider.overrideWithValue(settings)],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const VideoConverterApp(
        home: WindowCloseGuard(child: HomeScreen()),
      ),
    ),
  );
  // Lets `vidctrl-client` control this window. A window that cannot serve
  // (no folder to write to) still works for its user.
  unawaited(
    container
        .read(controlProvider.notifier)
        .start()
        .catchError(
          (Object error) =>
              debugPrint('The control server did not start: $error'),
        ),
  );
}

/// What the system counts in a window's size beyond what the app has
/// inside: on macOS the title bar, on Windows the title bar and the borders.
/// GTK counts neither.
Future<Offset> _windowFrame() async {
  if (Platform.isMacOS) {
    return Offset(0, (await windowManager.getTitleBarHeight()) * 1.0);
  }
  if (!Platform.isWindows) return Offset.zero;
  // Windows has the borders' width only as the difference, taken while the
  // window is still the size the runner made it, inside and out.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (view.devicePixelRatio <= 0 || view.physicalSize.isEmpty) {
    return Offset.zero;
  }
  final inside = view.physicalSize / view.devicePixelRatio;
  final outside = await windowManager.getSize();
  final frame = Offset(
    outside.width - inside.width,
    outside.height - inside.height,
  );
  // A size from before the window was laid out would be no frame at all.
  final plausible =
      frame.dx >= 0 && frame.dx < 100 && frame.dy >= 0 && frame.dy < 150;
  return plausible ? frame : Offset.zero;
}
