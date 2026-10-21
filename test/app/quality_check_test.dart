import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/technical_text.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  late FakeEnvironment env;

  setUp(() {
    env = FakeEnvironment();
    env.ffprobe.add('/videos/holiday.mp4');
  });

  // A running job's progress bar animates forever, so menus are given a
  // fixed time to open and close instead of "until settled".
  Future<void> wait(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  Future<void> addToQueue(WidgetTester tester, {Locale? locale}) async {
    final sources = await pumpApp(
      tester,
      env,
      locale: locale ?? const Locale('en'),
    );
    await addVideos(tester, sources, ['/videos/holiday.mp4']);
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    await tester.pump();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More').last);
    await tester.pump();
    await wait(tester);
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tapAt(Offset.zero);
    await tester.pump();
    await wait(tester);
  }

  /// One video converted, and its comparison asked for.
  Future<FakeComparison> compare(WidgetTester tester) async {
    await addToQueue(tester);
    env.executor.last.finish();
    await tester.pump();
    await openMenu(tester);
    await tester.tap(find.text('Compare with the original'));
    await tester.pump();
    await wait(tester);
    return env.qualityMeter.last;
  }

  testWidgets('a result can be compared once its conversion is done', (
    tester,
  ) async {
    await addToQueue(tester);

    await openMenu(tester);
    expect(find.text('Compare with the original'), findsNothing);
    await closeMenu(tester);

    env.executor.last.finish();
    await tester.pump();
    await openMenu(tester);
    expect(find.text('Compare with the original'), findsOneWidget);
  });

  testWidgets('the comparison shows how far it has got', (tester) async {
    final comparison = await compare(tester);

    comparison.report(0.35);
    await tester.pump();

    expect(find.text('Comparing with the original… 35%'), findsOneWidget);
    expect(find.byTooltip('Stop comparing'), findsOneWidget);
  });

  testWidgets('the result says in words how close it is, and the score', (
    tester,
  ) async {
    final comparison = await compare(tester);

    comparison.finish(40.6);
    await tester.pump();

    expect(find.text('Very close to the original'), findsOneWidget);
    expect(find.widgetWithText(TechnicalText, 'XPSNR 40.6 dB'), findsOneWidget);
    expect(find.textContaining('Comparing'), findsNothing);
  });

  testWidgets('with VMAF the verdict follows VMAF, and both scores show', (
    tester,
  ) async {
    final comparison = await compare(tester);

    // A grainy 4K clip: below the XPSNR target, and nothing to see.
    comparison.finish(40.6, vmaf: 96.0);
    await tester.pump();

    expect(find.text('Looks the same as the original'), findsOneWidget);
    expect(
      find.widgetWithText(TechnicalText, 'VMAF 96.0  ·  XPSNR 40.6 dB'),
      findsOneWidget,
    );
  });

  for (final (score, words) in [
    (45.1, 'Looks the same as the original'),
    (38.7, 'Differences may be visible'),
    (double.infinity, 'Looks the same as the original'),
  ]) {
    testWidgets('$score dB reads "$words"', (tester) async {
      final comparison = await compare(tester);

      comparison.finish(score);
      await tester.pump();

      expect(find.text(words), findsOneWidget);
    });
  }

  testWidgets('a comparison can be stopped', (tester) async {
    final comparison = await compare(tester);

    await tester.tap(find.byTooltip('Stop comparing'));
    await tester.pump();

    expect(comparison.cancelRequested, isTrue);
    expect(find.textContaining('Comparing'), findsNothing);
  });

  testWidgets('a comparison that fails says so', (tester) async {
    final comparison = await compare(tester);

    comparison.fail();
    await tester.pump();

    expect(find.text('Could not compare'), findsOneWidget);
  });

  testWidgets('the score is shown the Ukrainian way in Ukrainian', (
    tester,
  ) async {
    await addToQueue(tester, locale: const Locale('uk'));
    env.executor.last.finish();
    await tester.pump();
    await tester.tap(find.byTooltip('Більше').last);
    await tester.pump();
    await wait(tester);
    await tester.tap(find.text('Порівняти з оригіналом'));
    await tester.pump();

    env.qualityMeter.last.finish(40.6);
    await tester.pump();

    expect(find.text('Майже як оригінал'), findsOneWidget);
    expect(find.widgetWithText(TechnicalText, 'XPSNR 40,6 дБ'), findsOneWidget);
  });
}
