import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/control/client.dart';
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/launcher.dart';
import 'package:vidctrl/core/control/listener.dart';
import 'package:vidctrl/core/control/manual.dart';
import 'package:vidctrl/core/control/process_alive.dart';
import 'package:vidctrl/core/control/protocol.dart';
import 'package:vidctrl/core/control/words.dart';

import '../../support/machine_json.dart';

typedef _Answer = FutureOr<Object?> Function(
  Map<String, Object?> params,
  ControlPeer peer,
);

Map<String, Object?> _status(String state) => {
  'state': state,
  'version': '0.1.0',
  'busy': false,
  'paused': false,
  'jobs': <String, int>{},
};

/// A window in the test: it answers `status` as ready and `subscribe` with
/// nothing, unless [answers] says otherwise, and refuses any other method
/// [answers] does not name.
class _FakeApp {
  _FakeApp._(this.listener, this.calls, this.subscribers);

  final ControlListener listener;
  final List<(String, Map<String, Object?>)> calls;

  /// The clients that asked for events: the window tells events to these
  /// only.
  final List<ControlPeer> subscribers;

  static Future<_FakeApp> start(
    EndpointFile file, [
    Map<String, _Answer> answers = const {},
  ]) async {
    final calls = <(String, Map<String, Object?>)>[];
    final subscribers = <ControlPeer>[];
    final all = <String, _Answer>{
      Methods.status: (_, _) => _status('READY'),
      Methods.subscribe: (_, _) => const <String, Object?>{},
      ...answers,
    };
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async {
        calls.add((method, params));
        if (method == Methods.subscribe) subscribers.add(peer);
        final answer = all[method];
        if (answer == null) {
          throw ControlError(ControlErrorKind.unknownMethod, 'No $method.');
        }
        return answer(params, peer);
      },
    );
    addTearDown(listener.close);
    await file.write(
      Endpoint(
        port: listener.port,
        token: 't',
        pid: pid,
        version: '0.1.0',
        protocol: controlProtocol,
      ),
    );
    return _FakeApp._(listener, calls, subscribers);
  }

  Map<String, Object?> paramsOf(String method) =>
      calls.lastWhere((call) => call.$1 == method).$2;

  bool asked(String method) => calls.any((call) => call.$1 == method);
}

/// Starts nothing unless told how.
class _FakeLauncher implements AppLauncher {
  _FakeLauncher([this._start]);

  final Future<void> Function()? _start;
  var starts = 0;

  @override
  String get os => 'linux';

  @override
  String get clientExecutable => '/opt/vidctrl/vidctrl-client';

  @override
  Map<String, String> get environment => const {};

  @override
  String? get appPath => '/opt/vidctrl/vidctrl';

  @override
  Future<void> start() async {
    starts++;
    await _start?.call();
  }
}

class _Run {
  _Run(this.exitCode, this.out, this.err);

  final int exitCode;
  final String out;
  final String err;
}

late EndpointFile _endpoint;

Future<_Run> _run(
  List<String> args, {
  AppLauncher? launcher,
  StringBuffer? out,
  StringBuffer? err,
  String os = 'linux',
  Map<String, String> environment = const {'HOME': '/home/alice'},
  String workingDirectory = '/home/alice/work',
  ProcessAlive? isAlive,
}) async {
  out ??= StringBuffer();
  err ??= StringBuffer();
  final code = await runClient(
    args,
    ClientIo(
      out: out,
      err: err,
      environment: environment,
      workingDirectory: workingDirectory,
      executable: '/opt/vidctrl/vidctrl-client',
      os: os,
      launcher: launcher ?? _FakeLauncher(),
      endpoint: _endpoint,
      isAlive: isAlive,
    ),
  );
  return _Run(code, '$out', '$err');
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('It never happened.');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Map<String, Object?> _job(int id, String status, {String? outputPath}) => {
  'id': id,
  'videoId': id,
  'path': '/videos/clip$id.mov',
  'goal': 'archive.master',
  'options': {'codec': 'av1'},
  'status': status,
  'outputPath': ?outputPath,
  'needsALook': false,
  'errorLines': <String>[],
};

Map<String, Object?> _outcome(
  int id,
  String status, {
  bool needsALook = false,
}) => {
  'jobId': id,
  'path': '/videos/clip$id.mov',
  'status': status,
  if (status == 'done') 'outputPath': '/videos/Converted/clip$id.mp4',
  'needsALook': needsALook,
};

Map<String, Object?> _video(int id) => {
  'id': id,
  'path': '/videos/clip$id.mov',
  'status': 'READY',
  'sizeBytes': 1500000000,
  'width': 3840,
  'height': 2160,
  'audioCodecs': ['aac'],
  'hdr': false,
};

/// What the window answers about results: a job worth a look by eye, its
/// comparison, a video's details and an estimate.
final _resultAnswers = <String, _Answer>{
  Methods.jobGet: (params, _) => {
    'job': {
      ..._job(
        2,
        'done',
        outputPath: '/videos/Converted/clip2_av1-crf20-check.mp4',
      ),
      'outputBytes': 1000000,
      'quality': {
        'outcome': 'BELOW_TARGET',
        'value': 20,
        'standardValue': 35,
        'vmaf': 93.1,
        'xpsnr': 40.2,
        'share': .4,
      },
      'needsALook': true,
    },
    if (params['command'] == true)
      'command':
          'ffmpeg -hide_banner -i file:/videos/clip2.mov -c:v libsvtav1 -crf 20 '
          'file:/videos/Converted/clip2_av1-crf20-check.mp4',
  },
  Methods.jobCompare: (params, _) => params['wait'] == false
      ? {'started': true}
      : {
          'job': params['job'],
          'status': 'MEASURED',
          'closeness': 'SAME',
          'closenessText': 'Looks the same as the original',
          'vmaf': 96.2,
          'xpsnr': 43.0,
        },
  Methods.videosDetails: (params, _) => {
    'info': _video(1),
    if (params['raw'] == true)
      'raw': {
        'format': {'format_name': 'mov'},
      }
    else
      'details': [
        {
          'title': 'Video track 1',
          'rows': [
            ['Format', 'H.265 / HEVC'],
            ['Resolution', '3840×2160'],
          ],
        },
        {
          'title': 'File',
          'rows': [
            ['Size', '1.5 GB'],
          ],
        },
      ],
  },
  Methods.videosEstimate: (params, _) => {
    'videos': [
      {
        ..._video(1),
        'preview': {
          'goal': 'archive.master',
          'plan': 'ENCODE',
          'expectedBytes': 400000000,
          'measured': true,
          'measuring': false,
          'closeness': 'SAME',
        },
      },
    ],
  },
};

void main() {
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('client');
    addTearDown(() => dir.delete(recursive: true));
    _endpoint = EndpointFile(p.join(dir.path, 'control.json'));
  });

  test('relative and ~ paths are sent absolute', () async {
    final app = await _FakeApp.start(_endpoint, {
      Methods.videosAdd: (params, _) => {
        'videos': [
          for (final (i, path) in (params['paths'] as List).indexed)
            {'path': path, 'id': i + 1, 'result': 'ADDED'},
        ],
      },
    });
    final run = await _run(['add', 'clip.mov', '~/Videos', './x/../y.mp4']);
    expect(run.exitCode, 0, reason: run.err);
    expect(app.paramsOf(Methods.videosAdd), {
      'paths': [
        '/home/alice/work/clip.mov',
        '/home/alice/Videos',
        '/home/alice/work/y.mp4',
      ],
      'wait': true,
    });
    expect(run.out, contains('/home/alice/work/clip.mov'));

    await _run(['add', '/videos/a.mov', '--no-wait']);
    expect(app.paramsOf(Methods.videosAdd), {
      'paths': ['/videos/a.mov'],
      'wait': false,
    });
  });

  test('on Windows, paths are made absolute the Windows way', () async {
    final app = await _FakeApp.start(_endpoint, {
      Methods.videosAdd: (params, _) => {
        'videos': [
          for (final (i, path) in (params['paths'] as List).indexed)
            {'path': path, 'id': i + 1, 'result': 'ADDED'},
        ],
      },
      Methods.queueAdd: (params, _) => {
        'goal': 'archive.master',
        'options': <String, String>{},
        'added': <Object?>[],
        'alreadyQueued': <int>[],
        'skipped': <Object?>[],
      },
    });
    Future<_Run> run(List<String> args) => _run(
      args,
      os: 'windows',
      environment: const {'USERPROFILE': r'C:\Users\alice'},
      workingDirectory: r'C:\work',
    );
    final add = await run([
      'add',
      'clip.mov',
      r'~\Videos',
      '~/Docs',
      r'.\x\..\y.mp4',
      r'D:\films\a.mkv',
    ]);
    expect(add.exitCode, 0, reason: add.err);
    expect(app.paramsOf(Methods.videosAdd)['paths'], [
      r'C:\work\clip.mov',
      r'C:\Users\alice\Videos',
      r'C:\Users\alice\Docs',
      r'C:\work\y.mp4',
      r'D:\films\a.mkv',
    ]);
    await run(['queue', 'add', '1', '--out', r'..\done']);
    expect(app.paramsOf(Methods.queueAdd)['out'], r'C:\done');
  });

  test('queue add sends goal, options, sample and folder as given', () async {
    final app = await _FakeApp.start(_endpoint, {
      Methods.queueAdd: (params, _) => {
        'goal': 'archive.master',
        'options': {'speed': 'fast'},
        'added': [_job(1, 'WAITING')],
        'alreadyQueued': <int>[],
        'skipped': <Object?>[],
      },
    });
    final run = await _run([
      'queue',
      'add',
      '3',
      '--goal',
      'archive',
      '--opt',
      'speed=fast',
      '--sample',
      'middle',
      '--out',
      '/out',
    ]);
    expect(run.exitCode, 0, reason: run.err);
    expect(app.paramsOf(Methods.queueAdd), {
      'videos': [3],
      'goal': 'archive',
      'options': {'speed': 'fast'},
      'sample': 'MIDDLE',
      'out': '/out',
    });
    expect(run.out, contains('archive.master'));
    expect(run.out, contains('Job 1'));

    await _run(['queue', 'add', 'a.mov', '--out', 'next', '--subfolder', 'X']);
    expect(app.paramsOf(Methods.queueAdd), {
      'videos': ['/home/alice/work/a.mov'],
      'out': 'next',
      'subfolder': 'X',
    });
    await _run(['queue', 'add', '1', '--out', '../done']);
    expect(app.paramsOf(Methods.queueAdd)['out'], '/home/alice/done');
  });

  test(
    'the queue\'s controls ask the window for what its buttons do',
    () async {
      final app = await _FakeApp.start(_endpoint, {
        Methods.queueRemove: (params, _) => {'removed': params['jobs']},
        Methods.queueMove: (_, _) => {
          'jobs': [_job(3, 'WAITING'), _job(1, 'RUNNING')],
        },
        Methods.queueRetry: (params, _) => {
          'job': _job(params['job'] as int, 'waiting'),
        },
        Methods.queueClearFinished: (_, _) => {'removed': <int>[]},
        Methods.queuePause: (_, _) => {'paused': true},
        Methods.queueResume: (_, _) => {'paused': false},
        Methods.queueCancel: (params, _) => params['job'] == 3
            ? {'cancelled': null, 'job': _job(3, 'DONE')}
            : {'cancelled': params['job'] ?? 1},
        Methods.queueConvertAnyway: (_, _) => {
          'added': [_job(5, 'WAITING')],
          'alreadyQueued': false,
        },
        Methods.queueConvertWhole: (_, _) => {
          'added': <Object?>[],
          'alreadyQueued': true,
        },
      });
      for (final (args, method, params, printed) in [
        (
          ['queue', 'remove', '1', '2'],
          Methods.queueRemove,
          {
            'jobs': [1, 2],
          },
          'Job 2: Taken out of the queue; any finished file stays on disk.',
        ),
        (
          ['queue', 'move', '3', '1'],
          Methods.queueMove,
          {'job': 3, 'position': 1},
          '1. Job 3: Waiting.',
        ),
        (
          ['queue', 'retry', '4'],
          Methods.queueRetry,
          {'job': 4},
          'Job 4: Queued again.',
        ),
        (
          ['queue', 'clear-finished'],
          Methods.queueClearFinished,
          <String, Object?>{},
          'nothing was taken out',
        ),
        (['pause'], Methods.queuePause, <String, Object?>{}, 'paused'),
        (['resume'], Methods.queueResume, <String, Object?>{}, 'goes on'),
        (
          ['cancel'],
          Methods.queueCancel,
          <String, Object?>{},
          'Job 1: Cancelled',
        ),
        (['cancel', '2'], Methods.queueCancel, {'job': 2}, 'Job 2: Cancelled'),
        (
          ['cancel', '3'],
          Methods.queueCancel,
          {'job': 3},
          'Job 3: Not cancelled; it ended first: Done.',
        ),
        (
          ['queue', 'convert-anyway', '0'],
          Methods.queueConvertAnyway,
          {'job': 0},
          'Job 5: Queued.',
        ),
        (
          ['queue', 'convert-whole', '0'],
          Methods.queueConvertWhole,
          {'job': 0},
          'In the queue already',
        ),
      ]) {
        final run = await _run(args);
        expect(run.exitCode, ExitCode.ok, reason: '$args ${run.err}');
        expect(app.paramsOf(method), params, reason: '$args');
        expect(run.out, contains(printed), reason: '$args');
      }

      // Refused before the window is asked anything.
      final asked = app.calls.length;
      for (final args in [
        ['queue', 'remove'],
        ['queue', 'remove', 'a.mov'],
        ['queue', 'move', '3'],
        ['queue', 'move', '3', 'top'],
        ['queue', 'retry'],
        ['queue', 'retry', '1', '2'],
        ['queue', 'clear-finished', '1'],
        ['queue', 'convert-whole', 'x'],
        ['pause', 'now'],
        ['cancel', '1', '2'],
        ['cancel', 'all'],
      ]) {
        final run = await _run(args);
        expect(run.exitCode, ExitCode.badArguments, reason: '$args');
        expect(run.err, isNotEmpty, reason: '$args');
      }
      expect(app.calls.length, asked);
    },
  );

  test(
    'job, compare, details and estimate ask what the window shows',
    () async {
      final app = await _FakeApp.start(_endpoint, _resultAnswers);
      for (final (args, method, params, printed) in [
        (['job', '2'], Methods.jobGet, {'job': 2}, 'Worth a look by eye'),
        (
          ['job', '2', '--command'],
          Methods.jobGet,
          {'job': 2, 'command': true},
          'ffmpeg -hide_banner',
        ),
        (['compare', '2'], Methods.jobCompare, {'job': 2}, 'Looks the same'),
        (
          ['compare', '2', '--no-wait'],
          Methods.jobCompare,
          {'job': 2, 'wait': false},
          'Job 2: Comparing with the original',
        ),
        (['details', '1'], Methods.videosDetails, {'video': 1}, 'Resolution: '),
        (
          ['details', 'a.mov'],
          Methods.videosDetails,
          {'video': '/home/alice/work/a.mov'},
          'Video track 1',
        ),
        (['details', '--job', '2'], Methods.videosDetails, {'job': 2}, 'File'),
        (
          ['details', '1', '--raw'],
          Methods.videosDetails,
          {'video': 1, 'raw': true},
          '"format_name": "mov"',
        ),
        (
          [
            'estimate',
            '1',
            'b.mov',
            '--goal',
            'archive',
            '--opt',
            'codec=hevc',
          ],
          Methods.videosEstimate,
          {
            'videos': [1, '/home/alice/work/b.mov'],
            'goal': 'archive',
            'options': {'codec': 'hevc'},
          },
          'About 400.0 MB, measured',
        ),
      ]) {
        final run = await _run(args);
        expect(run.exitCode, ExitCode.ok, reason: '$args ${run.err}');
        expect(app.paramsOf(method), params, reason: '$args');
        expect(run.out, contains(printed), reason: '$args');
      }

      // Refused before the window is asked anything.
      final asked = app.calls.length;
      for (final args in [
        ['job'],
        ['job', 'x'],
        ['job', '1', '2'],
        ['compare'],
        ['compare', '1', '2'],
        ['details'],
        ['details', '1', '--job', '2'],
        ['details', '--job', 'x'],
        ['details', '1', '2'],
        ['estimate'],
        ['estimate', '1', '--opt', 'codec'],
      ]) {
        final run = await _run(args);
        expect(run.exitCode, ExitCode.badArguments, reason: '$args');
        expect(run.err, isNotEmpty, reason: '$args');
      }
      expect(app.calls.length, asked);
    },
  );

  test('--json prints the answer as JSON', () async {
    final answer = {
      'paused': false,
      'busy': true,
      'jobs': [
        _job(1, 'RUNNING'),
        _job(2, 'DONE', outputPath: '/videos/Converted/clip2.mp4'),
      ],
    };
    await _FakeApp.start(_endpoint, {Methods.queueList: (_, _) => answer});
    for (final args in [
      ['queue', '--json'],
      ['--json', 'queue'],
    ]) {
      final run = await _run(args);
      expect(run.exitCode, 0, reason: run.err);
      expect(jsonDecode(run.out), answer);
      expectMachineJson(jsonDecode(run.out));
    }
  });

  test('a bad argument exits 5 with the message', () async {
    final app = await _FakeApp.start(_endpoint, {
      Methods.queueAdd: (_, _) => throw const ControlError(
        ControlErrorKind.badArgument,
        'There is no goal "x". Goals: archive, smaller.',
      ),
    });
    final run = await _run(['queue', 'add', '1', '--goal', 'x']);
    expect(run.exitCode, ExitCode.badArguments);
    expect(run.err, contains('Goals: archive'));

    final json = await _run(['queue', 'add', '1', '--goal', 'x', '--json']);
    expect(json.exitCode, ExitCode.badArguments);
    expect(jsonDecode(json.err), {
      'error': {
        'code': 'BAD_ARGUMENT',
        'message': 'There is no goal "x". Goals: archive, smaller.',
      },
    });
    expectMachineJson(jsonDecode(json.err));

    // Refused before the window is asked anything.
    final asked = app.calls.length;
    for (final args in [
      ['convert'],
      ['queue', 'add'],
      ['queue', 'add', '1', '--opt', 'speed'],
      ['queue', 'add', '1', '--sample', 'end'],
      ['wait', 'x'],
      ['wait', '--timeout', 'soon'],
      ['remove', 'a.mov', '--loud'],
    ]) {
      final run = await _run(args);
      expect(run.exitCode, ExitCode.badArguments, reason: '$args');
      expect(run.err, isNotEmpty, reason: '$args');
    }
    expect(app.calls.length, asked);
  });

  test('wait exits 1 when a job failed and 0 when all are done', () async {
    var outcomes = [_outcome(1, 'DONE'), _outcome(2, 'FAILED')];
    final app = await _FakeApp.start(_endpoint, {
      Methods.wait: (_, _) => {'outcomes': outcomes},
    });
    final failed = await _run(['wait']);
    expect(failed.exitCode, ExitCode.jobsFailed);
    expect(failed.out, contains('Job 1: Done'));
    expect(failed.out, contains('Job 2: Failed'));

    outcomes = [_outcome(1, 'DONE'), _outcome(2, 'SKIPPED')];
    expect((await _run(['wait', '1', '2'])).exitCode, ExitCode.ok);
    expect(app.paramsOf(Methods.wait), {
      'jobs': [1, 2],
    });

    outcomes = [_outcome(3, 'CANCELLED')];
    expect((await _run(['wait'])).exitCode, ExitCode.jobsFailed);
    // Taken out of the queue is not a failure.
    outcomes = [_outcome(3, 'REMOVED')];
    expect((await _run(['wait'])).exitCode, ExitCode.ok);
  });

  test('wait prints each outcome as it is known', () async {
    final answer = Completer<void>();
    late _FakeApp app;
    app = await _FakeApp.start(_endpoint, {
      Methods.wait: (_, peer) async {
        // As the window does: the waiting client is told the queue is
        // paused, and only subscribed ones are told events.
        peer.notify(Events.queuePaused, const {});
        expect(app.subscribers, hasLength(1));
        expect(app.subscribers.single, isNot(same(peer)));
        for (final subscriber in app.subscribers) {
          subscriber.notify(
            Events.jobFinished,
            _job(1, 'DONE', outputPath: '/videos/Converted/clip1.mp4'),
          );
          subscriber.notify(Events.queuePaused, const {});
        }
        await answer.future;
        return {
          'outcomes': [_outcome(1, 'DONE'), _outcome(2, 'DONE')],
        };
      },
    });
    final out = StringBuffer();
    final err = StringBuffer();
    final running = _run(['wait'], out: out, err: err);
    await _until(() => '$out'.contains('Job 1'));
    expect('$out', isNot(contains('Job 2')));
    answer.complete();
    final run = await running;
    expect(run.exitCode, ExitCode.ok);
    expect('Job 1:'.allMatches(run.out), hasLength(1));
    expect(run.out, contains('Job 2'));
    expect(run.out, contains('/videos/Converted/clip1.mp4'));
    expect(
      'The queue is paused in the window; still waiting.'.allMatches(run.err),
      hasLength(1),
    );
  });

  test('wait exits 4 when the app goes away', () async {
    final app = await _FakeApp.start(_endpoint, {
      Methods.wait: (_, _) => Completer<Object?>().future,
    });
    final running = _run(['wait']);
    await _until(() => app.asked(Methods.wait));
    await app.listener.close(farewell: false);
    final run = await running;
    expect(run.exitCode, ExitCode.appClosed);
    expect(run.err, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('wait --timeout exits 3', () async {
    await _FakeApp.start(_endpoint, {
      Methods.wait: (_, _) => Completer<Object?>().future,
    });
    final watch = Stopwatch()..start();
    final run = await _run(['wait', '--timeout', '0.2']);
    expect(run.exitCode, ExitCode.timeout);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(run.err, isNotEmpty);

    final json = await _run(['wait', '--timeout', '0.2', '--json']);
    expect(json.exitCode, ExitCode.timeout);
    expect(
      (jsonDecode(json.err) as Map)['error'],
      containsPair('code', 'TIMEOUT'),
    );
  });

  test(
    'events prints each event as a JSON line and ends with the app',
    () async {
      late _FakeApp app;
      app = await _FakeApp.start(_endpoint, {
        Methods.subscribe: (params, peer) {
          if (params['snapshot'] == true) {
            peer.notify(Events.snapshot, {
              'time': 't0',
              'videos': <Object?>[],
              'jobs': <Object?>[],
              'paused': false,
              'busy': false,
            });
          }
          Timer(const Duration(milliseconds: 50), () {
            peer.notify(Events.jobFinished, {'time': 't1', ..._job(1, 'DONE')});
            app.listener.close();
          });
          return const <String, Object?>{};
        },
      });
      final run = await _run(['events', '--json']);
      expect(run.exitCode, ExitCode.appClosed);
      final lines = [
        for (final line in const LineSplitter().convert(run.out))
          jsonDecode(line) as Map<String, Object?>,
      ];
      expect(
        [for (final line in lines) line['event']],
        ['SNAPSHOT', 'JOB_FINISHED', 'APP_CLOSING'],
      );
      for (final line in lines) {
        expectMachineJson(line);
      }
      expect(lines[1]['id'], 1);
      expect(lines[1]['time'], 't1');
      expect(app.paramsOf(Methods.subscribe), {'snapshot': true});

      app = await _FakeApp.start(_endpoint, {
        Methods.subscribe: (params, peer) {
          Timer(const Duration(milliseconds: 50), app.listener.close);
          return const <String, Object?>{};
        },
      });
      final sinceNow = await _run(['events', '--since-now']);
      expect(sinceNow.exitCode, ExitCode.appClosed);
      expect(app.paramsOf(Methods.subscribe), {'snapshot': false});
      expect(sinceNow.out, contains('VidCtrl is closing'));
    },
  );

  test('without a running app, --no-start exits 2', () async {
    final launcher = _FakeLauncher();
    final run = await _run(['queue', '--no-start'], launcher: launcher);
    expect(run.exitCode, ExitCode.notRunning);
    expect(run.err, contains('not running'));
    expect(launcher.starts, 0);
  });

  test('without a running app, it starts the window and goes on', () async {
    var statuses = 0;
    final launcher = _FakeLauncher(() async {
      await _FakeApp.start(_endpoint, {
        // Looking for FFmpeg at first.
        Methods.status: (_, _) =>
            _status(++statuses < 3 ? 'STARTING' : 'READY'),
        Methods.queueList: (_, _) => {
          'paused': false,
          'busy': false,
          'jobs': <Object?>[],
        },
      });
    });
    final run = await _run(['queue'], launcher: launcher);
    expect(run.exitCode, ExitCode.ok, reason: run.err);
    expect(launcher.starts, 1);
    expect(run.err, contains('Starting VidCtrl'));
    expect(statuses, 3);
    expect(run.out, contains('The queue is empty'));
  });

  test('a stale endpoint file starts the window', () async {
    final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = gone.port;
    await gone.close();
    await _endpoint.write(
      Endpoint(
        port: deadPort,
        token: 'old',
        pid: pid,
        version: '0.1.0',
        protocol: controlProtocol,
      ),
    );
    final launcher = _FakeLauncher(() async {
      await _FakeApp.start(_endpoint, {
        Methods.queueList: (_, _) => {
          'paused': false,
          'busy': false,
          'jobs': <Object?>[],
        },
      });
    });
    final run = await _run(['queue'], launcher: launcher);
    expect(run.exitCode, ExitCode.ok, reason: run.err);
    expect(launcher.starts, 1);
  });

  test('a file whose window is gone, with another program on its port, '
      'starts the window', () async {
    final other = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(other.close);
    other.listen((socket) => socket.destroy());
    await _endpoint.write(
      Endpoint(
        port: other.port,
        token: 'old',
        pid: 4242,
        version: '0.1.0',
        protocol: controlProtocol,
      ),
    );
    final launcher = _FakeLauncher(() async {
      await _FakeApp.start(_endpoint, {
        Methods.queueList: (_, _) => {
          'paused': false,
          'busy': false,
          'jobs': <Object?>[],
        },
      });
    });
    final run = await _run(
      ['queue'],
      launcher: launcher,
      isAlive: (pid) async => pid != 4242,
    );
    expect(run.exitCode, ExitCode.ok, reason: run.err);
    expect(launcher.starts, 1);
  });

  test('a running window that does not answer exits 2 and starts no '
      'other', () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    final accepted = <Socket>[];
    silent.listen(accepted.add);
    addTearDown(() {
      for (final socket in accepted) {
        socket.destroy();
      }
    });
    await _endpoint.write(
      Endpoint(
        port: silent.port,
        token: 't',
        // This test's own process: running.
        pid: pid,
        version: '0.1.0',
        protocol: controlProtocol,
      ),
    );
    final launcher = _FakeLauncher();
    final run = await _run(['queue'], launcher: launcher);
    expect(run.exitCode, ExitCode.notRunning);
    expect(run.err, contains('running but does not answer'));
    expect(launcher.starts, 0);
  });

  test('a window that cannot be started exits 2', () async {
    final launcher = _FakeLauncher(
      () async => throw const ControlError(
        ControlErrorKind.notRunning,
        'VidCtrl was not found next to vidctrl-client.',
      ),
    );
    final run = await _run(['queue'], launcher: launcher);
    expect(run.exitCode, ExitCode.notRunning);
    expect(run.err, contains('was not found'));
  });

  test(
    'FFmpeg missing exits 6 without waiting for the start timeout',
    () async {
      final launcher = _FakeLauncher(() async {
        await _FakeApp.start(_endpoint, {
          Methods.status: (_, _) => _status('FFMPEG_MISSING'),
        });
      });
      final watch = Stopwatch()..start();
      final run = await _run(['queue'], launcher: launcher);
      expect(run.exitCode, ExitCode.ffmpegMissing);
      expect(run.err, contains('FFmpeg'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test('status without a running app says so and exits 0', () async {
    final launcher = _FakeLauncher();
    final text = await _run(['status'], launcher: launcher);
    expect(text.exitCode, ExitCode.ok);
    expect(text.out.trim(), 'VidCtrl is not running.');
    final json = await _run(['status', '--json'], launcher: launcher);
    expect(json.exitCode, ExitCode.ok);
    expect(jsonDecode(json.out), {'running': false});
    expect(launcher.starts, 0);

    await _FakeApp.start(_endpoint);
    final running = await _run(['status', '--json']);
    expect(jsonDecode(running.out), {'running': true, ..._status('READY')});
  });

  test('--help prints what the commands are', () async {
    final run = await _run(['--help']);
    expect(run.exitCode, ExitCode.ok);
    expect(run.out, usage());
    for (final command in clientCommands) {
      expect(run.out, contains(command));
    }
  });

  test('manual and help need no running app', () async {
    final launcher = _FakeLauncher();
    for (final (args, printed) in [
      (<String>[], quickStart('vidctrl-client', os: Platform.operatingSystem)),
      (['manual'], manual(client: 'vidctrl-client')),
      (['manual', '--json'], '${jsonEncode(manualJson())}\n'),
      (['help'], usage()),
      (['help', 'queue', 'add'], commandHelp('queue add')),
      (['queue', 'add', '--help'], commandHelp('queue add')),
      (['wait', '-h'], commandHelp('wait')),
    ]) {
      final run = await _run(args, launcher: launcher);
      expect(run.exitCode, ExitCode.ok, reason: '$args ${run.err}');
      expect(run.out, printed, reason: '$args');
      expect(run.err, isEmpty, reason: '$args');
    }
    expect(launcher.starts, 0);
    expect(_endpoint.read(), completion(isNull));

    final unknown = await _run(['help', 'convert'], launcher: launcher);
    expect(unknown.exitCode, ExitCode.badArguments);
    expect(unknown.err, contains('queue add'));
  });

  test('a --timeout that is not a finite number is refused', () async {
    final app = await _FakeApp.start(_endpoint, {
      Methods.wait: (_, _) => {'outcomes': <Object?>[]},
    });
    for (final timeout in ['Infinity', '-Infinity', 'NaN', '0', '-1']) {
      final run = await _run(['wait', '--timeout', timeout]);
      expect(run.exitCode, ExitCode.badArguments, reason: timeout);
      expect(run.err, contains('--timeout'), reason: timeout);
    }
    expect(app.asked(Methods.wait), isFalse);
    // A very long one is as good as none.
    final long = await _run(['wait', '--timeout', '1e300']);
    expect(long.exitCode, ExitCode.ok, reason: long.err);
  });

  test('an unexpected error ends in one line, with exit 5', () async {
    await _FakeApp.start(_endpoint, {
      // Not the shape the client reads.
      Methods.queueList: (_, _) => {'jobs': 'none'},
      Methods.wait: (_, _) => {'outcomes': 'none'},
      Methods.subscribe: (_, peer) {
        Timer.run(() => peer.notify(Events.jobFinished, {'id': 'x'}));
        return const <String, Object?>{};
      },
    });
    for (final args in [
      ['queue'],
      ['events'],
      ['wait', '--json'],
    ]) {
      final run = await _run(args);
      expect(run.exitCode, ExitCode.badArguments, reason: '$args');
      expect(run.err.trim().split('\n'), hasLength(1), reason: run.err);
      expect(run.err, isNot(contains('#0')));
      if (args.contains('--json')) {
        expect(
          (jsonDecode(run.err) as Map)['error'],
          containsPair('code', 'UNEXPECTED'),
        );
      } else {
        expect(run.err, contains('unexpected error'));
      }
    }
  });

  test('remove says the file stays on disk, and no output speaks of '
      'deleting', () async {
    late _FakeApp app;
    var following = false;
    app = await _FakeApp.start(_endpoint, {
      ..._resultAnswers,
      Methods.status: (_, _) => {
        ..._status('READY'),
        'busy': true,
        'jobs': {'RUNNING': 1, 'WAITING': 2, 'DONE': 3},
      },
      Methods.goals: (_, _) => {
        'goals': [
          {
            'id': 'archive.master',
            'scenario': 'archive',
            'title': 'Archive',
            'subtitle': 'no quality loss',
            'options': [
              {
                'id': 'codec',
                'title': 'Format',
                'defaultChoice': 'av1',
                'advanced': false,
                'choices': [
                  {'id': 'av1', 'label': 'Smallest file', 'hint': 'Slower.'},
                  {'id': 'hevc', 'label': 'Plays everywhere', 'hint': ''},
                ],
              },
            ],
          },
        ],
      },
      Methods.videosAdd: (_, _) => {
        'videos': [
          {'path': '/videos/a.mov', 'id': 1, 'result': 'ADDED'},
          {'path': '/videos/b.mov', 'id': 2, 'result': 'KNOWN'},
          {'path': '/videos/c.txt', 'id': 3, 'result': 'UNREADABLE'},
          {'path': '/videos/none', 'result': 'NOT_FOUND'},
        ],
      },
      Methods.videosList: (_, _) => {
        'videos': [
          {
            'id': 1,
            'path': '/videos/a.mov',
            'status': 'READY',
            'sizeBytes': 1500000000,
            'durationSeconds': 754.2,
            'width': 3840,
            'height': 2160,
            'videoCodec': 'hevc',
            'audioCodecs': ['aac'],
            'hdr': true,
            'preview': {
              'goal': 'archive.master',
              'plan': 'ENCODE',
              'expectedBytes': 400000000,
              'measured': true,
              'measuring': false,
              'closeness': 'SAME',
            },
          },
          {
            'id': 3,
            'path': '/videos/c.txt',
            'status': 'UNREADABLE',
            'audioCodecs': <String>[],
            'hdr': false,
          },
        ],
      },
      Methods.videosRemove: (_, _) => {
        'removed': [1, 2],
      },
      Methods.queueList: (_, _) => {
        'paused': true,
        'busy': true,
        'jobs': [
          {
            ..._job(1, 'RUNNING'),
            'fraction': .42,
            'remainingSeconds': 200.0,
            'attempt': 2,
          },
          {
            ..._job(2, 'DONE', outputPath: '/videos/Converted/clip2.mp4'),
            'outputBytes': 1000000,
            'sample': 'MIDDLE',
            'quality': {
              'outcome': 'BELOW_TARGET',
              'value': 20,
              'standardValue': 35,
              'vmaf': 93.1,
              'share': .4,
            },
            'needsALook': true,
          },
          {
            ..._job(3, 'FAILED'),
            'errorLines': ['Conversion failed!'],
          },
        ],
      },
      Methods.queueAdd: (_, _) => {
        'goal': 'archive.master',
        'options': {'codec': 'av1'},
        'added': [_job(4, 'WAITING')],
        'alreadyQueued': [2],
        'skipped': [
          {'video': '/videos/none', 'reason': 'NOT_FOUND'},
          {'video': 3, 'reason': 'UNREADABLE'},
        ],
      },
      Methods.queueRemove: (_, _) => {
        'removed': [1],
      },
      Methods.queueClearFinished: (_, _) => {
        'removed': [2],
      },
      Methods.queueMove: (_, _) => {
        'jobs': [_job(1, 'WAITING')],
      },
      Methods.queueRetry: (_, _) => {'job': _job(3, 'WAITING')},
      Methods.queuePause: (_, _) => {'paused': true},
      Methods.queueResume: (_, _) => {'paused': false},
      Methods.queueCancel: (_, _) => {'cancelled': null},
      Methods.queueConvertAnyway: (_, _) => {
        'added': [_job(4, 'WAITING')],
        'alreadyQueued': false,
      },
      Methods.queueConvertWhole: (_, _) => {
        'added': <Object?>[],
        'alreadyQueued': true,
      },
      Methods.wait: (_, _) => {
        'outcomes': [
          _outcome(1, 'DONE', needsALook: true),
          _outcome(2, 'REMOVED'),
          _outcome(3, 'CANCELLED'),
        ],
      },
      Methods.subscribe: (_, peer) {
        // `wait` follows the events too; only `events` is told these.
        if (!following) return const <String, Object?>{};
        for (final (event, params) in [
          (Events.videoAdded, {'id': 1, 'path': '/videos/a.mov'}),
          (Events.videoRemoved, {'video': 1}),
          (Events.jobAdded, _job(1, 'WAITING')),
          (Events.jobChecking, {'job': 1, 'attempt': 1}),
          (Events.jobProgress, {'job': 1, 'fraction': .5}),
          (Events.jobFinished, _job(1, 'FAILED')),
          (Events.jobRemoved, {'job': 1}),
          (Events.queueIdle, const <String, Object?>{}),
          (
            Events.compareFinished,
            {'job': 1, 'status': 'MEASURED', 'closeness': 'SAME', 'xpsnr': 42},
          ),
        ]) {
          peer.notify(event, {'time': 't', ...params});
        }
        Timer(const Duration(milliseconds: 50), app.listener.close);
        return const <String, Object?>{};
      },
    });
    final printed = StringBuffer();
    for (final args in [
      ['status'],
      ['goals'],
      ['add', '/videos'],
      ['videos', '--goal', 'archive.master'],
      ['remove', '1', '/videos/b.mov'],
      ['queue'],
      ['queue', 'add', '1', '2', '3', '/videos/none'],
      ['queue', 'remove', '1'],
      ['queue', 'clear-finished'],
      ['queue', 'move', '1', '1'],
      ['queue', 'retry', '3'],
      ['queue', 'convert-anyway', '2'],
      ['queue', 'convert-whole', '2'],
      ['pause'],
      ['resume'],
      ['cancel'],
      ['job', '2', '--command'],
      ['compare', '2'],
      ['compare', '2', '--no-wait'],
      ['details', '1'],
      ['details', '--job', '2'],
      ['details', '1', '--raw'],
      ['estimate', '1', '--goal', 'archive'],
      ['wait'],
      ['events', '--since-now'],
    ]) {
      following = args.first == 'events';
      final run = await _run(args);
      expect(run.exitCode, isNot(ExitCode.badArguments), reason: run.err);
      if (args.contains('remove') || args.contains('clear-finished')) {
        expect(run.out, contains('stays on disk'));
      }
      if (args.first == 'remove') {
        expect(app.paramsOf(Methods.videosRemove), {
          'videos': [1, '/videos/b.mov'],
        });
      }
      printed
        ..writeln(run.out)
        ..writeln(run.err);
    }
    expect(speaksOfDeleting('$printed'), isFalse, reason: '$printed');
    // People see the ids to refer to, and plain words first.
    expect('$printed', contains('Job 2'));
    expect('$printed', contains('Video 1'));
    expect('$printed', contains('Smallest file: av1 (the default)'));
    // The goal's only kind goes by the kind's name.
    expect('$printed', contains('--goal archive\n'));
    expect('$printed', contains('Looks the same as the original'));
  });
}
