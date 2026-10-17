import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/licenses.dart';
import 'package:vidctrl/app/home/technical_text.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/locator.dart';
import 'package:vidctrl/core/settings/settings_store.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';

final _ffmpeg81 = Capabilities(
  ffmpegVersion: 'n8.1.3-9-g29e619e767-20260930',
  encoders: softwareOnly.encoders,
  svtAv1Params: 'tune=0',
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('About VidCtrl'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the menu says the built-in engine is in use, and its version', (
    tester,
  ) async {
    await pumpApp(tester, FakeEnvironment(capabilities: _ffmpeg81));
    await _openMenu(tester);

    expect(find.text('Video engine: built in'), findsOneWidget);
    expect(find.widgetWithText(TechnicalText, 'FFmpeg 8.1.3'), findsOneWidget);
    expect(find.text('Use FFmpeg from a folder…'), findsOneWidget);
    // Nothing to go back to.
    expect(find.text('Use the built-in FFmpeg'), findsNothing);
  });

  testWidgets('with a chosen folder, the menu names it and offers the way '
      'back', (tester) async {
    final settings = MemorySettingsStore()
      ..write('ffmpegFolder', '/home/user/ffmpeg-9');
    await pumpApp(
      tester,
      FakeEnvironment(
        capabilities: _ffmpeg81,
        ffmpegPaths: const FfmpegPaths(
          ffmpeg: '/home/user/ffmpeg-9/ffmpeg',
          ffprobe: '/home/user/ffmpeg-9/ffprobe',
          source: FfmpegSource.chosen,
        ),
      ),
      settings: settings,
    );
    await _openMenu(tester);

    expect(find.text('Video engine: your own'), findsOneWidget);
    expect(
      find.widgetWithText(TechnicalText, 'FFmpeg 8.1.3 · /home/user/ffmpeg-9'),
      findsOneWidget,
    );

    await tester.tap(find.text('Use the built-in FFmpeg'));
    await tester.pumpAndSettle();

    // Taken at the next start, and said so.
    expect(settings.read('ffmpegFolder'), isNull);
    expect(
      find.text('VidCtrl will use it from its next start.'),
      findsOneWidget,
    );
  });

  testWidgets('the menu names the computer\'s own FFmpeg as such', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeEnvironment(
        capabilities: _ffmpeg81,
        ffmpegPaths: const FfmpegPaths(
          ffmpeg: '/usr/bin/ffmpeg',
          ffprobe: '/usr/bin/ffprobe',
          source: FfmpegSource.system,
        ),
      ),
    );
    await _openMenu(tester);

    expect(find.text("Video engine: the computer's"), findsOneWidget);
    expect(
      find.widgetWithText(TechnicalText, 'FFmpeg 8.1.3 · /usr/bin'),
      findsOneWidget,
    );
  });

  testWidgets('the menu has the website', (tester) async {
    await pumpApp(tester, FakeEnvironment(capabilities: _ffmpeg81));
    await _openMenu(tester);

    // Not tapped: that would open the browser.
    expect(find.text('Website'), findsOneWidget);
  });

  group('the version', () {
    const release = BuildInfo(version: '0.3.0', repository: 'owner/vidctrl');

    Future<FakeReleaseSource> openUpdateCheck(WidgetTester tester) async {
      final releases = FakeReleaseSource();
      await pumpApp(
        tester,
        FakeEnvironment(build: release, releases: releases),
      );
      await _openMenu(tester);
      await tester.tap(find.text('Check for updates…'));
      await tester.pump();
      await tester.pump();
      return releases;
    }

    testWidgets('a release names its version, and can look for a newer one', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeEnvironment(build: release, releases: FakeReleaseSource()),
      );
      await _openMenu(tester);

      expect(find.text('VidCtrl 0.3.0'), findsOneWidget);
      expect(find.text('Check for updates…'), findsOneWidget);
    });

    testWidgets('a development build says so, and does not look for updates', (
      tester,
    ) async {
      await pumpApp(tester, FakeEnvironment());
      await _openMenu(tester);

      expect(find.text('VidCtrl, development build'), findsOneWidget);
      expect(find.text('Check for updates…'), findsNothing);
    });

    testWidgets('a newer release is offered for download', (tester) async {
      final releases = await openUpdateCheck(tester);
      expect(find.text('Looking for a new version…'), findsOneWidget);

      releases.answer('0.4.0');
      await tester.pump();

      expect(find.text('A new version is out'), findsOneWidget);
      expect(
        find.text('VidCtrl 0.4.0 is available. You have 0.3.0.'),
        findsOneWidget,
      );
      // Not tapped: that would open the browser.
      expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    });

    testWidgets('the same version is up to date', (tester) async {
      final releases = await openUpdateCheck(tester);
      releases.answer('0.3.0');
      await tester.pump();

      expect(find.text('VidCtrl is up to date'), findsOneWidget);
      expect(find.text('0.3.0 is the newest version.'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('a check that cannot be made says so', (tester) async {
      final releases = await openUpdateCheck(tester);
      releases.fail();
      await tester.pump();

      expect(find.text('Could not check for updates'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Could not check for updates'), findsNothing);
    });
  });

  testWidgets('the licences include FFmpeg\'s', (tester) async {
    registerLicenses();
    addTearDown(LicenseRegistry.reset);
    await pumpApp(tester, FakeEnvironment());
    await _openMenu(tester);

    await tester.tap(find.text('Licences'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Roboto'), findsOneWidget);
    await tester.tap(find.text('FFmpeg').first);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    // Where this FFmpeg and its source come from, then the GPL itself.
    expect(find.textContaining('unmodified builds of FFmpeg'), findsOneWidget);
    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsWidgets);
  });
}
