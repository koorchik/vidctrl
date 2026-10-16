import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/app.dart';
import 'package:vidctrl/app/home/home_screen.dart';
import 'package:vidctrl/app/home/technical_text.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/settings.dart';
import 'package:vidctrl/core/settings/settings_store.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/app/theme.dart';
import 'package:vidctrl/app/window.dart';

import 'fakes.dart';

const _screenshotKey = ValueKey('screenshot');

/// Starts the app against a [FakeEnvironment] in a window of [size].
Future<SourcesController> pumpApp(
  WidgetTester tester,
  FakeEnvironment env, {
  Locale? locale = const Locale('en'),
  SettingsStore? settings,
  Look? look,
  Size size = defaultWindowSize,
  Widget home = const HomeScreen(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...env.overrides,
      if (settings != null) settingsStoreProvider.overrideWithValue(settings),
    ],
  );
  addTearDown(container.dispose);
  // Chosen the way a user chooses it; null leaves the remembered look, or
  // the one the app starts with.
  if (look != null) await container.read(lookProvider.notifier).select(look);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _screenshotKey,
        child: VideoConverterApp(locale: locale, home: home),
      ),
    ),
  );
  await container.read(environmentProvider.future);
  await tester.pump();
  return container.read(sourcesProvider.notifier);
}

/// Adds files to the list. Checking whether a path is a folder is real disk
/// access, which only completes outside the test's simulated clock.
Future<void> addVideos(
  WidgetTester tester,
  SourcesController sources,
  Iterable<String> paths,
) async {
  await tester.runAsync(() => sources.addPaths(paths));
  await tester.pump();
}

/// Text on screen in the main, plain-language style: everything except the
/// small technical notes beside it.
List<String> plainTexts(WidgetTester tester) {
  final technical = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(TechnicalText),
          matching: find.byType(Text),
        ),
      )
      .toSet();
  return [
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      if (!technical.contains(text))
        text.data ?? text.textSpan?.toPlainText() ?? '',
  ];
}

/// Every piece of text currently on screen.
List<String> visibleTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

/// Loads the fonts the app ships, so text takes the room it really takes and
/// rendered images are readable.
Future<void> loadRealFonts() async {
  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(read('assets/fonts/Roboto-$weight.ttf'));
  }
  await roboto.load();
  final mono = FontLoader('JetBrains Mono')
    ..addFont(read('assets/fonts/JetBrainsMono-Regular.ttf'));
  await mono.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      read(
        p.join(
          Platform.environment['FLUTTER_ROOT']!,
          'bin',
          'cache',
          'artifacts',
          'material_fonts',
          'MaterialIcons-Regular.otf',
        ),
      ),
    );
  await icons.load();
}

/// Saves what is on screen to `<folder>/<name>.png`, by default in
/// `build/screenshots`. A [pixelRatio] of 2 gives an image twice as sharp,
/// for showing to people.
Future<void> saveScreenshot(
  WidgetTester tester,
  String name, {
  String? folder,
  double pixelRatio = 1,
}) async {
  // Lets fades finish (a button going from disabled to enabled, for one), so
  // the image shows the settled state.
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenshotKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      p.join(folder ?? p.join('build', 'screenshots'), '$name.png'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
