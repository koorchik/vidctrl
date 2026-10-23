import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/app.dart';
import 'package:vidctrl/app/control/agent_prompt.dart';
import 'package:vidctrl/app/home/widgets/agent_dialog.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/theme.dart';
import 'package:vidctrl/app/window.dart';
import 'package:vidctrl/core/control/words.dart';
import 'package:vidctrl/l10n/app_localizations.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

const _client = '/opt/vidctrl/vidctrl-client';

/// What the app copies, caught on its way to the system's clipboard.
List<String> _catchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  return copied;
}

Future<void> _openFromHeader(WidgetTester tester, {String? tooltip}) async {
  await tester.tap(find.byTooltip(tooltip ?? 'Use with an AI agent'));
  await tester.pumpAndSettle();
}

void main() {
  group('the prompt', () {
    test('names the program, the manual, waiting and the rule about files', () {
      final text = agentPrompt(
        clientPath: _client,
        languageName: 'English',
        os: 'linux',
      );
      expect(text, contains("'$_client' manual"));
      expect(text, contains("'$_client' wait"));
      expect(text, contains(filesRule));
      expect(text, isNot(contains('Answer me')));
      expect(speaksOfDeleting(text), isFalse);
    });

    test('in Ukrainian the agent is asked to answer in Ukrainian', () {
      final text = agentPrompt(
        clientPath: _client,
        languageName: 'Ukrainian',
        os: 'linux',
      );
      expect(text.trimRight(), endsWith('Answer me in Ukrainian.'));
      expect(speaksOfDeleting(text), isFalse);
    });

    test('on Windows the program is called as PowerShell needs it', () {
      final text = agentPrompt(
        clientPath: r'C:\Apps\VidCtrl\vidctrl-client.exe',
        languageName: 'English',
        os: 'windows',
      );
      expect(
        text,
        contains(r'`& "C:\Apps\VidCtrl\vidctrl-client.exe" manual`'),
      );
    });

    test('the README shows the same prompt', () {
      final readme = File('README.md').readAsStringSync();
      final prompt = agentPrompt(
        clientPath: '/home/alice/Apps/vidctrl/vidctrl-client',
        languageName: 'English',
        os: 'linux',
      );
      expect(readme, contains('```text\n$prompt```'));
    });
  });

  test('the program is found beside the app, or reported missing', () {
    final there = <String>{
      '/opt/vidctrl/vidctrl-client',
      r'C:\Apps\VidCtrl\vidctrl-client.exe',
      '/Applications/VidCtrl.app/Contents/MacOS/vidctrl-client',
    };
    String? beside(String app, String os) =>
        clientExecutable(appExecutable: app, os: os, exists: there.contains);

    expect(
      beside('/opt/vidctrl/vidctrl', 'linux'),
      '/opt/vidctrl/vidctrl-client',
    );
    expect(
      beside(r'C:\Apps\VidCtrl\vidctrl.exe', 'windows'),
      r'C:\Apps\VidCtrl\vidctrl-client.exe',
    );
    expect(
      beside('/Applications/VidCtrl.app/Contents/MacOS/VidCtrl', 'macos'),
      '/Applications/VidCtrl.app/Contents/MacOS/vidctrl-client',
    );
    expect(beside('/home/alice/build/bundle/vidctrl', 'linux'), isNull);
  });

  testWidgets('the header button opens the window and Copy copies the prompt', (
    tester,
  ) async {
    await pumpApp(tester, FakeEnvironment(clientPath: _client));
    final copied = _catchClipboard(tester);
    await _openFromHeader(tester);

    expect(find.byType(AgentDialog), findsOneWidget);
    expect(
      find.text(
        'Let an AI agent such as Claude add videos and start conversions '
        'for you. You keep watching here.',
      ),
      findsOneWidget,
    );
    expect(find.text('Paste this into your agent'), findsOneWidget);
    expect(find.text('The program the agent uses'), findsOneWidget);
    expect(find.text('Show in folder'), findsOneWidget);
    expect(find.textContaining('Claude Code, Codex'), findsOneWidget);
    expect(find.textContaining('cannot run commands'), findsOneWidget);
    expect(find.textContaining('sandbox'), findsOneWidget);

    await tester.tap(find.text('Copy').first);
    await tester.pump();
    expect(copied, [
      agentPrompt(
        clientPath: _client,
        languageName: 'English',
        os: Platform.operatingSystem,
      ),
    ]);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);

    // The program's own Copy gives its path alone.
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied.last, _client);
  });

  testWidgets('in Ukrainian the window copies a prompt asking for Ukrainian', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeEnvironment(clientPath: _client),
      locale: const Locale('uk'),
    );
    final copied = _catchClipboard(tester);
    await _openFromHeader(tester, tooltip: 'Робота з ШІ-агентом');

    await tester.tap(find.text('Копіювати').first);
    await tester.pump();
    expect(copied.single, endsWith('Answer me in Ukrainian.\n'));
  });

  testWidgets('no button on the engine-missing screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentProvider.overrideWith(
            (ref) async => throw const FfmpegMissing(),
          ),
        ],
        child: const VideoConverterApp(locale: Locale('en')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The video engine is missing'), findsOneWidget);
    expect(find.byTooltip('Use with an AI agent'), findsNothing);
    await tester.tap(find.byTooltip('About VidCtrl'));
    await tester.pumpAndSettle();
    expect(find.text('Use with an AI agent'), findsNothing);
  });

  testWidgets('without the program the window says how to build it and '
      'cannot copy', (tester) async {
    await pumpApp(tester, FakeEnvironment(clientPath: null));
    await _openFromHeader(tester);

    expect(
      find.text(
        'This build has no vidctrl-client beside it. Build it with '
        'tool/build_client.sh.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Run `'), findsNothing);
    expect(find.text('Show in folder'), findsNothing);
    final copy = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Copy'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('the About menu opens the same window', (tester) async {
    await pumpApp(tester, FakeEnvironment(clientPath: _client));
    await tester.tap(find.byTooltip('About VidCtrl'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use with an AI agent'));
    await tester.pumpAndSettle();

    expect(find.byType(AgentDialog), findsOneWidget);
    expect(find.text('Paste this into your agent'), findsOneWidget);
  });

  group('fits the window', () {
    setUpAll(loadRealFonts);

    // The prompt scrolls in its box at the smallest window, where a long
    // path may not leave room for all of it; everything else is in view.
    // From the size the window opens at, the whole prompt shows.
    final cases = [
      for (final look in Look.values)
        for (final locale in const [Locale('en'), Locale('uk')])
          for (final size in const [minimumWindowSize, defaultWindowSize])
            (look: look, locale: locale, size: size),
    ];
    for (final (:look, :locale, :size) in cases) {
      testWidgets('${size.width.round()} x ${size.height.round()}, '
          '${locale.languageCode}, ${look.name}', (tester) async {
        await pumpApp(
          tester,
          FakeEnvironment(
            clientPath: '/home/alice/Apps/vidctrl/vidctrl-client',
          ),
          locale: locale,
          look: look,
          size: size,
        );
        final l10n = lookupAppLocalizations(locale);
        await _openFromHeader(tester, tooltip: l10n.agentTitle);

        expect(tester.takeException(), isNull);
        final window = Offset.zero & size;
        for (final text in [l10n.agentKindSandbox, l10n.close]) {
          expect(
            window.contains(tester.getBottomRight(find.text(text))),
            isTrue,
          );
        }
        final prompt = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(AgentDialog),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        if (size == defaultWindowSize) {
          expect(prompt.position.maxScrollExtent, 0);
        }
      });
    }
  });
}
