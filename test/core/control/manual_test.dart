import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/control/client.dart';
import 'package:vidctrl/core/control/codes.dart';
import 'package:vidctrl/core/control/manual.dart';
import 'package:vidctrl/core/control/manual_words.g.dart';
import 'package:vidctrl/core/control/protocol.dart';
import 'package:vidctrl/core/control/views.dart';
import 'package:vidctrl/core/control/words.dart';
import 'package:vidctrl/core/scenarios/registry.dart';

import '../../../tool/make_manual.dart'
    show manualFile, manualWordsFile, manualWordsSource;

/// What [markdown] names a part or list by: its headings, and the words it
/// sets in bold.
Set<String> _headings(String markdown) => {
  for (final m in RegExp(
    r'^#+ (.+)$|\*\*([^*]+)\*\*',
    multiLine: true,
  ).allMatches(markdown))
    m[1] ?? m[2]!,
};

/// Every key in [json] and the objects and lists inside it.
Set<String> _keys(Object? json) => switch (json) {
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) ...{
      '$key',
      ..._keys(value),
    },
  },
  final List<Object?> list => {for (final item in list) ..._keys(item)},
  _ => const {},
};

void main() {
  final text = manual(client: 'vidctrl-client');
  final document = manualDocument(client: 'vidctrl-client');

  test('the manual is short enough for an agent to read in one go', () {
    expect(
      utf8.encode(text).length,
      lessThanOrEqualTo(16000),
      reason:
          'Keep `manual` within 16000 bytes: shorten an entry; details '
          'belong in `help <command>`.',
    );
  });

  test('the manual covers every command the client knows', () {
    for (final c in clientCommands) {
      expect(text, contains('\n- `$c'), reason: c);
      expect(commandHelp(c), contains('vidctrl-client $c'), reason: c);
      expect(
        document,
        contains(commandHelp(c).split('\n#### ').first),
        reason: c,
      );
      expect(usage(), contains('  $c '), reason: c);
    }
    expect(
      text,
      contains(
        '`vidctrl-client help <command>` prints a command\'s examples, its '
        'text output and a JSON sample.',
      ),
    );
    expect([
      for (final c in manualJson()['commands'] as List) (c as Map)['name'],
    ], clientCommands);
  });

  test('every command\'s help has an example, and a sample of its JSON', () {
    for (final c in clientCommands) {
      final help = commandHelp(c);
      expect(help, contains('```sh\nvidctrl-client $c'), reason: c);
      if (c != 'help') expect(help, contains('```json\n{'), reason: c);
    }
  });

  test('the manual lists every goal, option and choice', () {
    for (final s in scenarios) {
      for (final preset in s.presets) {
        expect(text, contains(preset.id));
        for (final o in preset.options) {
          expect(text, contains('--opt ${o.id}='), reason: o.id);
          for (final c in o.choices) {
            expect(text, contains('`$c`'), reason: '${preset.id} $c');
          }
        }
      }
    }
    // With the panel's words, not only ids.
    expect(
      text,
      contains('- `--goal archive` (`archive.master`): Archive, no quality'),
    );
    expect(text, contains('`av1` Smallest file (default)'));
    expect(text, contains('`--goal resolve.studio`'));
    // In full in the goals' help.
    final goals = commandHelp('goals');
    expect(goals, contains('#### Archive, no quality loss: `--goal archive`'));
    expect(goals, contains('`av1`: Smallest file (the default).'));
  });

  test('help goals has the window\'s words for every id goals --json '
      'gives', () {
    final goals = commandHelp('goals');
    for (final s in scenarios) {
      for (final preset in s.presets) {
        final words = manualGoalWords[preset.id]!;
        expect(goals, contains(words.title), reason: preset.id);
        expect(goals, contains(words.subtitle), reason: preset.id);
        expect(goals, contains(words.hint), reason: preset.id);
        for (final o in preset.options) {
          final option = words.options[o.id]!;
          expect(goals, contains('`--opt ${o.id}=…`: ${option.title}'));
          expect(goals, contains(option.hint), reason: o.id);
          for (final c in o.choices) {
            final choice = option.choices[c]!;
            expect(goals, contains('`$c`'), reason: '${preset.id} $c');
            // A label that only repeats the id is said by the id.
            if (choice.label.toLowerCase() != c) {
              expect(goals, contains(choice.label), reason: c);
            }
            expect(goals, contains(choice.hint), reason: c);
          }
        }
      }
    }
  });

  test('the manual says which goal to choose', () {
    final part = text.substring(text.indexOf('## Goals'));
    expect(part, contains('the usual choice to save space without loss'));
    expect(part, contains('at most 1080p'));
  });

  test('the manual, help and quick start never speak of deleting files', () {
    final texts = [
      text,
      document,
      quickStart('x', os: 'linux'),
      quickStart('/opt/VidCtrl/vidctrl-client', os: 'linux'),
      quickStart(r'C:\VidCtrl\vidctrl-client.exe', os: 'windows'),
      usage(),
      jsonEncode(manualJson()),
      for (final c in clientCommands) commandHelp(c),
    ];
    for (final t in texts) {
      expect(speaksOfDeleting(t), isFalse, reason: t);
    }
  });

  test('the manual says plainly that remove leaves the file on disk', () {
    final top = text.substring(0, text.indexOf('## Commands'));
    expect(top, contains(neverDeletes));
    expect(top, contains(filesRule));
    expect(top, contains('"Remove" only takes a video off the list'));
    expect(text, contains(quickStart('vidctrl-client', os: 'linux')));
    expect(commandHelp('remove'), contains('stay on disk'));
  });

  test('the manual\'s quick start says what the prompt leaves to it', () {
    final start = text.substring(
      text.indexOf('## Quick start'),
      text.indexOf('## What VidCtrl is'),
    );
    expect(start, contains('Finding the videos is your job'));
    expect(start, contains('`vidctrl-client wait --json`'));
    expect(start, contains('`vidctrl-client wait --any --timeout 540 --json`'));
    expect(start, contains('`pending`'));
    expect(start, contains(filesRule));
  });

  test('the quick start is what the program is and its manual', () {
    final start = quickStart('/opt/Vid Ctrl/vidctrl-client', os: 'linux');
    expect(start, contains("`'/opt/Vid Ctrl/vidctrl-client'` controls it"));
    expect(start, contains("`'/opt/Vid Ctrl/vidctrl-client' manual`"));
    expect(start, contains('`--json`'));
    expect(start, isNot(contains('wait')));
    expect(start, isNot(contains(filesRule)));
    expect('\n- '.allMatches(start), hasLength(1));
    expect(
      quickStart('vidctrl-client', os: 'windows'),
      contains('`vidctrl-client manual`'),
    );
  });

  group('a path is typed as the system\'s terminal needs it', () {
    test('on Linux and macOS in single quotes, so nothing in it expands', () {
      for (final os in ['linux', 'macos']) {
        expect(
          shellWord(r'/home/alice/$HOME/vidctrl-client', os: os),
          r"'/home/alice/$HOME/vidctrl-client'",
        );
      }
      expect(
        shellWord("/home/alice/Bob's/vidctrl-client", os: 'linux'),
        r"'/home/alice/Bob'\''s/vidctrl-client'",
      );
    });

    test('on Windows in double quotes, which Git Bash, cmd and PowerShell '
        'read, with a line on PowerShell\'s &', () {
      const client = r'C:\Program Files\VidCtrl\vidctrl-client.exe';
      expect(shellWord(client, os: 'windows'), '"$client"');
      final start = quickStart(client, os: 'windows');
      expect(start, contains('`"$client" manual`'));
      expect(
        start,
        contains(
          '- In PowerShell, put & before a quoted path: '
          '`& "$client" manual`.\n',
        ),
      );
      expect(speaksOfDeleting(start), isFalse);
    });

    test('a plain name stays as it is, with no word on PowerShell', () {
      for (final os in ['linux', 'macos', 'windows']) {
        expect(shellWord('vidctrl-client', os: os), 'vidctrl-client');
        expect(
          quickStart('vidctrl-client', os: os),
          isNot(contains('PowerShell')),
        );
      }
      expect(
        quickStart('/opt/vidctrl/vidctrl-client', os: 'linux'),
        isNot(contains('PowerShell')),
      );
    });
  });

  test('the manual says what the name in its examples stands for', () {
    final intro = text.substring(0, text.indexOf('## Quick start'));
    expect(intro, contains('by its full path'));
    expect(intro, contains("as the window's prompt has it"));
  });

  test('the manual, help and usage are typed for the system asked for', () {
    expect(
      manual(client: 'vidctrl-client', os: 'windows'),
      manual(client: 'vidctrl-client', os: 'linux'),
    );
    expect(
      usage(client: '/opt/vidctrl/vidctrl-client', os: 'linux'),
      contains("Usage: '/opt/vidctrl/vidctrl-client' <command>"),
    );
    expect(
      commandHelp(
        'wait',
        client: r'C:\VidCtrl\vidctrl-client.exe',
        os: 'windows',
      ),
      contains(r'"C:\VidCtrl\vidctrl-client.exe" wait'),
    );
  });

  test('--help is a short list that points to the manual and help', () {
    expect(
      usage().trimRight(),
      endsWith(
        'Run `vidctrl-client manual` for the guide; `vidctrl-client help '
        '<command>` for a command\'s details.',
      ),
    );
    expect(usage().split('\n').length, lessThanOrEqualTo(40));
  });

  test('every JSON field the window sends is explained', () {
    const job = JobView(
      id: 0,
      videoId: 0,
      path: '/videos/a.mov',
      goal: 'archive.master',
      options: {},
      sample: 'start',
      status: 'done',
      fraction: 1,
      remainingSeconds: 0,
      attempt: 1,
      outputPath: '/videos/Converted/a.mp4',
      outputBytes: 1,
      sourceBytes: 1,
      seconds: 1,
      quality: QualityView(
        outcome: 'standard',
        value: 35,
        standardValue: 35,
        vmaf: 96,
        xpsnr: 43,
        share: .2,
      ),
      needsALook: false,
      errorLines: [],
    );
    const video = VideoView(
      id: 0,
      path: '/videos/a.mov',
      status: 'ready',
      sizeBytes: 1,
      durationSeconds: 1,
      width: 1,
      height: 1,
      videoCodec: 'hevc',
      audioCodecs: [],
      hdr: false,
      preview: GoalPreview(
        goal: 'archive.master',
        plan: 'encode',
        expectedBytes: 1,
        measured: true,
        measuring: false,
        closeness: 'same',
      ),
    );
    const goal = GoalView(
      id: 'archive.master',
      scenario: 'archive',
      options: [
        OptionView(
          id: 'codec',
          defaultChoice: 'av1',
          advanced: false,
          choices: ['av1'],
        ),
      ],
    );
    const pending = PendingJob(
      id: 0,
      status: 'running',
      fraction: .5,
      remainingSeconds: 1,
      attempt: 1,
    );
    const status = StatusView(
      state: 'ready',
      version: '1.0.0',
      busy: false,
      paused: false,
      jobs: {},
    );
    final keys = _keys([
      job.toJson(),
      video.toJson(),
      goal.toJson(),
      pending.toJson(),
      status.toJson(),
    ]);
    for (final key in keys) {
      expect(text, contains('`$key`'), reason: key);
    }
  });

  test('every code the JSON carries is explained, with its words', () {
    final codes = [
      ...JobStatusCodes.all,
      ...VideoStatusCodes.all,
      ...PlanCodes.all,
      ...ClosenessCodes.all,
      ...OutcomeCodes.all,
      ...StateCodes.all,
      ...AddResultCodes.all,
      ...SampleCodes.all,
      ...ComparisonCodes.all,
      for (final kind in ControlErrorKind.values) kind.code,
      ...ClientErrorCodes.all,
    ];
    final codesPart = text.substring(text.indexOf('## Codes'));
    for (final code in codes) {
      expect(codesPart, contains('`$code`'), reason: code);
      expect(document, contains('- `$code`: '), reason: code);
    }
    // In full, with the words, in the help of the commands that give them.
    for (final status in JobStatus.values.map(codeOf)) {
      expect(
        commandHelp('queue'),
        contains('- `$status`: ${statusWords(status)}'),
      );
    }
    for (final status in SourceStatus.values.map(codeOf)) {
      expect(
        commandHelp('videos'),
        contains('- `$status`: ${statusWords(status)}'),
      );
    }
    expect(
      commandHelp('job'),
      contains('- `BELOW_TARGET`: ${outcomeWords(OutcomeCodes.belowTarget)}'),
    );
    expect(text, contains('-check'));
  });

  test('the manual\'s code lists part codes by ; alone', () {
    final part = text.substring(
      text.indexOf('## Codes'),
      text.indexOf('## Goals'),
    );
    for (final line in part.split('\n').where((l) => l.startsWith('- **'))) {
      final codes = line.substring(line.indexOf('): ') + 3);
      for (final entry in codes.split('; ')) {
        expect(entry, startsWith('`'), reason: line);
      }
    }
  });

  test('the manual says an option not offered here takes the default', () {
    expect(text, contains('so a script may name the defaults everywhere'));
  });

  test('what a help points to is in it or in the manual', () {
    final known = _headings(text);
    for (final c in clientCommands) {
      final help = commandHelp(c);
      final named = {
        for (final m in RegExp(r'(?:see|under) "([^"…]+)"').allMatches(help))
          m[1]!,
      };
      for (final name in named) {
        expect(
          {...known, ..._headings(help)},
          contains(name),
          reason: '$c points to "$name"',
        );
      }
    }
  });

  test('the manual names no value as it was before codes', () {
    for (final old in [
      '`keptAsIs`',
      '`notWorthIt`',
      '`belowTarget`',
      '`veryClose`',
      '`ffmpegMissing`',
      '`badArgument`',
      '`job-finished`',
      '`app-closing`',
      'Text`',
    ]) {
      expect(document, isNot(contains(old)), reason: old);
    }
  });

  test('every event and exit code is listed', () {
    for (final event in [
      Events.snapshot,
      Events.videoAdded,
      Events.videoReady,
      Events.videoUnreadable,
      Events.videoRemoved,
      Events.jobAdded,
      Events.jobChecking,
      Events.jobStarted,
      Events.jobProgress,
      Events.jobFinished,
      Events.jobRemoved,
      Events.queuePaused,
      Events.queueResumed,
      Events.queueIdle,
      Events.compareFinished,
      Events.appClosing,
    ]) {
      expect(text, contains('`$event`'), reason: event);
      expect(commandHelp('events'), contains('| `$event` |'), reason: event);
    }
    for (final code in [
      ExitCode.ok,
      ExitCode.jobsFailed,
      ExitCode.notRunning,
      ExitCode.timeout,
      ExitCode.appClosed,
      ExitCode.badArguments,
      ExitCode.ffmpegMissing,
    ]) {
      expect(text, contains('\n- $code: '), reason: '$code');
      expect(commandHelp('wait'), contains('| $code |'), reason: '$code');
    }
    for (final kind in ControlErrorKind.values) {
      expect(text, contains('`${kind.code}`'), reason: kind.code);
    }
  });

  test('manual --json gives the goals, exit codes and events as data', () {
    final json = jsonDecode(jsonEncode(manualJson())) as Map<String, Object?>;
    final goals = json['goals'] as List;
    expect(
      [for (final g in goals) (g as Map)['id']],
      [
        for (final s in scenarios)
          for (final p in s.presets) p.id,
      ],
    );
    final archive = goals.first as Map;
    expect(archive['title'], 'Archive');
    expect(archive['goal'], 'archive');
    expect((json['exitCodes'] as Map).keys, containsAll(['0', '1', '6']));
    final events = [
      for (final e in json['events'] as List) (e as Map)['name'] as String,
    ];
    expect(events, contains(Events.jobFinished));
    for (final event in events) {
      expect(event, matches(codePattern));
    }
    final codes = json['codes'] as Map;
    expect([
      for (final c in codes['jobStatus'] as List) (c as Map)['code'],
    ], JobStatusCodes.all);
    expect([
      for (final c in codes['plan'] as List) (c as Map)['code'],
    ], PlanCodes.all);
    expect([
      for (final c in codes['event'] as List) (c as Map)['code'],
    ], events);
    for (final kind in codes.values) {
      for (final c in kind as List) {
        expect((c as Map)['code'], matches(codePattern));
        expect(c['description'], isNotEmpty);
      }
    }
  });

  test('docs/CLIENT.md is the manual, then every command\'s details', () {
    expect(document, startsWith(text));
    expect(
      File(manualFile).readAsStringSync().replaceAll('\r\n', '\n'),
      document,
      reason: 'Run `flutter test tool/make_manual.dart`.',
    );
  });

  test('the goal words are up to date with the English texts', () {
    expect(
      File(manualWordsFile).readAsStringSync().replaceAll('\r\n', '\n'),
      manualWordsSource(),
      reason: 'Run `flutter test tool/make_manual.dart`.',
    );
  });
}
