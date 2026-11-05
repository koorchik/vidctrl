import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/quality/quality_search.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';

/// "Show the command" for a video in the list: the command the panel's
/// settings would run, and why there is none where none runs.
void main() {
  late FakeEnvironment env;

  setUpAll(loadRealFonts);

  setUp(() => env = FakeEnvironment());

  const intro =
      'This is what the app runs for this video. Copy it to run it '
      'yourself in a terminal, or to adjust it.';

  Future<void> addVideo(WidgetTester tester, String path) async {
    final sources = await pumpApp(tester, env);
    await addVideos(tester, sources, [path]);
    await tester.pump();
  }

  Future<void> showCommand(WidgetTester tester) async {
    await tester.tap(find.text('Show the command'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The command as the window shows it, or null without one. Without the
  /// quotes, which differ by terminal: PowerShell's on Windows quote every
  /// option.
  String? shownCommand(WidgetTester tester) {
    final command = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(SelectableText),
    );
    if (command.evaluate().isEmpty) return null;
    return tester.widget<SelectableText>(command).data!.replaceAll("'", '');
  }

  testWidgets('shows the command for a video to convert', (tester) async {
    env.ffprobe.add('/videos/holiday.mp4');
    await addVideo(tester, '/videos/holiday.mp4');

    await showCommand(tester);

    expect(find.text(intro), findsOneWidget);
    expect(shownCommand(tester), contains('libsvtav1'));
  });

  testWidgets('a video already right says that nothing runs', (tester) async {
    env.ffprobe.add(
      '/videos/nikon.mov',
      like: clip(video: 'hevc', audio: [track('pcm_s24le')]),
    );
    await addVideo(tester, '/videos/nikon.mov');
    await tester.tap(find.text('Edit in DaVinci Resolve'));
    await tester.pump();

    await showCommand(tester);

    expect(
      find.text(
        'This video is already right for this goal, so nothing runs: it '
        'stays as it is.',
      ),
      findsOneWidget,
    );
    expect(find.text(intro), findsNothing);
    expect(shownCommand(tester), isNull);
  });

  testWidgets('a file the goal cannot use says why nothing runs', (
    tester,
  ) async {
    env.ffprobe.add('/videos/voice.m4a', like: clip(video: null));
    await addVideo(tester, '/videos/voice.m4a');

    await showCommand(tester);

    expect(
      find.text('No picture in this file, so nothing runs for it.'),
      findsOneWidget,
    );
    expect(shownCommand(tester), isNull);
  });

  testWidgets(
    'a video not worth converting shows what "Convert anyway" would run',
    (tester) async {
      env.ffprobe.add('/videos/holiday.mp4');
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.notWorthIt,
      );
      await addVideo(tester, '/videos/holiday.mp4');

      await showCommand(tester);

      expect(
        find.text(
          'This video stays as it is: converting would save only 10%. '
          '“Convert anyway” in the queue runs this command.',
        ),
        findsOneWidget,
      );
      expect(find.text(intro), findsNothing);
      expect(shownCommand(tester), contains('-crf 35'));
    },
  );

  testWidgets('the video list menu explains it the same way', (tester) async {
    env.ffprobe.add('/videos/voice.m4a', like: clip(video: null));
    await addVideo(tester, '/videos/voice.m4a');

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Show the command').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('No picture in this file, so nothing runs for it.'),
      findsOneWidget,
    );
  });
}
