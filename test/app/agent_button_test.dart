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
import 'package:vidctrl/core/control/manual.dart';
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

const _folder = '/home/alice/work/vidctrl/build/linux/x64/debug/bundle';

final _en = lookupAppLocalizations(const Locale('en'));
final _uk = lookupAppLocalizations(const Locale('uk'));

void main() {
  group('the prompt', () {
    test('in English it is the quick start the client prints', () {
      for (final (client, os) in [
        (_client, 'linux'),
        (r'C:\Apps\VidCtrl\vidctrl-client.exe', 'windows'),
        ('vidctrl-client', 'windows'),
      ]) {
        expect(
          agentPrompt(_en, clientPath: client, os: os),
          quickStart(client, os: os),
          reason: '$client on $os',
        );
      }
    });

    test('names the program, its manual and --json, in either language, '
        'and nothing about deleting', () {
      for (final l10n in [_en, _uk]) {
        final text = agentPrompt(l10n, clientPath: _client, os: 'linux');
        expect(text, contains("`'$_client'`"));
        expect(text, contains("`'$_client' manual`"));
        expect(text, contains('`--json`'));
        expect(text, isNot(contains('Answer me')));
        expect(speaksOfDeleting(text), isFalse, reason: text);
      }
    });

    test('in Ukrainian it is in Ukrainian', () {
      final text = agentPrompt(_uk, clientPath: _client, os: 'linux');
      expect(
        text,
        startsWith(
          "VidCtrl відкритий на цьому комп'ютері, і людина стежить за його "
          "вікном. Програма `'$_client'` керує ним:",
        ),
      );
      expect(text, contains("- Спершу запусти `'$_client' manual`:"));
    });

    test('on Windows the path is in double quotes, with PowerShell\'s & '
        'said once', () {
      const client = r'C:\Apps\VidCtrl\vidctrl-client.exe';
      final text = agentPrompt(_en, clientPath: client, os: 'windows');
      expect(text, contains('`"$client" manual`'));
      expect(
        text,
        contains(
          '- In PowerShell, put & before a quoted path: '
          '`& "$client" manual`.',
        ),
      );
      expect('&'.allMatches(text), hasLength(2));
      expect(
        agentPrompt(_uk, clientPath: client, os: 'windows'),
        contains(
          '- У PowerShell пиши & перед шляхом у лапках: `& "$client" manual`.',
        ),
      );
      for (final l10n in [_en, _uk]) {
        final text = agentPrompt(l10n, clientPath: client, os: 'windows');
        expect(speaksOfDeleting(text), isFalse, reason: text);
      }
    });

    test('the README shows the English prompt', () {
      final readme = File('README.md').readAsStringSync();
      final prompt = agentPrompt(
        _en,
        clientPath: '/home/alice/Apps/vidctrl/vidctrl-client',
        os: 'linux',
      );
      expect(readme, contains('```text\n$prompt```'));
    });
  });

  test('the command that builds the client names the app\'s folder', () {
    expect(
      buildClientCommand(_folder, os: 'linux'),
      "tool/build_client.sh '$_folder'",
    );
    expect(
      buildClientCommand(
        r'C:\Users\alice\vidctrl\build\windows\x64\runner\Debug',
        os: 'windows',
      ),
      r'tool/build_client.sh "C:\Users\alice\vidctrl\build\windows\x64\runner\Debug"',
    );
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
    final prompt = agentPrompt(_en, clientPath: _client, os: 'linux');
    expect(find.text(prompt.trimRight()), findsOneWidget);
    // Nothing else: no program row, no kinds of agent.
    expect(find.text('Show in folder'), findsNothing);
    expect(find.textContaining('Claude Code'), findsNothing);
    expect(find.textContaining('sandbox'), findsNothing);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, [prompt]);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('on Windows the window copies the path in double quotes', (
    tester,
  ) async {
    const client = r'C:\Apps\VidCtrl\vidctrl-client.exe';
    await pumpApp(tester, FakeEnvironment(clientPath: client, os: 'windows'));
    final copied = _catchClipboard(tester);
    await _openFromHeader(tester);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied.single, contains('`"$client" manual`'));
    expect(copied.single, contains('`& "$client" manual`'));
  });

  testWidgets('in Ukrainian the window copies the Ukrainian prompt', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeEnvironment(clientPath: _client),
      locale: const Locale('uk'),
    );
    final copied = _catchClipboard(tester);
    await _openFromHeader(tester, tooltip: 'Робота з ШІ-агентом');

    await tester.tap(find.text('Копіювати'));
    await tester.pump();
    expect(copied, [agentPrompt(_uk, clientPath: _client, os: 'linux')]);
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

  testWidgets('without the program the window gives the command that '
      'builds it, and cannot copy a prompt', (tester) async {
    await pumpApp(tester, FakeEnvironment(clientPath: null));
    final copied = _catchClipboard(tester);
    await _openFromHeader(tester);

    expect(
      find.text(
        'This build has no vidctrl-client beside it. In the project folder, '
        'run:',
      ),
      findsOneWidget,
    );
    final command = "tool/build_client.sh '$_folder'";
    expect(find.text(command), findsOneWidget);
    expect(find.text('Then open this window again.'), findsOneWidget);
    expect(find.textContaining('manual'), findsNothing);
    final copyPrompt = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Copy'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(copyPrompt.onPressed, isNull);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, [command]);
  });

  testWidgets('a program built while the app runs is found when the window '
      'opens again', (tester) async {
    final env = FakeEnvironment(clientPath: null);
    await pumpApp(tester, env);
    await _openFromHeader(tester);
    expect(find.text('Then open this window again.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    env.clientPath = _client;
    await _openFromHeader(tester);
    expect(find.text('Then open this window again.'), findsNothing);
    expect(
      find.text(agentPrompt(_en, clientPath: _client, os: 'linux').trimRight()),
      findsOneWidget,
    );
  });

  testWidgets('in Ukrainian the window says in Ukrainian how to build it', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeEnvironment(clientPath: null),
      locale: const Locale('uk'),
    );
    await _openFromHeader(tester, tooltip: 'Робота з ШІ-агентом');

    expect(
      find.text(
        'Поруч із цією збіркою немає vidctrl-client. У теці проєкту '
        'виконайте:',
      ),
      findsOneWidget,
    );
    expect(find.text("tool/build_client.sh '$_folder'"), findsOneWidget);
    expect(find.text('Потім відкрийте це вікно ще раз.'), findsOneWidget);
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

    // Everything in view at every window size, the whole prompt too, with
    // Windows' longer path and its line on PowerShell; or, with no program,
    // the command that builds it.
    final cases = [
      for (final look in Look.values)
        for (final locale in const [Locale('en'), Locale('uk')])
          for (final size in const [minimumWindowSize, defaultWindowSize])
            for (final os in const ['linux', 'windows'])
              for (final missing in const [false, true])
                (
                  look: look,
                  locale: locale,
                  size: size,
                  os: os,
                  missing: missing,
                ),
    ];
    for (final (:look, :locale, :size, :os, :missing) in cases) {
      testWidgets('${size.width.round()} x ${size.height.round()}, '
          '${locale.languageCode}, ${look.name}, $os'
          '${missing ? ', no program' : ''}', (tester) async {
        final windows = os == 'windows';
        await pumpApp(
          tester,
          FakeEnvironment(
            os: os,
            clientPath: missing
                ? null
                : windows
                ? r'C:\Users\alice\Apps\VidCtrl\vidctrl-client.exe'
                : '/home/alice/Apps/vidctrl/vidctrl-client',
            appFolder: windows
                ? r'C:\Users\alice\Projects\vidctrl\build\windows\x64\runner\Debug'
                : _folder,
          ),
          locale: locale,
          look: look,
          size: size,
        );
        final l10n = lookupAppLocalizations(locale);
        await _openFromHeader(tester, tooltip: l10n.agentTitle);

        expect(tester.takeException(), isNull);
        final window = Offset.zero & size;
        final lowest = [
          missing
              ? find.text(l10n.agentMissingAfter)
              : find.byType(SelectableText),
          find.text(l10n.close),
        ];
        for (final finder in lowest) {
          expect(window.contains(tester.getBottomRight(finder)), isTrue);
        }
        if (!missing) {
          final prompt = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(AgentDialog),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(prompt.position.maxScrollExtent, 0);
        }
      });
    }
  });
}
