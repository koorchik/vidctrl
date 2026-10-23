import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'client_text.dart';
import 'connection.dart';
import 'endpoint.dart';
import 'launcher.dart';
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
  'wait',
  'events',
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
    this.startTimeout = const Duration(seconds: 30),
  }) : launcher =
           launcher ??
           AppLauncher(
             os: Platform.operatingSystem,
             clientExecutable: executable,
             environment: environment,
           ),
       endpoint =
           endpoint ?? EndpointFile.forThisUser(environment: environment);

  final StringSink out;
  final StringSink err;
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

/// Runs the command [args] names and returns the code to exit with.
Future<int> runClient(List<String> args, ClientIo io) async {
  final output = _Output(io, json: args.contains('--json'));
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
    io.out.write(_usage);
    return ExitCode.ok;
  }
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
/// no window is open.
class _Command {
  _Command(this.name, this.run);

  final String name;
  final Future<int> Function(ControlConnection? connection, _Output output) run;
}

// ---- Parsing -----------------------------------------------------------

ArgParser _withGlobals(ArgParser parser) => parser
  ..addFlag('json', negatable: false, help: 'Print the answer as JSON.')
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
    ..addCommand('wait', _withGlobals(ArgParser())..addOption('timeout'))
    ..addCommand(
      'events',
      _withGlobals(ArgParser())..addFlag('since-now', negatable: false),
    );
}

const _usage = '''
vidctrl-client adds videos to the open VidCtrl window and follows its queue.

  status               whether VidCtrl is open, and how its queue stands
  goals                the goals and their options
  add <paths…>         adds videos to the list, as dropping them does
                       (--no-wait: do not wait until each has been read)
  videos               the videos in the list (--goal g --opt option=choice:
                       what that goal would do to each)
  remove <videos…>     takes videos off the list; the files stay on disk
  queue                the jobs in the queue
  queue add <videos…>  queues videos (--goal, --opt, --sample start|middle,
                       --out next|<folder>, --subfolder Name)
  wait [jobs…]         waits until the jobs are finished (--timeout seconds)
  events               tells what happens in the window as it happens
                       (--since-now: without how things stand first)

Videos are given by their number or their path, jobs by their number.
Every command takes --json, and --no-start not to start VidCtrl.
''';

_Command? _command(ArgResults top, ClientIo io) {
  final command = top.command;
  if (command == null) {
    if (top.rest.isNotEmpty) {
      throw _bad('There is no command "${top.rest.first}".');
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
      final add = command.command;
      if (add == null) {
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
    case 'wait':
      final jobs = [
        for (final job in args)
          int.tryParse(job) ??
              (throw _bad('wait takes job numbers, not "$job".')),
      ];
      final timeout = command.option('timeout');
      final seconds = timeout == null ? null : double.tryParse(timeout);
      if (timeout != null && (seconds == null || seconds <= 0)) {
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
              : Duration(milliseconds: (seconds * 1000).round()),
        ),
      );
    case 'events':
      noArguments();
      return _Command(
        'events',
        (c, o) => _events(c!, o, sinceNow: command.flag('since-now')),
      );
  }
  throw _bad('There is no command "${command.name}".');
}

ControlError _bad(String message) =>
    ControlError(ControlErrorKind.badArgument, message);

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
  final home = Platform.isWindows
      ? io.environment['USERPROFILE']
      : io.environment['HOME'];
  final tilde =
      path == '~' ||
      path.startsWith('~/') ||
      Platform.isWindows && path.startsWith(r'~\');
  if (home != null && tilde) {
    path = p.join(home, path.length > 2 ? path.substring(2) : '');
  }
  return p.normalize(p.join(io.workingDirectory, path));
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
