import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/technical_text.dart';
import 'package:vidctrl/app/home/widgets/archive_quality_dialog.dart';
import 'package:vidctrl/app/home/widgets/busy_mark.dart';
import 'package:vidctrl/app/home/widgets/quality_report.dart';
import 'package:vidctrl/app/window.dart';
import 'package:vidctrl/core/quality/quality_search.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';
import 'home_screen_test.dart' show expectNoJargon;

/// The quality the archive chooses for each video, as people see it: in the
/// video list before converting, in the queue, and in the (i) window.
void main() {
  late FakeEnvironment env;

  // What fits on a line depends on the fonts the app ships.
  setUpAll(loadRealFonts);

  setUp(() {
    env = FakeEnvironment();
    env.ffprobe.add('/videos/holiday.mp4');
    env.ffprobe.add('/videos/film.mkv');
  });

  // A running job's progress bar animates forever: fixed times, not
  // "until settled".
  Future<void> wait(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  Future<void> addHoliday(WidgetTester tester, {Locale? locale}) async {
    final sources = await pumpApp(
      tester,
      env,
      locale: locale ?? const Locale('en'),
    );
    await addVideos(tester, sources, ['/videos/holiday.mp4']);
    await tester.pump();
  }

  Future<void> addToQueue(WidgetTester tester) async {
    await tapAddToQueue(tester);
    await tester.pump();
    await tester.pump();
  }

  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.byTooltip("About this video's quality").first);
    await tester.pump();
    await wait(tester);
  }

  group('in the video list', () {
    testWidgets('a raised quality says so, with the numbers as detail', (
      tester,
    ) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.raised,
      );
      await addHoliday(tester);

      expect(find.text('Quality raised to look the same'), findsOneWidget);
      expect(
        find.widgetWithText(
          TechnicalText,
          'CRF 35 → 26  ·  VMAF 95.3  ·  XPSNR 40.3 dB',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Will be converted  → about'), findsOneWidget);
    });

    testWidgets('one that falls short asks for a look by eye', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester);

      expect(
        find.text('Check by eye before deleting the original'),
        findsOneWidget,
      );
      expect(find.byTooltip("About this video's quality"), findsOneWidget);
    });

    testWidgets('one not worth converting will stay as it is', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.notWorthIt,
      );
      await addHoliday(tester);

      expect(find.text('Will stay as it is'), findsOneWidget);
      expect(find.text('Converting would save only 10%'), findsOneWidget);
      expect(find.textContaining('Will be converted'), findsNothing);
    });

    testWidgets('a look for a better quality shows while it goes on', (
      tester,
    ) async {
      env.estimator
        ..choices['/videos/holiday.mp4'] = fakeChoice(QualityOutcome.raised)
        ..hold = true;
      await addHoliday(tester);

      // In the video's line and in the panel's summary, each with a spinner.
      expect(find.textContaining('choosing the quality…'), findsNWidgets(2));
      expect(find.byType(BusyMark), findsNWidgets(2));
    });

    testWidgets('a spinner shows while it is measured, and goes', (
      tester,
    ) async {
      env.estimator.hold = true;
      await addHoliday(tester);

      // In the video's line and in the panel's summary.
      expect(find.byType(BusyMark), findsNWidgets(2));
      expect(
        find.textContaining('measuring size and quality…'),
        findsNWidgets(2),
      );

      env.estimator.release();
      await tester.pump();
      await tester.pump();

      expect(find.byType(BusyMark), findsNothing);
    });

    testWidgets('one that looks the same needs no (i)', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.standard,
      );
      await addHoliday(tester);

      expect(find.text('Looks the same as the original'), findsOneWidget);
      expect(find.byTooltip("About this video's quality"), findsNothing);
    });
  });

  group('the tag of a tuned quality', () {
    for (final (outcome, shown) in [
      (QualityOutcome.standard, false),
      (QualityOutcome.raised, true),
      (QualityOutcome.belowTarget, true),
      (QualityOutcome.notWorthIt, false),
    ]) {
      testWidgets('${shown ? 'marks' : 'does not mark'} '
          'a video ${outcome.name}', (tester) async {
        env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(outcome);
        await addHoliday(tester);

        expect(
          find.text('Quality tuned'),
          shown ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('stays with the job in the queue, and after', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.raised,
      );
      await addHoliday(tester);
      await addToQueue(tester);

      // In the video list and on the job.
      expect(find.text('Quality tuned'), findsNWidgets(2));

      env.executor.last.finish();
      await tester.pump();

      expect(find.text('Quality tuned'), findsNWidgets(2));
    });

    testWidgets('opens the story of the quality chosen', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.raised,
      );
      await addHoliday(tester);

      await tester.tap(find.text('Quality tuned'));
      await tester.pump();
      await wait(tester);

      expect(find.text('Quality raised for this video'), findsOneWidget);
    });
  });

  group('the (i) window', () {
    testWidgets('shows the hardest frame of the original and the copy', (
      tester,
    ) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester);

      await openDetails(tester);

      expect(find.text('Check this video by eye'), findsOneWidget);
      // 40 frames into the piece at 2:23, at 25 frames a second.
      expect(find.text('The hardest frame checked, at 2:24'), findsOneWidget);
      // Before converting, from the piece encoded while measuring.
      expect(env.frames.grabbed, [
        ('/videos/holiday.mp4', const Duration(minutes: 2, seconds: 23), 40),
        ('/tmp/vidctrl_estimates/sample_20.mp4', Duration.zero, 40),
      ]);
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('Result'), findsNWidgets(2));
    });

    testWidgets('switches between the original and the copy', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester);
      await openDetails(tester);

      await tester.tap(find.text('Original').first);
      await tester.pump();

      // The label over the picture says which one shows.
      expect(find.text('Original'), findsNWidgets(2));
      final shown = tester.widgetList<Offstage>(
        find.descendant(
          of: find.byType(FrameCompare),
          matching: find.byType(Offstage),
        ),
      );
      expect([for (final o in shown) o.offstage], [false, true]);
    });

    testWidgets('holding Space shows the original', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester);
      await openDetails(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Original'), findsNWidgets(2));

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Result'), findsNWidgets(2));
    });

    testWidgets('the frames are read once, however the window changes', (
      tester,
    ) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester);
      await openDetails(tester);
      expect(env.frames.grabbed, hasLength(2));

      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      await tester.pump();
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pump();

      expect(env.frames.grabbed, hasLength(2));
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('frames that cannot be read are said so', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      env.frames.fail = true;
      await addHoliday(tester);

      await openDetails(tester);

      expect(find.textContaining('could not be read'), findsOneWidget);
    });

    testWidgets('a raised quality is explained without frames', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.raised,
      );
      await addHoliday(tester);

      await openDetails(tester);

      expect(find.text('Quality raised for this video'), findsOneWidget);
      // Each quality tried, the chosen one marked.
      expect(
        find.widgetWithText(
          TechnicalText,
          'CRF 26  ·  VMAF 95.3  ·  XPSNR 40.3 dB  ·  '
          "35% of the original's size  ·  ← chosen",
        ),
        findsOneWidget,
      );
      expect(env.frames.grabbed, isEmpty);
    });

    testWidgets('a video left as it is says why', (tester) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.notWorthIt,
      );
      await addHoliday(tester);

      await openDetails(tester);

      expect(find.text('Why this video stays as it is'), findsOneWidget);
      expect(find.textContaining('keep 90% of its size'), findsOneWidget);
    });
  });

  group('in the queue', () {
    testWidgets('a job says it checks, then chooses the quality', (
      tester,
    ) async {
      env.estimator
        ..choices['/videos/holiday.mp4'] = fakeChoice(QualityOutcome.raised)
        ..hold = true;
      await addHoliday(tester);
      await addToQueue(tester);

      // The list's measuring was stopped; the job measures, at its third
      // try: the second better quality.
      expect(find.text('Choosing the quality… try 2'), findsOneWidget);

      env.estimator.release();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('_av1-crf26.mp4'), findsOneWidget);
      expect(find.text('Quality raised to look the same'), findsWidgets);
    });

    testWidgets('a video left as it is can be converted anyway', (
      tester,
    ) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.notWorthIt,
      );
      await addHoliday(tester);
      await addToQueue(tester);

      expect(find.text('Left as it is'), findsOneWidget);
      expect(env.executor.started, isEmpty);

      await tester.tap(find.byTooltip('More').last);
      await tester.pump();
      await wait(tester);
      await tester.tap(find.text('Convert anyway'));
      await tester.pump();
      await wait(tester);

      expect(env.executor.started, hasLength(1));
    });

    testWidgets('a finished video to look at is marked, and counted', (
      tester,
    ) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester);
      await addToQueue(tester);
      env.executor.last.finish();
      await tester.pump();

      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
      expect(find.textContaining('check by eye: 1'), findsOneWidget);

      // Its frame now comes from the converted file.
      await tester.tap(find.byTooltip("About this video's quality").last);
      await tester.pump();
      await wait(tester);
      final (path, seek, frame) = env.frames.grabbed.last;
      expect(path, endsWith('holiday_av1-crf20-check.mp4'));
      expect(seek, const Duration(minutes: 2, seconds: 23));
      expect(frame, 40);
    });
  });

  for (final locale in const [Locale('en'), Locale('uk')]) {
    testWidgets('every verdict fits the smallest window '
        '(${locale.languageCode})', (tester) async {
      final outcomes = {
        '/videos/a.mp4': QualityOutcome.standard,
        '/videos/b.mp4': QualityOutcome.raised,
        '/videos/c.mp4': QualityOutcome.belowTarget,
        '/videos/d.mp4': QualityOutcome.notWorthIt,
      };
      for (final MapEntry(key: path, value: outcome) in outcomes.entries) {
        env.ffprobe.add(path);
        env.estimator.choices[path] = fakeChoice(outcome);
      }
      final sources = await pumpApp(
        tester,
        env,
        locale: locale,
        size: minimumWindowSize,
      );
      await addVideos(tester, sources, outcomes.keys);
      await tester.pump();
      await addToQueue(tester);
      env.executor.last.finish();
      await tester.pump();
      await tester.pump();

      // A line that does not fit throws while it is laid out.
      expect(tester.takeException(), isNull);
      expect(find.byType(QualityChoiceLine), findsWidgets);
    });

    testWidgets('how the archive keeps the quality opens from the smallest '
        'window, with a graphics card too (${locale.languageCode})', (
      tester,
    ) async {
      for (final capabilities in [
        softwareOnly,
        withGpu({'av1_nvenc'}),
      ]) {
        await tester.pumpWidget(const SizedBox());
        await pumpApp(
          tester,
          FakeEnvironment(capabilities: capabilities),
          locale: locale,
          size: minimumWindowSize,
        );

        await tester.tap(find.byIcon(Icons.help_outline_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(ArchiveQualityDialog), findsOneWidget);
      }
    });

    testWidgets('the numbers stay secondary detail (${locale.languageCode})', (
      tester,
    ) async {
      env.estimator.choices['/videos/holiday.mp4'] = fakeChoice(
        QualityOutcome.belowTarget,
      );
      await addHoliday(tester, locale: locale);
      await addToQueue(tester);

      expectNoJargon(
        plainTexts(tester)..removeWhere((t) => t.startsWith('holiday.')),
      );

      await tester.tap(find.byType(QualityDetailsButton).first);
      await tester.pump();
      await wait(tester);
      expectNoJargon(
        plainTexts(tester)..removeWhere((t) => t.startsWith('holiday.')),
      );
    });
  }
}
