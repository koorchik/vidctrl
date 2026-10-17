import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/widgets/recipe_pane.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/app/recipe/recipe_controller.dart';
import 'package:vidctrl/app/theme.dart';
import 'package:vidctrl/app/window.dart';
import 'package:vidctrl/core/scenarios/registry.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';

/// Every combination of an option list's choices.
Iterable<OptionValues> combinations(List<PresetOption> options) sync* {
  if (options.isEmpty) {
    yield const {};
    return;
  }
  for (final rest in combinations(options.skip(1).toList())) {
    for (final choice in options.first.choices) {
      yield {options.first.id: choice, ...rest};
    }
  }
}

/// Labels in the settings panel that are cut off with "…", or broken in the
/// middle of a word because the word is wider than its space.
///
/// Texts meant to shorten to one line (the technical summary, a folder name)
/// are exempt: the full text is in a tooltip or beside them.
List<String> textProblems(WidgetTester tester) {
  final problems = <String>[];
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byType(RecipePane),
      matching: find.byType(RichText),
    ),
  );
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    final singleLine = paragraph.maxLines == 1;
    if (paragraph.didExceedMaxLines && !singleLine) {
      problems.add('cut off: "$text"');
    }
    final width = paragraph.constraints.maxWidth;
    if (singleLine || !width.isFinite) continue;
    for (final word in text.split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: paragraph.text.style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      if (painter.width > width + 0.5) {
        problems.add('"$word" is wider than its space in "$text"');
      }
    }
  }
  return problems;
}

void main() {
  // Whether text fits depends on the font, so the app's real ones are used.
  setUpAll(loadRealFonts);

  // The smallest window, the height where the roomier spacing starts, and
  // the size the window opens at.
  const sizes = {
    'smallest window': minimumWindowSize,
    'where the spacing gets roomier': Size(960, 790),
    'default window': defaultWindowSize,
  };

  // The looks letter their labels differently, so each is checked.
  final cases = [
    for (final look in Look.values)
      for (final locale in const [Locale('en'), Locale('uk')])
        for (final MapEntry(key: name, value: size) in sizes.entries)
          (look: look, locale: locale, name: name, size: size),
  ];

  for (final (:look, :locale, :name, :size) in cases) {
    testWidgets(
      'the settings panel shows everything, uncut, without scrolling: '
      '$name, ${locale.languageCode}, ${look.name}',
      (tester) async {
        final env = FakeEnvironment(capabilities: withGpu({'av1_nvenc'}));
        env.ffprobe.add('/videos/a.mp4');
        env.ffprobe.add('/videos/b.mp4');
        final sources = await pumpApp(
          tester,
          env,
          locale: locale,
          look: look,
          size: size,
        );
        await addVideos(tester, sources, ['/videos/a.mp4', '/videos/b.mp4']);
        // One of two selected: both buttons and a full summary are shown.
        sources.select(0);
        final recipe = ProviderScope.containerOf(
          tester.element(find.byType(RecipePane)),
        ).read(recipeProvider.notifier);

        final tooTall = <String>[];
        final badText = <String>{};
        for (final scenario in scenarios) {
          for (final preset in scenario.presets) {
            for (final values in combinations(preset.options)) {
              for (final sample in SampleChoice.values) {
                recipe.load(Recipe(presetId: preset.id, values: values));
                recipe.setSample(sample);
                await tester.pump();
                final scrollable = tester.state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byType(RecipePane),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                );
                final overflow = scrollable.position.maxScrollExtent;
                if (overflow > 0) {
                  tooTall.add(
                    '${preset.id} $values ${sample.name}: '
                    '${overflow.round()} px too tall',
                  );
                }
                for (final problem in textProblems(tester)) {
                  badText.add('${preset.id} $values: $problem');
                }
              }
            }
          }
        }

        expect(tooTall, isEmpty, reason: tooTall.join('\n'));
        expect(badText, isEmpty, reason: badText.join('\n'));
      },
    );
  }
}
