import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';

import 'protocol.dart';

/// Answers one request from a client that has said `hello`. Throws a
/// [ControlError] to refuse it; any other exception reaches the client as
/// [ControlErrorKind.badArgument] with its text.
typedef ControlHandler = Future<Object?> Function(
  String method,
  Map<String, Object?> params,
  ControlPeer peer,
);

/// The client a request came from, for telling it things later.
abstract interface class ControlPeer {
  /// Does nothing once the connection has ended.
  void notify(String method, Map<String, Object?> params);

  /// Completes when the connection ends, from either side.
  Future<void> get closed;
}

/// The window's side of the conversation: a socket on the loopback
/// interface that only programs knowing [token] may talk to.
class ControlListener {
  ControlListener._(
    this._server,
    this._token,
    this._handler,
    this._helloDeadline,
  ) {
    _server.listen(_accept);
  }

  /// Listens on a port the system picks, on `127.0.0.1` only. A connection
  /// that has not said `hello` within [helloDeadline] is ended; the client
  /// says it at once, and gives up itself after two seconds.
  static Future<ControlListener> bind({
    required String token,
    required ControlHandler handler,
    Duration helloDeadline = const Duration(seconds: 5),
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return ControlListener._(server, token, handler, helloDeadline);
  }

  final ServerSocket _server;
  final String _token;
  final ControlHandler _handler;
  final Duration _helloDeadline;
  final _peers = <_Peer>{};
  bool _closing = false;

  int get port => _server.port;

  void _accept(Socket socket) {
    if (_closing) {
      socket.destroy();
      return;
    }
    final peer = _Peer(socket, this);
    _peers.add(peer);
    unawaited(peer.closed.then((_) => _peers.remove(peer)));
  }

  /// With [farewell], every client that said `hello` is told
  /// [Events.appClosing] before its connection ends.
  Future<void> close({bool farewell = true}) async {
    if (_closing) return;
    _closing = true;
    await _server.close();
    final peers = _peers.toList();
    if (farewell) {
      for (final peer in peers) {
        peer.notify(Events.appClosing, const {});
      }
    }
    await Future.wait([for (final peer in peers) peer.end()]);
  }
}

/// One connection: json_rpc_2 answers the requests, behind a gate that lets
/// through nothing before a right `hello`.
class _Peer implements ControlPeer {
  _Peer(this._socket, this._listener) {
    _helloTimer = Timer(_listener._helloDeadline, () => _refuse(null));
    _subscription = utf8.decoder
        .bind(_socket.map(_countUnheard))
        .transform(const LineSplitter())
        .listen(
          _lines.add,
          onError: (Object _) => _finish(),
          onDone: _finish,
          cancelOnError: true,
        );
    // A write to a client that has gone shows up here, not at the write.
    unawaited(_socket.done.then((_) {}, onError: (Object _) => _finish()));
    _messages = jsonLines(_lines.stream, _write);
    _rpc =
        rpc.Peer.withoutJson(
            _messages.transformStream(
              StreamTransformer.fromHandlers(
                handleData: _admit,
                // Not JSON: not one of ours, perhaps a browser posting to
                // the port.
                handleError: (_, _, _) => _refuse(null),
              ),
            ),
          )
          ..registerMethod(Methods.hello, (rpc.Parameters _) => _helloAnswer)
          ..registerFallback(_serve);
    unawaited(_rpc.listen());
  }

  final Socket _socket;
  final ControlListener _listener;
  late final StreamSubscription<String> _subscription;
  late final Timer _helloTimer;
  // Synchronous, so a line is dealt with before the next one comes.
  final _lines = StreamController<String>(sync: true);
  late final StreamChannel<Object?> _messages;
  late final rpc.Peer _rpc;
  final _closed = Completer<void>();
  bool _authorised = false;

  /// Bytes received before `hello`, which is a short line: a program that
  /// sends more, or no line break at all, is not a client.
  int _unheard = 0;
  static const _unheardLimit = 4096;

  /// Set once nothing more is to be written, and lines are ignored.
  bool _ending = false;

  @override
  Future<void> get closed => _closed.future;

  @override
  void notify(String method, Map<String, Object?> params) {
    if (_authorised && !_ending) _rpc.sendNotification(method, params);
  }

  List<int> _countUnheard(List<int> bytes) {
    if (!_authorised && !_ending) {
      _unheard += bytes.length;
      if (_unheard > _unheardLimit) _refuse(null);
    }
    return bytes;
  }

  /// Passes [message] on to json_rpc_2 once the client has said `hello`.
  void _admit(Object? message, EventSink<Object?> rpcSide) {
    if (_ending) return;
    if (_authorised || _greet(message)) rpcSide.add(message);
  }

  /// The first message must be `hello` with the token, or the connection
  /// ends. True when it is, and json_rpc_2 is to answer it.
  bool _greet(Object? message) {
    final params = message is Map ? message['params'] : null;
    if (message is! Map ||
        message['jsonrpc'] != '2.0' ||
        message['id'] is! int && message['id'] is! String ||
        message['method'] != Methods.hello ||
        params is! Map ||
        params['token'] != _listener._token ||
        params['protocol'] is! int) {
      _refuse(message);
      return false;
    }
    final protocol = params['protocol'];
    if (protocol != controlProtocol) {
      _answerAndEnd(
        message,
        ControlError(
          ControlErrorKind.badArgument,
          'This vidctrl-client speaks protocol $protocol, the app speaks '
          '$controlProtocol; use the vidctrl-client that came with this '
          'VidCtrl.',
        ),
      );
      return false;
    }
    _authorised = true;
    _helloTimer.cancel();
    return true;
  }

  static const _helloAnswer = {'protocol': controlProtocol};

  /// Answers [request] (null when there is none to answer) with
  /// [ControlErrorKind.unauthorized] and ends the connection.
  void _refuse(Object? request) => _answerAndEnd(
    request,
    const ControlError(
      ControlErrorKind.unauthorized,
      'VidCtrl refused the connection.',
    ),
  );

  void _answerAndEnd(Object? request, ControlError error) {
    if (_ending) return;
    _messages.sink.add(error.toRpc().serialize(request));
    unawaited(end());
  }

  Future<Object?> _serve(rpc.Parameters request) async {
    final params = request.value == null
        ? <String, Object?>{}
        : request.asMap.cast<String, Object?>();
    try {
      return await _listener._handler(request.method, params, this);
    } on ControlError catch (e) {
      throw e.toRpc();
    } on Object catch (e) {
      throw ControlError(ControlErrorKind.badArgument, '$e').toRpc();
    }
  }

  void _write(String line) {
    if (_ending || _closed.isCompleted) return;
    _socket.write('$line\n');
  }

  /// Sends what is written so far, then ends the connection; waits a moment
  /// for the client to end its side, so nothing it sent is left unread.
  Future<void> end() {
    if (!_ending) {
      _ending = true;
      _helloTimer.cancel();
      // A failure means the client has gone already; `done` reports it.
      unawaited(_socket.close().then((_) {}, onError: (Object _) {}));
    }
    return closed.timeout(const Duration(seconds: 1), onTimeout: _finish);
  }

  void _finish() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _ending = true;
    _helloTimer.cancel();
    _socket.destroy();
    unawaited(_subscription.cancel());
    unawaited(_lines.close());
    unawaited(_rpc.close());
  }
}
