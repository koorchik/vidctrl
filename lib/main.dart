import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
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

  runApp(
    ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
      child: const VideoConverterApp(
        home: WindowCloseGuard(child: HomeScreen()),
      ),
    ),
  );
}
