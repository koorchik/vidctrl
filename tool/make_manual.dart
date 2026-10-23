// Writes what vidctrl-client's manual takes from the app: the goals' English
// words (lib/core/control/manual_words.g.dart), then the manual itself as
// docs/CLIENT.md. Both are committed.
//
//   flutter test tool/make_manual.dart
//
// It goes through `flutter test` because the words live in the app's
// localizations, which need Flutter; the client, plain Dart, cannot read
// them. Run it after changing the English texts, a goal or the manual: a test
// fails until then.
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/scenario_texts.dart';
import 'package:vidctrl/core/control/manual.dart';
import 'package:vidctrl/core/scenarios/registry.dart';
import 'package:vidctrl/l10n/app_localizations.dart';

const manualWordsFile = 'lib/core/control/manual_words.g.dart';
const manualFile = 'docs/CLIENT.md';

/// Every goal's words as the panel shows them in English, by preset id.
Map<String, GoalWords> englishGoalWords() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  String joined(List<String> parts) =>
      parts.where((part) => part.isNotEmpty).join(' ');
  return {
    for (final scenario in scenarios)
      for (final preset in scenario.presets)
        preset.id: (
          title: scenarioTitle(l10n, scenario.id),
          // Resolve's two are told apart as on the panel's tile.
          subtitle: scenario.presets.length > 1
              ? presetTitle(l10n, preset.id)
              : scenarioSubtitle(l10n, scenario.id),
          hint: joined([
            scenarioHint(l10n, scenario.id),
            presetHint(l10n, preset.id),
            scenarioNotice(l10n, scenario.id),
          ]),
          options: {
            for (final option in preset.options)
              option.id: (
                title: optionTitle(l10n, preset.id, option.id),
                hint: optionHint(l10n, option.id),
                choices: {
                  for (final choice in option.choices)
                    choice: (
                      label: choiceLabel(l10n, preset.id, choice),
                      hint: choiceHint(l10n, option.id, choice),
                    ),
                },
              ),
          },
        ),
  };
}

/// manual_words.g.dart as it should be now.
String manualWordsSource([Map<String, GoalWords>? words]) {
  final out = StringBuffer()
    ..writeln('// Written by tool/make_manual.dart from the English texts;')
    ..writeln(
      '// run `flutter test tool/make_manual.dart` after changing them.',
    )
    ..writeln('// dart format off')
    ..writeln("import 'manual.dart';")
    ..writeln()
    ..writeln('/// Every goal\'s English words, by preset id.')
    ..writeln('const manualGoalWords = <String, GoalWords>{');
  for (final MapEntry(key: id, value: goal)
      in (words ?? englishGoalWords()).entries) {
    out
      ..writeln('  ${_string(id)}: (')
      ..writeln('    title: ${_string(goal.title)},')
      ..writeln('    subtitle: ${_string(goal.subtitle)},')
      ..writeln('    hint: ${_string(goal.hint)},')
      ..writeln('    options: {');
    for (final MapEntry(key: optionId, value: option) in goal.options.entries) {
      out
        ..writeln('      ${_string(optionId)}: (')
        ..writeln('        title: ${_string(option.title)},')
        ..writeln('        hint: ${_string(option.hint)},')
        ..writeln('        choices: {');
      for (final MapEntry(key: choice, value: words)
          in option.choices.entries) {
        out.writeln(
          '          ${_string(choice)}: '
          '(label: ${_string(words.label)}, hint: ${_string(words.hint)}),',
        );
      }
      out
        ..writeln('        },')
        ..writeln('      ),');
    }
    out
      ..writeln('    },')
      ..writeln('  ),');
  }
  out.writeln('};');
  return '$out';
}

/// [text] as a Dart string literal.
String _string(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

void main() {
  test('writes the manual\'s words and docs/CLIENT.md', () {
    final words = englishGoalWords();
    File(manualWordsFile).writeAsStringSync(manualWordsSource(words));
    File(
      manualFile,
    ).writeAsStringSync(manualDocument(client: 'vidctrl-client', words: words));
  });
}
