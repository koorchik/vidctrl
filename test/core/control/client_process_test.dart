import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/listener.dart';
import 'package:vidctrl/core/control/protocol.dart';

void main() {
  test('the compiled entry point runs as a process', () async {
    final dir = await Directory.systemTemp.createTemp('client_process');
    addTearDown(() => dir.delete(recursive: true));
    const status = {
      'state': 'ready',
      'version': '0.1.0',
      'busy': false,
      'paused': false,
      'jobs': <String, int>{},
    };
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => status,
    );
    addTearDown(listener.close);
    final file = EndpointFile(p.join(dir.path, 'control.json'));
    await file.write(
      Endpoint(
        port: listener.port,
        token: 't',
        pid: pid,
        version: '0.1.0',
        protocol: controlProtocol,
      ),
    );
    final result = await Process.run(
      'dart',
      ['run', 'bin/vidctrl_client.dart', 'status', '--json'],
      environment: {'VIDCTRL_ENDPOINT': file.path},
      runInShell: Platform.isWindows,
    );
    expect(result.exitCode, ExitCode.ok, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), {'running': true, ...status});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a reader that stops reading ends events quietly', () async {
    final dir = await Directory.systemTemp.createTemp('client_process');
    addTearDown(() => dir.delete(recursive: true));
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async {
        if (method == Methods.subscribe) {
          // Far more than a reader that wants one line takes.
          final timer = Timer.periodic(
            const Duration(milliseconds: 5),
            (_) => peer.notify(Events.queueIdle, const {}),
          );
          unawaited(peer.closed.then((_) => timer.cancel()));
          return const <String, Object?>{};
        }
        return {
          'state': 'ready',
          'version': '0.1.0',
          'busy': false,
          'paused': false,
          'jobs': <String, int>{},
        };
      },
    );
    addTearDown(listener.close);
    final file = EndpointFile(p.join(dir.path, 'control.json'));
    await file.write(
      Endpoint(
        port: listener.port,
        token: 't',
        pid: pid,
        version: '0.1.0',
        protocol: controlProtocol,
      ),
    );
    final process = await Process.start(
      'dart',
      ['run', 'bin/vidctrl_client.dart', 'events', '--since-now'],
      environment: {'VIDCTRL_ENDPOINT': file.path},
      runInShell: Platform.isWindows,
    );
    final err = StringBuffer();
    final errDone = process.stderr.transform(utf8.decoder).forEach(err.write);
    final firstLine = Completer<void>();
    late final StreamSubscription<List<int>> reading;
    reading = process.stdout.listen((_) {
      if (!firstLine.isCompleted) firstLine.complete();
    });
    await firstLine.future;
    // As `head -1` does once it has its line.
    await reading.cancel();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await errDone;
    expect(code, ExitCode.ok, reason: '$err');
    expect('$err', isNot(contains('Broken pipe')));
    expect('$err', isNot(contains('#0')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
