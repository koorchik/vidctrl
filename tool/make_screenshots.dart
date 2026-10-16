// Draws the pictures of the app that the README shows, one for each look,
// into docs/screenshots/. The files it writes are committed; run it again
// after the screen changes:
//
//   flutter test tool/make_screenshots.dart
//
// The app draws itself, with stand-ins for FFmpeg and for the video files,
// so no footage and no real conversion is needed. It goes through
// `flutter test` because that is what can draw the app without a window.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/widgets/recipe_pane.dart';
import 'package:vidctrl/app/queue/queue_controller.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/app/recipe/recipe_controller.dart';
import 'package:vidctrl/app/theme.dart';
import 'package:vidctrl/core/media/ffprobe.dart';

import '../test/support/fake_media.dart';
import '../test/support/fakes.dart';
import '../test/support/pump_app.dart';

const _folder = 'docs/screenshots';

const _videos = [
  '/videos/DSC_0412.MOV',
  '/videos/DSC_0413.MOV',
  '/videos/Z5_0007.MOV',
  '/videos/birthday final export.mov',
];

void main() {
  setUpAll(loadRealFonts);

  for (final look in Look.values) {
    testWidgets('the main screen, ${look.name}', (tester) async {
      // Laid out as on a desktop: tests otherwise space things for a phone.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      final env = FakeEnvironment(capabilities: withGpu({'av1_nvenc'}));
      env.ffprobe.add(_videos[0]);
      env.ffprobe.add(
        _videos[1],
        like: clip(duration: const Duration(minutes: 4, seconds: 12)),
      );
      env.ffprobe.add(
        _videos[2],
        like: clip(video: 'hevc', audio: [track('pcm_s24le')]),
      );
      env.ffprobe.add(
        _videos[3],
        like: parseFfprobeJson(
          _videos[3],
          jsonDecode(
            File('test/fixtures/hlg_clip_ffprobe.json').readAsStringSync(),
          ) as Map<String, dynamic>,
        ),
      );

      final sources = await pumpApp(tester, env, look: look);
      await addVideos(tester, sources, _videos);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipePane)),
      );
      final recipe = container.read(recipeProvider.notifier);
      final queue = container.read(queueProvider.notifier);

      // The state is set through the controllers rather than by clicking, so
      // nothing is left looking hovered or pressed.
      //
      // A finished sample of the first video...
      sources.select(0);
      recipe.setSample(SampleChoice.start);
      await tester.pump();
      queue.addSelected();
      await tester.pump();
      await tester.pump();
      env.executor.last.finish(
        bytes: 2600000,
        elapsed: const Duration(seconds: 6),
      );
      await tester.pump();
      await tester.pump();

      // ...the second video part-way through...
      recipe.setSample(SampleChoice.none);
      sources.select(1);
      await tester.pump();
      queue.addSelected();
      await tester.pump();
      await tester.pump();
      env.executor.last.report(0.42);
      await tester.pump();

      // ...the third waiting, and the last two selected.
      sources.select(2);
      await tester.pump();
      queue.addSelected();
      await tester.pump();
      sources.toggle(3);
      await tester.pump();

      await saveScreenshot(tester, look.name, folder: _folder, pixelRatio: 2);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
