import 'dart:async';

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
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: defaultWindowSize,
      minimumSize: minimumWindowSize,
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
    container.read(controlProvider.notifier).start().catchError((Object _) {}),
  );
}
