import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/control/client.dart';
import 'package:vidctrl/core/control/manual.dart';
import 'package:vidctrl/core/control/protocol.dart';
import 'package:vidctrl/core/control/views.dart';
import 'package:vidctrl/core/control/words.dart';
import 'package:vidctrl/core/scenarios/registry.dart';

import '../../../tool/make_manual.dart'
    show manualFile, manualWordsFile, manualWordsSource;

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

  test('the manual covers every command the client knows', () {
    for (final c in clientCommands) {
      expect(text, contains('`vidctrl-client $c'), reason: c);
      expect(commandHelp(c), contains('vidctrl-client $c'), reason: c);
      expect(text, contains(commandHelp(c).split('\n#### ').first), reason: c);
      expect(usage(), contains('  $c '), reason: c);
    }
    expect([
      for (final c in manualJson()['commands'] as List) (c as Map)['name'],
    ], clientCommands);
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
    expect(text, contains('### Archive, no quality loss: `--goal archive`'));
    expect(text, contains('`av1`: Smallest file (the default).'));
    expect(text, contains('`--goal resolve.studio`'));
  });

  test('the manual, help and quick start never speak of deleting files', () {
    final texts = [
      text,
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
    final top = text.indexOf('## Commands');
    expect(text.indexOf(neverDeletes), inInclusiveRange(0, top));
    expect(quickStart('x', os: 'linux'), contains(filesRule));
    expect(text, contains(quickStart('vidctrl-client', os: 'linux')));
    expect(commandHelp('remove'), contains('stay on disk'));
  });

  test('the quick start names the program, the manual and wait', () {
    final start = quickStart('/opt/Vid Ctrl/vidctrl-client', os: 'linux');
    expect(start, contains("`'/opt/Vid Ctrl/vidctrl-client' manual`"));
    expect(start, contains("`'/opt/Vid Ctrl/vidctrl-client' wait`"));
    expect(start, contains('--json'));
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
      expect(start, contains('`"$client" wait`'));
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
    expect(intro, contains("as the window's prompt has it"));
    expect(intro, contains(r'`"C:\…\vidctrl-client.exe"` on Windows'));
    expect(intro, contains(r'`& "C:\…\vidctrl-client.exe"`'));
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

  test('--help is a short list that points to the manual', () {
    expect(
      usage().trimRight(),
      endsWith('Run `vidctrl-client manual` for the full guide.'),
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
      title: 'Archive',
      subtitle: '',
      options: [
        OptionView(
          id: 'codec',
          title: 'Format',
          defaultChoice: 'av1',
          advanced: false,
          choices: [ChoiceView(id: 'av1', label: 'Smallest file', hint: '')],
        ),
      ],
    );
    const outcome = JobOutcome(
      jobId: 0,
      path: '/videos/a.mov',
      status: 'done',
      outputPath: '/videos/Converted/a.mp4',
      needsALook: false,
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
      outcome.toJson(),
      status.toJson(),
    ]);
    for (final key in keys) {
      expect(text, contains('`$key`'), reason: key);
    }
  });

  test('every status, plan, closeness and outcome is told in words', () {
    for (final id in [
      for (final status in JobStatus.values) status.name,
      'removed',
      for (final status in SourceStatus.values) status.name,
      'keptAsIs',
    ]) {
      expect(text, contains('- `$id`: '), reason: id);
    }
    expect(text, contains('- `belowTarget`: ${outcomeWords('belowTarget')}'));
    expect(text, contains('-check'));
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
      expect(text, contains('| `$event` |'), reason: event);
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
      expect(text, contains('| $code |'), reason: '$code');
    }
    for (final kind in ControlErrorKind.values) {
      expect(text, contains('`${kind.name}`'), reason: kind.name);
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
    expect([
      for (final e in json['events'] as List) (e as Map)['name'],
    ], contains(Events.jobFinished));
  });

  test('docs/CLIENT.md is the manual as it is now', () {
    expect(
      File(manualFile).readAsStringSync().replaceAll('\r\n', '\n'),
      text,
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
