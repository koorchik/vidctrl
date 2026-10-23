import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/listener.dart';
import 'package:vidctrl/core/control/process_alive.dart';
import 'package:vidctrl/core/control/protocol.dart';

Endpoint _endpoint(int port, String token) => Endpoint(
  port: port,
  token: token,
  pid: 1,
  version: '0.1.0',
  protocol: controlProtocol,
);

/// Sends [lines] over a plain socket and returns every line that came back
/// before the listener ended the connection.
Future<List<String>> _rawExchange(int port, List<String> lines) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  for (final line in lines) {
    socket.write(line);
  }
  final received = await utf8.decoder
      .bind(socket)
      .transform(const LineSplitter())
      .toList()
      .timeout(const Duration(seconds: 5));
  socket.destroy();
  return received;
}

/// One request as a line of JSON-RPC 2.0, written out by hand.
String _request(
  int id,
  String method, [
  Map<String, Object?> params = const {},
]) =>
    '${jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params})}\n';

/// The kind of the error answered in [line], if it is one.
ControlErrorKind? _errorIn(String line) {
  final error = (jsonDecode(line) as Map)['error'];
  if (error is! Map) return null;
  return ControlErrorKind.values.asNameMap()[(error['data'] as Map)['kind']];
}

Future<bool> _alive(int pid) async => true;

Future<bool> _gone(int pid) async => false;

void main() {
  test('a call reaches the handler and its answer comes back', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => {'echo': method, ...params},
    );
    addTearDown(listener.close);
    final c = await ControlConnection.open(_endpoint(listener.port, 't'));
    addTearDown(c.close);
    expect(await c.call('status', {'x': 1}), {'echo': 'status', 'x': 1});
  });

  test('a wrong token is refused and the connection closed', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    await expectLater(
      ControlConnection.open(_endpoint(listener.port, 'wrong')),
      throwsA(
        isA<ControlError>().having(
          (e) => e.kind,
          'kind',
          ControlErrorKind.unauthorized,
        ),
      ),
    );
    final received = await _rawExchange(listener.port, [
      _request(1, Methods.hello, {
        'token': 'wrong',
        'protocol': controlProtocol,
      }),
      _request(2, 'status'),
    ]);
    expect(received, hasLength(1));
    expect(_errorIn(received.single), ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a line that is not JSON closes the connection at once', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    final received = await _rawExchange(listener.port, [
      'GET / HTTP/1.1\r\n\r\n',
    ]);
    expect(received, hasLength(1));
    expect(_errorIn(received.single), ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a line that is not JSON after hello ends the connection', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    final lines = StreamIterator(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );
    socket.write(
      _request(1, Methods.hello, {'token': 't', 'protocol': controlProtocol}),
    );
    expect(await lines.moveNext(), isTrue);
    expect((jsonDecode(lines.current) as Map)['result'], {
      'protocol': controlProtocol,
    });
    socket.write('not JSON\n${_request(2, 'status')}');
    expect(await lines.moveNext(), isTrue);
    expect(_errorIn(lines.current), ControlErrorKind.unauthorized);
    expect(await lines.moveNext().timeout(const Duration(seconds: 5)), isFalse);
    socket.destroy();
    expect(calls, 0);
  });

  test('a connection that never says hello is ended', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
      helloDeadline: const Duration(milliseconds: 200),
    );
    addTearDown(listener.close);
    final silent = await _rawExchange(listener.port, []);
    expect(_errorIn(silent.single), ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a long first line without a break is refused at once', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    final endless = await _rawExchange(listener.port, [
      'x' * 100000,
    ]).timeout(const Duration(seconds: 2));
    expect(_errorIn(endless.single), ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a request before hello is refused', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    final received = await _rawExchange(listener.port, [_request(5, 'status')]);
    expect((jsonDecode(received.single) as Map)['id'], 5);
    expect(_errorIn(received.single), ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a batch before hello is refused and the connection ends', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    final hello = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': Methods.hello,
      'params': {'token': 't', 'protocol': controlProtocol},
    };
    final status = {'jsonrpc': '2.0', 'id': 2, 'method': 'status'};
    // _rawExchange returns only once the listener has ended the connection.
    final received = await _rawExchange(listener.port, [
      '${jsonEncode([hello, status])}\n',
    ]);
    expect(received, hasLength(1));
    expect(_errorIn(received.single), ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a client of another protocol is told which one to use', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => null,
    );
    addTearDown(listener.close);
    final received = await _rawExchange(listener.port, [
      _request(1, Methods.hello, {'token': 't', 'protocol': 99}),
    ]);
    expect(_errorIn(received.single), ControlErrorKind.badArgument);
    expect(
      ((jsonDecode(received.single) as Map)['error'] as Map)['message'],
      'This vidctrl-client speaks protocol 99, the app speaks '
      '$controlProtocol; use the vidctrl-client that came with this VidCtrl.',
    );
  });

  test('a slow call does not hold up a quick one', () async {
    final slow = Completer<Object?>();
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) =>
          method == 'slow' ? slow.future : Future.value('quick'),
    );
    addTearDown(listener.close);
    final c = await ControlConnection.open(_endpoint(listener.port, 't'));
    addTearDown(c.close);
    final slowAnswer = c.call('slow');
    expect(await c.call('quick'), 'quick');
    slow.complete('slow');
    expect(await slowAnswer, 'slow');
  });

  test('an error from the handler arrives with its kind', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => switch (method) {
        'job.get' => throw const ControlError(
          ControlErrorKind.notFound,
          'no job 9',
        ),
        _ => throw StateError('broken'),
      },
    );
    addTearDown(listener.close);
    final c = await ControlConnection.open(_endpoint(listener.port, 't'));
    addTearDown(c.close);
    await expectLater(
      c.call('job.get', {'job': 9}),
      throwsA(
        isA<ControlError>()
            .having((e) => e.kind, 'kind', ControlErrorKind.notFound)
            .having((e) => e.message, 'message', 'no job 9'),
      ),
    );
    await expectLater(
      c.call('other'),
      throwsA(
        isA<ControlError>()
            .having((e) => e.kind, 'kind', ControlErrorKind.badArgument)
            .having((e) => e.message, 'message', contains('broken')),
      ),
    );
  });

  test('the handler can tell a client something unasked', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async {
        peer.notify(Events.jobAdded, {'job': 3});
        return true;
      },
    );
    addTearDown(listener.close);
    final c = await ControlConnection.open(_endpoint(listener.port, 't'));
    addTearDown(c.close);
    final event = c.notifications.first;
    await c.call(Methods.subscribe);
    expect((await event).method, Events.jobAdded);
    expect((await event).params, {'job': 3});
  });

  test('the handler learns when its client has gone', () async {
    final gone = Completer<void>();
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async {
        unawaited(peer.closed.then(gone.complete));
        return true;
      },
    );
    addTearDown(listener.close);
    final c = await ControlConnection.open(_endpoint(listener.port, 't'));
    await c.call(Methods.wait);
    await c.close();
    await gone.future.timeout(const Duration(seconds: 5));
  });

  test('closing says goodbye to every client', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => null,
    );
    final a = await ControlConnection.open(_endpoint(listener.port, 't'));
    final b = await ControlConnection.open(_endpoint(listener.port, 't'));
    final goodbyes = [a.notifications.first, b.notifications.first];
    await listener.close();
    for (final goodbye in goodbyes) {
      expect((await goodbye).method, Events.appClosing);
    }
    await Future.wait([a.done, b.done]).timeout(const Duration(seconds: 5));
  });

  test('a call still waiting when the app closes says so', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) => Completer<Object?>().future,
    );
    final c = await ControlConnection.open(_endpoint(listener.port, 't'));
    final waiting = expectLater(
      c.call(Methods.wait),
      throwsA(
        isA<ControlError>()
            .having((e) => e.kind, 'kind', ControlErrorKind.appClosed)
            .having((e) => e.message, 'message', 'VidCtrl was closed.'),
      ),
    );
    await listener.close(farewell: false);
    await waiting;
    await expectLater(
      c.call('status'),
      throwsA(
        isA<ControlError>().having(
          (e) => e.kind,
          'kind',
          ControlErrorKind.appClosed,
        ),
      ),
    );
  });

  test('open says not running when the port refuses', () async {
    final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = gone.port;
    await gone.close();
    await expectLater(
      ControlConnection.open(_endpoint(freePort, 't')),
      throwsA(
        isA<ControlError>().having(
          (e) => e.kind,
          'kind',
          ControlErrorKind.notRunning,
        ),
      ),
    );
  });

  test('a stale endpoint file is not live', () async {
    final folder = await Directory.systemTemp.createTemp('vidctrl_control');
    addTearDown(() => folder.delete(recursive: true));
    final file = EndpointFile(p.join(folder.path, 'control.json'));
    expect(await connectIfLive(file, isAlive: _alive), isNull);

    await File(file.path).writeAsString('{"port": "not a number"}');
    expect(await connectIfLive(file, isAlive: _alive), isNull);

    // Nothing listens on its port: stale, whatever runs under its pid.
    final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = gone.port;
    await gone.close();
    await file.write(_endpoint(freePort, 't'));
    expect(await connectIfLive(file, isAlive: _alive), isNull);

    // Something there refuses the token, and the window is gone.
    final listener = await ControlListener.bind(
      token: 'other',
      handler: (method, params, peer) async => null,
    );
    addTearDown(listener.close);
    await file.write(_endpoint(listener.port, 't'));
    expect(await connectIfLive(file, isAlive: _gone), isNull);

    await file.write(_endpoint(listener.port, 'other'));
    final live = await connectIfLive(file, isAlive: _gone);
    expect(live, isNotNull);
    await live!.close();
  });

  test('another program on the port of a window that is gone is not '
      'mistaken for VidCtrl', () async {
    final folder = await Directory.systemTemp.createTemp('vidctrl_control');
    addTearDown(() => folder.delete(recursive: true));
    final file = EndpointFile(p.join(folder.path, 'control.json'));
    final other = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(other.close);
    other.listen((socket) {
      socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
      socket.close();
    });
    await file.write(_endpoint(other.port, 't'));
    expect(await connectIfLive(file, isAlive: _gone), isNull);
  });

  test('a running window that does not answer is not taken for a stale '
      'one', () async {
    final folder = await Directory.systemTemp.createTemp('vidctrl_control');
    addTearDown(() => folder.delete(recursive: true));
    final file = EndpointFile(p.join(folder.path, 'control.json'));
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    final accepted = <Socket>[];
    silent.listen(accepted.add);
    addTearDown(() {
      for (final socket in accepted) {
        socket.destroy();
      }
    });
    await file.write(_endpoint(silent.port, 't'));
    const quick = Duration(milliseconds: 200);

    await expectLater(
      connectIfLive(file, isAlive: _alive, timeout: quick),
      throwsA(
        isA<ControlError>()
            .having((e) => e.kind, 'kind', ControlErrorKind.unauthorized)
            .having(
              (e) => e.message,
              'message',
              'VidCtrl is running but does not answer; try again, or close '
                  'and reopen its window.',
            ),
      ),
    );
    // The same silence on the port of a window that is gone: stale.
    expect(await connectIfLive(file, isAlive: _gone, timeout: quick), isNull);
  });

  test('a running window that refuses the token is not taken for a stale '
      'one', () async {
    final folder = await Directory.systemTemp.createTemp('vidctrl_control');
    addTearDown(() => folder.delete(recursive: true));
    final file = EndpointFile(p.join(folder.path, 'control.json'));
    final listener = await ControlListener.bind(
      token: 'other',
      handler: (method, params, peer) async => null,
    );
    addTearDown(listener.close);
    await file.write(_endpoint(listener.port, 't'));
    await expectLater(
      connectIfLive(file, isAlive: _alive),
      throwsA(
        isA<ControlError>().having(
          (e) => e.kind,
          'kind',
          ControlErrorKind.unauthorized,
        ),
      ),
    );
  });

  test(
    'the window running these tests is alive, a pid of none is not',
    () async {
      expect(await processIsAlive(pid), isTrue);
      expect(await processIsAlive(0), isFalse);
      expect(await processIsAlive(-1), isFalse);
    },
  );
}
