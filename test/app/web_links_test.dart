import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/app.dart';
import 'package:vidctrl/app/home/widgets/language_button.dart';
import 'package:vidctrl/app/home/widgets/recipe_pane.dart';
import 'package:vidctrl/app/home/widgets/web_links.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/window.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

/// The page that the link reading [text] opens.
String _target(WidgetTester tester, String text) => tester
    .widget<WebLink>(
      find.ancestor(of: find.text(text), matching: find.byType(WebLink)),
    )
    .url;

const _camctrl = 'Shooting on Blackmagic? Control the camera with CamCtrl';

Future<void> _chooseResolve(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.movie_edit));
  await tester.pump();
}

void main() {
  testWidgets('the header names the app and links to its website', (
    tester,
  ) async {
    await pumpApp(tester, FakeEnvironment());

    expect(find.text('VidCtrl'), findsOneWidget);
    expect(
      _target(tester, 'camctrl.app/vidctrl'),
      'https://camctrl.app/vidctrl',
    );
  });

  testWidgets('the header is there when the video engine is missing', (
    tester,
  ) async {
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
    expect(find.text('camctrl.app/vidctrl'), findsOneWidget);
    expect(find.byTooltip('About VidCtrl'), findsOneWidget);
  });

  testWidgets('CamCtrl is offered only while the goal is editing in Resolve', (
    tester,
  ) async {
    await pumpApp(tester, FakeEnvironment());
    expect(find.text(_camctrl), findsNothing);

    await _chooseResolve(tester);
    expect(_target(tester, _camctrl), 'https://camctrl.app');

    await tester.tap(find.text('Free Resolve'));
    await tester.pump();
    expect(find.text(_camctrl), findsOneWidget);

    await tester.tap(find.byIcon(Icons.inventory_2_rounded));
    await tester.pump();
    expect(find.text(_camctrl), findsNothing);
  });

  testWidgets('at the smallest window, CamCtrl gives way to the settings', (
    tester,
  ) async {
    await pumpApp(tester, FakeEnvironment(), size: minimumWindowSize);
    await _chooseResolve(tester);

    expect(find.text(_camctrl), findsNothing);
  });

  for (final size in const [minimumWindowSize, defaultWindowSize]) {
    testWidgets('the header\'s buttons end where the panel does: '
        '${size.width.round()} x ${size.height.round()}', (tester) async {
      await pumpApp(tester, FakeEnvironment(), size: size);

      expect(
        tester.getTopRight(find.byType(LanguageButton)).dx,
        tester.getTopRight(find.byType(RecipePane)).dx,
      );
    });
  }
}
