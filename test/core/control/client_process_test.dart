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
}
