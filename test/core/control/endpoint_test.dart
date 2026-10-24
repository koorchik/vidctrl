import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/control/endpoint.dart';

void main() {
  test('the endpoint lives in the runtime folder on Linux', () {
    expect(
      endpointPath(
        os: 'linux',
        environment: {
          'XDG_RUNTIME_DIR': '/run/user/1000',
          'HOME': '/home/alice',
        },
      ),
      '/run/user/1000/vidctrl/control.json',
    );
    expect(
      endpointPath(os: 'linux', environment: {'HOME': '/home/alice'}),
      '/home/alice/.cache/vidctrl/control.json',
    );
  });

  test('on macOS and Windows it lives in the per-user app folder', () {
    expect(
      endpointPath(os: 'macos', environment: {'HOME': '/Users/alice'}),
      '/Users/alice/Library/Application Support/app.camctrl.vidctrl/control.json',
    );
    expect(
      endpointPath(
        os: 'windows',
        environment: {'LOCALAPPDATA': r'C:\Users\alice\AppData\Local'},
      ),
      r'C:\Users\alice\AppData\Local\VidCtrl\control.json',
    );
  });

  test('VIDCTRL_ENDPOINT names another endpoint file', () {
    expect(
      EndpointFile.forThisUser(
        environment: {
          'VIDCTRL_ENDPOINT': '/home/alice/dev/control.json',
          'XDG_RUNTIME_DIR': '/run/user/1000',
          'HOME': '/home/alice',
        },
      ).path,
      '/home/alice/dev/control.json',
    );
    expect(
      EndpointFile.forThisUser(
        environment: {'VIDCTRL_ENDPOINT': '', 'HOME': '/home/alice'},
      ).path,
      isNot(''),
    );
  });

  test(
    'a written endpoint reads back and only its owner can read it',
    () async {
      final dir = await Directory.systemTemp.createTemp('endpoint');
      addTearDown(() => dir.delete(recursive: true));
      final file = EndpointFile(p.join(dir.path, 'sub', 'control.json'));
      const e = Endpoint(
        port: 4242,
        token: 't',
        pid: 1,
        version: '',
        protocol: 1,
      );
      await file.write(e);
      final back = (await file.read())!;
      expect(
        (back.port, back.token, back.pid, back.version, back.protocol),
        (4242, 't', 1, '', 1),
      );
      if (!Platform.isWindows) {
        expect(FileStat.statSync(file.path).modeString(), 'rw-------');
      }
      await file.delete();
      expect(await file.read(), isNull);
      await file.delete();
    },
  );

  test('a folder made for the endpoint is for its owner only', () async {
    final dir = await Directory.systemTemp.createTemp('endpoint');
    addTearDown(() => dir.delete(recursive: true));
    final file = EndpointFile(p.join(dir.path, 'sub', 'control.json'));
    const e = Endpoint(port: 1, token: 't', pid: 1, version: '', protocol: 1);
    await file.write(e);
    if (!Platform.isWindows) {
      expect(
        FileStat.statSync(p.join(dir.path, 'sub')).modeString(),
        'rwx------',
      );
    }
  });

  test('writing again replaces the endpoint and leaves no temp file', () async {
    final dir = await Directory.systemTemp.createTemp('endpoint');
    addTearDown(() => dir.delete(recursive: true));
    final file = EndpointFile(p.join(dir.path, 'control.json'));
    await file.write(
      const Endpoint(port: 1, token: 'a', pid: 1, version: '', protocol: 1),
    );
    await file.write(
      const Endpoint(port: 2, token: 'b', pid: 1, version: '', protocol: 1),
    );
    expect((await file.read())!.port, 2);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('two windows starting at once each write a whole endpoint', () async {
    final dir = await Directory.systemTemp.createTemp('endpoint');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'control.json');

    await Future.wait([
      for (var port = 1; port <= 20; port++)
        EndpointFile(path).write(
          Endpoint(
            port: port,
            token: 't$port',
            pid: port,
            version: '',
            protocol: 1,
          ),
        ),
    ]);

    final written = (await EndpointFile(path).read())!;
    expect(written.token, 't${written.port}');
    expect(dir.listSync().map((f) => p.basename(f.path)), ['control.json']);
  });

  test('a malformed endpoint file reads as none', () async {
    final dir = await Directory.systemTemp.createTemp('endpoint');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'control.json');
    await File(path).writeAsString('{');
    expect(await EndpointFile(path).read(), isNull);
    await File(path).writeAsString('{"port": "x"}');
    expect(await EndpointFile(path).read(), isNull);
  });

  test('tokens differ and are long', () {
    expect(newToken(), isNot(newToken()));
    expect(newToken().length, greaterThanOrEqualTo(43));
    expect(newToken(), isNot(contains('=')));
  });
}
