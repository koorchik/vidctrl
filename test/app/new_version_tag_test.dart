import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/home/widgets/new_version_tag.dart';
import 'package:vidctrl/app/theme.dart';
import 'package:vidctrl/app/window.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

void main() {
  const release = BuildInfo(version: '0.3.0', repository: 'owner/vidctrl');

  // Real widths, for the test of what fits.
  setUpAll(loadRealFonts);

  /// A released app started, with [releases] answering its question.
  Future<FakeReleaseSource> start(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = defaultWindowSize,
    Look? look,
  }) async {
    final releases = FakeReleaseSource();
    await pumpApp(
      tester,
      FakeEnvironment(build: release, releases: releases),
      locale: locale,
      size: size,
      look: look,
    );
    return releases;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a newer release is shown beside the website, unasked', (
    tester,
  ) async {
    final releases = await start(tester);
    expect(releases.asked, 1);
    expect(find.text('New version 0.4.0'), findsNothing);

    releases.answer('0.4.0');
    await settle(tester);

    expect(find.text('New version 0.4.0'), findsOneWidget);
  });

  testWidgets('the tag leads to the download', (tester) async {
    final releases = await start(tester);
    releases.answer('0.4.0');
    await settle(tester);

    await tester.tap(find.text('New version 0.4.0'));
    await tester.pumpAndSettle();

    expect(find.text('A new version is out'), findsOneWidget);
    expect(
      find.text('VidCtrl 0.4.0 is available. You have 0.3.0.'),
      findsOneWidget,
    );
    // Not tapped: that would open the browser.
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    // What was found is shown; GitHub is not asked again.
    expect(releases.asked, 1);
  });

  testWidgets('nothing is shown while this version is the newest', (
    tester,
  ) async {
    final releases = await start(tester);
    releases.answer('0.3.0');
    await settle(tester);

    expect(find.textContaining('New version'), findsNothing);
  });

  testWidgets('a check that fails, with no connection, shows nothing', (
    tester,
  ) async {
    final releases = await start(tester);
    releases.fail();
    await settle(tester);

    expect(find.textContaining('New version'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a development build does not look', (tester) async {
    final releases = FakeReleaseSource();
    await pumpApp(tester, FakeEnvironment(releases: releases));

    expect(releases.asked, 0);
  });

  testWidgets('in Ukrainian', (tester) async {
    final releases = await start(tester, locale: const Locale('uk'));
    releases.answer('0.4.0');
    await settle(tester);

    expect(find.text('Нова версія 0.4.0'), findsOneWidget);
  });

  for (final look in Look.values) {
    testWidgets('the tag fits the smallest window (${look.name})', (
      tester,
    ) async {
      final releases = await start(
        tester,
        locale: const Locale('uk'),
        size: minimumWindowSize,
        look: look,
      );
      // A long pre-release name, the widest a tag gets.
      releases.answer('10.10.10-beta.10');
      await settle(tester);

      final tag = tester.getRect(find.byType(NewVersionTag));
      // The first of the header's buttons.
      final agent = tester.getRect(find.byTooltip('Робота з ШІ-агентом'));
      expect(tag.right, lessThan(agent.left));
      expect(tester.takeException(), isNull);
    });
  }
}
