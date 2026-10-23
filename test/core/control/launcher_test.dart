import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/control/launcher.dart';
import 'package:vidctrl/core/control/protocol.dart';

void main() {
  late String dir;

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('launcher');
    addTearDown(() => temp.delete(recursive: true));
    dir = temp.path;
  });

  AppLauncher launcher(
    String os,
    String client, [
    Map<String, String> environment = const {},
  ]) => AppLauncher(os: os, clientExecutable: client, environment: environment);

  test('the app is found beside the client on each system', () {
    final client = p.join(dir, 'vidctrl-client');
    expect(launcher('linux', client).appPath, isNull);
    File(p.join(dir, 'vidctrl')).createSync();
    expect(launcher('linux', client).appPath, p.join(dir, 'vidctrl'));

    final windowsClient = p.join(dir, 'vidctrl-client.exe');
    expect(launcher('windows', windowsClient).appPath, isNull);
    File(p.join(dir, 'vidctrl.exe')).createSync();
    expect(
      launcher('windows', windowsClient).appPath,
      p.join(dir, 'vidctrl.exe'),
    );

    final bundle = p.join(dir, 'VidCtrl.app');
    final macClient = p.join(bundle, 'Contents', 'MacOS', 'vidctrl-client');
    Directory(p.dirname(macClient)).createSync(recursive: true);
    expect(launcher('macos', macClient).appPath, bundle);
    // Not inside an app bundle: nothing to open.
    expect(launcher('macos', client).appPath, isNull);
  });

  test('VIDCTRL_APP wins', () {
    File(p.join(dir, 'vidctrl')).createSync();
    final own = p.join(dir, 'build', 'vidctrl');
    expect(
      launcher('linux', p.join(dir, 'vidctrl-client'), {
        'VIDCTRL_APP': own,
      }).appPath,
      own,
    );
  });

  test('without an app, starting says where it was looked for', () async {
    await expectLater(
      launcher('linux', p.join(dir, 'vidctrl-client')).start(),
      throwsA(
        isA<ControlError>()
            .having((e) => e.kind.exitCode, 'exit code', ExitCode.notRunning)
            .having((e) => e.message, 'message', contains('VIDCTRL_APP')),
      ),
    );
    final missing = p.join(dir, 'missing');
    await expectLater(
      launcher('linux', p.join(dir, 'vidctrl-client'), {
        'VIDCTRL_APP': missing,
      }).start(),
      throwsA(
        isA<ControlError>().having(
          (e) => e.message,
          'message',
          contains(missing),
        ),
      ),
    );
  });
}
