import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/listener.dart';
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

ControlError? _errorIn(String line) =>
    (decodeMessage(line) as ControlResponse).error;

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
    final hello = encodeMessage(
      const ControlRequest(1, Methods.hello, {
        'token': 'wrong',
        'protocol': controlProtocol,
      }),
    );
    final received = await _rawExchange(listener.port, [
      '$hello\n',
      '${encodeMessage(const ControlRequest(2, 'status', {}))}\n',
    ]);
    expect(received, hasLength(1));
    expect(_errorIn(received.single)?.kind, ControlErrorKind.unauthorized);
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
    expect(_errorIn(received.single)?.kind, ControlErrorKind.unauthorized);
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
    expect(_errorIn(silent.single)?.kind, ControlErrorKind.unauthorized);
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
    expect(_errorIn(endless.single)?.kind, ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a request before hello is refused', () async {
    var calls = 0;
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => calls++,
    );
    addTearDown(listener.close);
    final received = await _rawExchange(listener.port, [
      '${encodeMessage(const ControlRequest(5, 'status', {}))}\n',
    ]);
    final answer = decodeMessage(received.single) as ControlResponse;
    expect(answer.id, 5);
    expect(answer.error?.kind, ControlErrorKind.unauthorized);
    expect(calls, 0);
  });

  test('a client of another protocol is told which one to use', () async {
    final listener = await ControlListener.bind(
      token: 't',
      handler: (method, params, peer) async => null,
    );
    addTearDown(listener.close);
    final hello = encodeMessage(
      const ControlRequest(1, Methods.hello, {'token': 't', 'protocol': 99}),
    );
    final received = await _rawExchange(listener.port, ['$hello\n']);
    final error = _errorIn(received.single);
    expect(error?.kind, ControlErrorKind.badArgument);
    expect(
      error?.message,
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

  test('a stale endpoint file is not live', () async {
    final folder = await Directory.systemTemp.createTemp('vidctrl_control');
    addTearDown(() => folder.delete(recursive: true));
    final file = EndpointFile(p.join(folder.path, 'control.json'));
    expect(await connectIfLive(file), isNull);

    final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = gone.port;
    await gone.close();
    await file.write(_endpoint(freePort, 't'));
    expect(await connectIfLive(file), isNull);

    final listener = await ControlListener.bind(
      token: 'other',
      handler: (method, params, peer) async => null,
    );
    addTearDown(listener.close);
    await file.write(_endpoint(listener.port, 't'));
    expect(await connectIfLive(file), isNull);

    await file.write(_endpoint(listener.port, 'other'));
    final live = await connectIfLive(file);
    expect(live, isNotNull);
    await live!.close();
  });

  test('another program on the port is not mistaken for VidCtrl', () async {
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
    expect(await connectIfLive(file), isNull);
  });
}
