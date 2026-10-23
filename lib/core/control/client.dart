import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'client_text.dart';
import 'connection.dart';
import 'endpoint.dart';
import 'launcher.dart';
import 'manual.dart';
import 'protocol.dart';
import 'views.dart';

// `vidctrl-client`: reads the command line, finds or starts the window,
// asks it one thing (or follows it), prints the answer and says by its exit
// code how it went.

/// The commands the client knows, as typed.
const clientCommands = <String>[
  'status',
  'goals',
  'add',
  'videos',
  'remove',
  'queue',
  'queue add',
  'queue remove',
  'queue move',
  'queue retry',
  'queue clear-finished',
  'queue convert-anyway',
  'queue convert-whole',
  'pause',
  'resume',
  'cancel',
  'wait',
  'events',
  'manual',
  'help',
];

/// What the client reads and writes, so tests can stand in for the
/// terminal, the window and the system.
class ClientIo {
  ClientIo({
    required this.out,
    required this.err,
    required this.environment,
    required this.workingDirectory,
    required this.executable,
    AppLauncher? launcher,
    EndpointFile? endpoint,
    String? os,
    this.startTimeout = const Duration(seconds: 30),
  }) : os = os ?? Platform.operatingSystem,
       launcher =
           launcher ??
           AppLauncher(
             os: os ?? Platform.operatingSystem,
             clientExecutable: executable,
             environment: environment,
           ),
       endpoint =
           endpoint ?? EndpointFile.forThisUser(environment: environment);

  final StringSink out;
  final StringSink err;

  /// A `Platform.operatingSystem` value: how paths are written.
  final String os;
  final Map<String, String> environment;

  /// Relative paths on the command line are taken from here.
  final String workingDirectory;

  /// The client's own path, links followed: the window is found beside it.
  final String executable;
  final AppLauncher launcher;
  final EndpointFile endpoint;

  /// How long a window that was started has to answer.
  final Duration startTimeout;
}

const _pollEvery = Duration(milliseconds: 250);

/// Runs the command [args] names and returns the code to exit with. An
/// error nobody expected ends it with one line on stderr, not a trace.
Future<int> runClient(List<String> args, ClientIo io) {
  final output = _Output(io, json: args.contains('--json'));
  final code = Completer<int>();
  void end(int exitCode) {
    if (!code.isCompleted) code.complete(exitCode);
  }

  runZonedGuarded(() async => end(await _runClient(args, io, output)), (
    error,
    _,
  ) {
    if (code.isCompleted) return;
    final first = '$error'.split('\n').first;
    end(
      output.failWith(
        'unexpected',
        'vidctrl-client stopped on an unexpected error: $first',
        ExitCode.badArguments,
      ),
    );
  });
  return code.future;
}

Future<int> _runClient(List<String> args, ClientIo io, _Output output) async {
  final ArgResults top;
  final _Command? command;
  try {
    top = _parser().parse(args);
    command = _command(top, io);
  } on FormatException catch (e) {
    return output.fail(ControlError(ControlErrorKind.badArgument, e.message));
  } on ControlError catch (e) {
    return output.fail(e);
  }
  if (command == null) {
    io.out.write(quickStart('vidctrl-client'));
    return ExitCode.ok;
  }
  if (command.offline) return command.run(null, output);
  final noStart = [
    top,
    ?top.command,
    ?top.command?.command,
  ].any((results) => results.flag('no-start'));

  ControlConnection? connection;
  try {
    connection = await connectIfLive(io.endpoint);
    if (connection == null && command.name != 'status') {
      if (noStart) {
        throw const ControlError(
          ControlErrorKind.notRunning,
          'VidCtrl is not running; start it, or leave out --no-start.',
        );
      }
      connection = await _start(io);
    }
    return await command.run(connection, output);
  } on ControlError catch (e) {
    return output.fail(e);
  } finally {
    await connection?.close();
  }
}

/// Starts the window and waits until it has looked for FFmpeg.
Future<ControlConnection> _start(ClientIo io) async {
  io.err.writeln('Starting VidCtrl…');
  await io.launcher.start();
  final deadline = DateTime.now().add(io.startTimeout);
  bool overdue() => DateTime.now().isAfter(deadline);
  ControlConnection? connection;
  while ((connection = await connectIfLive(io.endpoint)) == null) {
    if (overdue()) {
      throw ControlError(
        ControlErrorKind.notRunning,
        'VidCtrl did not answer within ${io.startTimeout.inSeconds} seconds '
        'of being started.',
      );
    }
    await Future<void>.delayed(_pollEvery);
  }
  try {
    while (true) {
      final status = StatusView.fromJson(
        _object(await connection!.call(Methods.status)),
      );
      if (status.state == 'ffmpegMissing') {
        throw const ControlError(
          ControlErrorKind.ffmpegMissing,
          'VidCtrl could not find FFmpeg; the window says what to do.',
        );
      }
      // Still starting after all that: the window holds the request until
      // it is ready.
      if (status.state != 'starting' || overdue()) return connection;
      await Future<void>.delayed(_pollEvery);
    }
  } on Object {
    await connection!.close();
    rethrow;
  }
}

/// Prints for people, or as JSON with `--json`.
class _Output {
  _Output(this.io, {required this.json});

  final ClientIo io;
  final bool json;

  /// [answer] as one JSON document, or [text] for people.
  void answer(Object? answer, List<String> Function() text) {
    if (json) {
      io.out.writeln(jsonEncode(answer));
    } else {
      lines(text());
    }
  }

  void lines(List<String> lines) {
    for (final line in lines) {
      io.out.writeln(line);
    }
  }

  /// Something to know on the side, on stderr.
  void note(String text) => io.err.writeln(text);

  int fail(ControlError e) => failWith(e.kind.name, e.message, e.kind.exitCode);

  int failWith(String kind, String message, int exitCode) {
    io.err.writeln(
      json
          ? jsonEncode({
              'error': {'kind': kind, 'message': message},
            })
          : message,
    );
    return exitCode;
  }
}

/// A command ready to run: [run] gets no connection only for `status` when
/// no window is open, and for an [offline] one.
class _Command {
  _Command(this.name, this.run) : offline = false;

  /// Prints [text] and needs no window.
  _Command.text(this.name, String text)
    : offline = true,
      run = ((_, output) async {
        output.io.out.write(text);
        return ExitCode.ok;
      });

  final String name;
  final Future<int> Function(ControlConnection? connection, _Output output) run;

  /// Answers without the window: it is neither asked nor opened.
  final bool offline;
}

// ---- Parsing -----------------------------------------------------------

ArgParser _withGlobals(ArgParser parser) => parser
  ..addFlag('json', negatable: false, help: 'Print the answer as JSON.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Print the guide.')
  ..addFlag(
    'no-start',
    negatable: false,
    help: 'Do not start VidCtrl when it is not running.',
  );

ArgParser _withGoal(ArgParser parser) => parser
  ..addOption('goal', help: 'A goal id, as `goals` lists them.')
  ..addMultiOption(
    'opt',
    splitCommas: false,
    help: 'An option of the goal: option=choice.',
  );

ArgParser _parser() {
  final queue = _withGlobals(ArgParser())
    ..addCommand(
      'add',
      _withGoal(_withGlobals(ArgParser()))
        ..addOption('sample', allowed: ['start', 'middle'])
        ..addOption('out')
        ..addOption('subfolder'),
    );
  for (final control in _queueControls.keys) {
    queue.addCommand(control, _withGlobals(ArgParser()));
  }
  return _withGlobals(ArgParser())
    ..addCommand('status', _withGlobals(ArgParser()))
    ..addCommand('goals', _withGlobals(ArgParser()))
    ..addCommand(
      'add',
      _withGlobals(ArgParser())..addFlag('wait', defaultsTo: true),
    )
    ..addCommand('videos', _withGoal(_withGlobals(ArgParser())))
    ..addCommand('remove', _withGlobals(ArgParser()))
    ..addCommand('queue', queue)
    ..addCommand('pause', _withGlobals(ArgParser()))
    ..addCommand('resume', _withGlobals(ArgParser()))
    ..addCommand('cancel', _withGlobals(ArgParser()))
    ..addCommand('wait', _withGlobals(ArgParser())..addOption('timeout'))
    ..addCommand(
      'events',
      _withGlobals(ArgParser())..addFlag('since-now', negatable: false),
    )
    ..addCommand('manual', _withGlobals(ArgParser()))
    ..addCommand('help', _withGlobals(ArgParser()));
}

_Command? _command(ArgResults top, ClientIo io) {
  final command = top.command;
  // `--help` after a command gives that command's part of the manual.
  final asked = [top, ?command, ?command?.command];
  if (asked.any((results) => results.flag('help'))) {
    final name = [for (final r in asked.skip(1)) r.name].join(' ');
    return name.isEmpty
        ? _Command.text('help', usage())
        : _Command.text('help', commandHelp(name));
  }
  if (command == null) {
    if (top.rest.isNotEmpty) {
      throw _bad(
        'There is no command "${top.rest.first}". Run `vidctrl-client '
        '--help` for the commands.',
      );
    }
    return null;
  }
  final args = command.rest;
  void noArguments() {
    if (args.isNotEmpty) {
      throw _bad('${command.name} takes no "${args.first}".');
    }
  }

  List<String> some(String what) {
    if (args.isEmpty) throw _bad('${command.name} needs $what.');
    return args;
  }

  switch (command.name) {
    case 'status':
      noArguments();
      return _Command('status', _status);
    case 'goals':
      noArguments();
      return _Command(
        'goals',
        (c, o) => _call(c!, o, Methods.goals, const {}, (a) {
          final goals = [
            for (final g in a['goals'] as List) GoalView.fromJson(_object(g)),
          ];
          return goalsText(goals);
        }),
      );
    case 'add':
      final paths = [for (final path in some('paths')) _absolute(path, io)];
      return _Command(
        'add',
        (c, o) => _call(c!, o, Methods.videosAdd, {
          'paths': paths,
          'wait': command.flag('wait'),
        }, (a) => [for (final v in a['videos'] as List) addedText(_object(v))]),
      );
    case 'videos':
      noArguments();
      final goal = _goalParams(command);
      return _Command(
        'videos',
        (c, o) => _call(c!, o, Methods.videosList, goal, (a) {
          final videos = [
            for (final v in a['videos'] as List) VideoView.fromJson(_object(v)),
          ];
          if (videos.isEmpty) return ['There are no videos in the list.'];
          return [for (final video in videos) ...videoText(video)];
        }),
      );
    case 'remove':
      final videos = [for (final v in some('videos')) _video(v, io)];
      return _Command(
        'remove',
        (c, o) => _call(c!, o, Methods.videosRemove, {'videos': videos}, (a) {
          return [
            for (final id in a['removed'] as List) removedText(id as int),
          ];
        }),
      );
    case 'queue':
      final sub = command.command;
      if (sub == null) {
        noArguments();
        return _Command(
          'queue',
          (c, o) => _call(c!, o, Methods.queueList, const {}, (a) {
            final jobs = [
              for (final j in a['jobs'] as List) JobView.fromJson(_object(j)),
            ];
            return queueText(a['busy'] == true, a['paused'] == true, jobs);
          }),
        );
      }
      if (sub.name != 'add') return _queueControl(sub);
      final add = sub;
      if (add.rest.isEmpty) throw _bad('queue add needs videos.');
      final out = add.option('out');
      final params = {
        'videos': [for (final v in add.rest) _video(v, io)],
        ..._goalParams(add),
        'sample': ?add.option('sample'),
        'out': ?(out == null || out == 'next' ? out : _absolute(out, io)),
        'subfolder': ?add.option('subfolder'),
      };
      return _Command(
        'queue add',
        (c, o) => _call(c!, o, Methods.queueAdd, params, queueAddText),
      );
    case 'pause' || 'resume':
      noArguments();
      return _Command(
        command.name!,
        (c, o) => _call(
          c!,
          o,
          command.name == 'pause' ? Methods.queuePause : Methods.queueResume,
          const {},
          (a) => [pausedText(paused: a['paused'] == true)],
        ),
      );
    case 'cancel':
      if (args.length > 1) throw _bad('cancel takes one job at most.');
      final job = args.isEmpty ? null : _jobId(args.single, 'cancel');
      return _Command(
        'cancel',
        (c, o) => _call(c!, o, Methods.queueCancel, {
          'job': ?job,
        }, (a) => [cancelledText(a['cancelled'] as int?)]),
      );
    case 'wait':
      final jobs = [
        for (final job in args)
          int.tryParse(job) ??
              (throw _bad('wait takes job numbers, not "$job".')),
      ];
      final timeout = command.option('timeout');
      final seconds = timeout == null ? null : double.tryParse(timeout);
      if (timeout != null &&
          (seconds == null || !seconds.isFinite || seconds <= 0)) {
        throw _bad('--timeout takes a number of seconds, not "$timeout".');
      }
      return _Command(
        'wait',
        (c, o) => _wait(
          c!,
          o,
          io.endpoint,
          jobs: jobs.isEmpty ? null : jobs,
          timeout: seconds == null
              ? null
              // Longer than that is as good as no limit, and fits a Duration.
              : Duration(milliseconds: (min(seconds, 1e9) * 1000).round()),
        ),
      );
    case 'events':
      noArguments();
      return _Command(
        'events',
        (c, o) => _events(c!, o, sinceNow: command.flag('since-now')),
      );
    case 'manual':
      noArguments();
      return _Command.text(
        'manual',
        top.flag('json') || command.flag('json')
            ? '${jsonEncode(manualJson())}\n'
            : manual(client: 'vidctrl-client'),
      );
    case 'help':
      final name = args.join(' ');
      if (name.isEmpty) return _Command.text('help', usage());
      if (!clientCommands.contains(name)) {
        throw _bad(
          'There is no command "$name". Commands: '
          '${clientCommands.join(', ')}.',
        );
      }
      return _Command.text('help', commandHelp(name));
  }
  throw _bad('There is no command "${command.name}".');
}

ControlError _bad(String message) =>
    ControlError(ControlErrorKind.badArgument, message);

/// The commands under `queue` that act on jobs already there: the window's
/// method for each, and how its answer reads.
final _queueControls =
    <
      String,
      ({String method, List<String> Function(Map<String, Object?> answer) text})
    >{
      'remove': (
        method: Methods.queueRemove,
        text: (a) => [
          for (final id in a['removed'] as List) takenOutText(id as int),
        ],
      ),
      'move': (
        method: Methods.queueMove,
        text: (a) => movedText([
          for (final j in a['jobs'] as List) JobView.fromJson(_object(j)),
        ]),
      ),
      'retry': (
        method: Methods.queueRetry,
        text: (a) => [retriedText(JobView.fromJson(_object(a['job'])))],
      ),
      'clear-finished': (
        method: Methods.queueClearFinished,
        text: (a) =>
            clearedText([for (final id in a['removed'] as List) id as int]),
      ),
      'convert-anyway': (
        method: Methods.queueConvertAnyway,
        text: addedJobText,
      ),
      'convert-whole': (method: Methods.queueConvertWhole, text: addedJobText),
    };

/// `queue remove`, `queue move` and the others in [_queueControls].
_Command _queueControl(ArgResults sub) {
  final name = 'queue ${sub.name}';
  final control = _queueControls[sub.name]!;
  final args = sub.rest;
  final Map<String, Object?> params;
  switch (sub.name) {
    case 'remove':
      if (args.isEmpty) throw _bad('$name needs job numbers.');
      params = {
        'jobs': [for (final job in args) _jobId(job, name)],
      };
    case 'move':
      if (args.length != 2) throw _bad('$name takes a job and a position.');
      final position = int.tryParse(args.last);
      if (position == null) {
        throw _bad(
          '$name takes a position in the queue, 1 for the first; not '
          '"${args.last}".',
        );
      }
      params = {'job': _jobId(args.first, name), 'position': position};
    case 'clear-finished':
      if (args.isNotEmpty) throw _bad('$name takes no "${args.first}".');
      params = const {};
    default:
      if (args.length != 1) throw _bad('$name takes one job number.');
      params = {'job': _jobId(args.single, name)};
  }
  return _Command(
    name,
    (c, o) => _call(c!, o, control.method, params, control.text),
  );
}

int _jobId(String job, String command) => RegExp(r'^\d+$').hasMatch(job)
    ? int.parse(job)
    : throw _bad('$command takes job numbers, not "$job".');

/// `goal` and `options` for the window, from `--goal` and `--opt`.
Map<String, Object?> _goalParams(ArgResults results) {
  final options = <String, String>{};
  for (final opt in results.multiOption('opt')) {
    final at = opt.indexOf('=');
    if (at <= 0) {
      throw _bad(
        '--opt takes option=choice, as in --opt speed=fast; not "$opt".',
      );
    }
    options[opt.substring(0, at)] = opt.substring(at + 1);
  }
  return {
    'goal': ?results.option('goal'),
    if (options.isNotEmpty) 'options': options,
  };
}

/// A video's number, or its path made absolute.
Object _video(String reference, ClientIo io) =>
    RegExp(r'^\d+$').hasMatch(reference)
    ? int.parse(reference)
    : _absolute(reference, io);

/// [path] from the working directory, with `~` for the home folder.
String _absolute(String path, ClientIo io) {
  final windows = io.os == 'windows';
  final paths = windows ? p.windows : p.posix;
  final home = io.environment[windows ? 'USERPROFILE' : 'HOME'];
  final tilde =
      path == '~' || path.startsWith('~/') || windows && path.startsWith(r'~\');
  if (home != null && tilde) {
    path = paths.join(home, path.length > 2 ? path.substring(2) : '');
  }
  return paths.normalize(paths.join(io.workingDirectory, path));
}

Map<String, Object?> _object(Object? value) =>
    Map<String, Object?>.from(value as Map);

// ---- Running -----------------------------------------------------------

/// Asks [method] and prints the answer, with [text] for people.
Future<int> _call(
  ControlConnection connection,
  _Output output,
  String method,
  Map<String, Object?> params,
  List<String> Function(Map<String, Object?> answer) text,
) async {
  final answer = _object(await connection.call(method, params));
  output.answer(answer, () => text(answer));
  return ExitCode.ok;
}

Future<int> _status(ControlConnection? connection, _Output output) async {
  if (connection == null) {
    output.answer({'running': false}, () => ['VidCtrl is not running.']);
    return ExitCode.ok;
  }
  final answer = _object(await connection.call(Methods.status));
  output.answer({
    'running': true,
    ...answer,
  }, () => statusText(StatusView.fromJson(answer)));
  return ExitCode.ok;
}

/// Waits for the jobs and prints how each ended as soon as it is known. A
/// second connection follows the events, so each result is printed when it
/// comes, not only once the last is in.
Future<int> _wait(
  ControlConnection connection,
  _Output output,
  EndpointFile endpoint, {
  required List<int>? jobs,
  required Duration? timeout,
}) async {
  final printed = <int>{};
  var toldPaused = false;
  void onEvent(ControlNotification event) {
    switch (event.method) {
      case Events.queuePaused when !toldPaused:
        toldPaused = true;
        output.note('The queue is paused in the window; still waiting.');
      case Events.jobFinished when !output.json:
        final job = JobView.fromJson(event.params);
        if ((jobs == null || jobs.contains(job.id)) && printed.add(job.id)) {
          output.lines(finishedText(job));
        }
    }
  }

  final listening = [connection.notifications.listen(onEvent)];
  ControlConnection? events;
  if (!output.json) {
    events = await connectIfLive(endpoint);
    if (events != null) {
      listening.add(events.notifications.listen(onEvent));
      try {
        await events.call(Methods.subscribe, {'snapshot': false});
      } on ControlError {
        // Then the results come with the answer.
      }
    }
  }
  try {
    var answer = connection.call(Methods.wait, {'jobs': ?jobs});
    if (timeout != null) answer = answer.timeout(timeout);
    final Map<String, Object?> result;
    try {
      result = _object(await answer);
    } on TimeoutException {
      return output.failWith(
        'timeout',
        'Still waiting after ${timeout!.inMilliseconds / 1000} seconds; the '
            'jobs go on in the window.',
        ExitCode.timeout,
      );
    }
    final outcomes = [
      for (final o in result['outcomes'] as List)
        JobOutcome.fromJson(_object(o)),
    ];
    output.answer(result, () {
      final failed = outcomes
          .where((o) => o.status == 'failed' || o.status == 'cancelled')
          .length;
      return [
        for (final outcome in outcomes)
          if (printed.add(outcome.jobId)) ...outcomeText(outcome),
        if (outcomes.isEmpty)
          'No job was waiting.'
        else if (failed > 0)
          '$failed of ${outcomes.length} failed or were cancelled.'
        else
          'All done.',
      ];
    });
    return outcomes.any((o) => o.status == 'failed' || o.status == 'cancelled')
        ? ExitCode.jobsFailed
        : ExitCode.ok;
  } finally {
    for (final subscription in listening) {
      unawaited(subscription.cancel());
    }
    await events?.close();
  }
}

/// Prints every event until the window closes.
Future<int> _events(
  ControlConnection connection,
  _Output output, {
  required bool sinceNow,
}) async {
  final ended = Completer<void>();
  var closing = false;
  connection.notifications.listen((event) {
    if (event.method == Events.appClosing) closing = true;
    if (output.json) {
      output.io.out.writeln(
        jsonEncode({'event': event.method, ...event.params}),
      );
    } else {
      output.lines(eventText(event.method, event.params));
    }
  }, onDone: ended.complete);
  await connection.call(Methods.subscribe, {'snapshot': !sinceNow});
  await ended.future;
  if (!closing) output.note('The connection to VidCtrl ended.');
  return ExitCode.appClosed;
}
