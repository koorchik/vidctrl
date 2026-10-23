import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  ControlListener._(this._server, this._token, this._handler) {
    _server.listen(_accept);
  }

  /// Listens on a port the system picks, on `127.0.0.1` only.
  static Future<ControlListener> bind({
    required String token,
    required ControlHandler handler,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return ControlListener._(server, token, handler);
  }

  final ServerSocket _server;
  final String _token;
  final ControlHandler _handler;
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
    peer.closed.then((_) => _peers.remove(peer));
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

class _Peer implements ControlPeer {
  _Peer(this._socket, this._listener) {
    _subscription = utf8.decoder
        .bind(_socket)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object _) => _finish(),
          onDone: _finish,
          cancelOnError: true,
        );
    // A write to a client that has gone shows up here, not at the write.
    _socket.done.then((_) {}, onError: (Object _) => _finish());
  }

  final Socket _socket;
  final ControlListener _listener;
  late final StreamSubscription<String> _subscription;
  final _closed = Completer<void>();
  bool _authorised = false;

  /// Set once nothing more is to be written, and lines are ignored.
  bool _ending = false;

  @override
  Future<void> get closed => _closed.future;

  @override
  void notify(String method, Map<String, Object?> params) {
    if (_authorised) _send(ControlNotification(method, params));
  }

  void _onLine(String line) {
    if (_ending) return;
    final ControlMessage message;
    try {
      message = decodeMessage(line);
    } on FormatException {
      // Not one of ours, perhaps a browser posting to the port.
      _refuse(0);
      return;
    }
    if (!_authorised) {
      _greet(message);
    } else if (message is ControlRequest) {
      unawaited(_serve(message));
    }
  }

  /// The first message must be `hello` with the token, or the connection
  /// ends.
  void _greet(ControlMessage message) {
    if (message is! ControlRequest ||
        message.method != Methods.hello ||
        message.params['token'] != _listener._token ||
        message.params['protocol'] is! int) {
      _refuse(message is ControlRequest ? message.id : 0);
      return;
    }
    final protocol = message.params['protocol'];
    if (protocol != controlProtocol) {
      _send(
        ControlResponse(
          message.id,
          error: ControlError(
            ControlErrorKind.badArgument,
            'This vidctrl-client speaks protocol $protocol, the app speaks '
            '$controlProtocol; use the vidctrl-client that came with this '
            'VidCtrl.',
          ),
        ),
      );
      unawaited(end());
      return;
    }
    _authorised = true;
    _send(ControlResponse(message.id, result: _helloAnswer));
  }

  static const _helloAnswer = {'protocol': controlProtocol};

  void _refuse(int id) {
    _send(
      ControlResponse(
        id,
        error: const ControlError(
          ControlErrorKind.unauthorized,
          'VidCtrl refused the connection.',
        ),
      ),
    );
    unawaited(end());
  }

  Future<void> _serve(ControlRequest request) async {
    if (request.method == Methods.hello) {
      _send(ControlResponse(request.id, result: _helloAnswer));
      return;
    }
    String line;
    try {
      final result = await _listener._handler(
        request.method,
        request.params,
        this,
      );
      line = encodeMessage(ControlResponse(request.id, result: result));
    } on ControlError catch (e) {
      line = encodeMessage(ControlResponse(request.id, error: e));
    } on Object catch (e) {
      line = encodeMessage(
        ControlResponse(
          request.id,
          error: ControlError(ControlErrorKind.badArgument, '$e'),
        ),
      );
    }
    _write(line);
  }

  void _send(ControlMessage message) => _write(encodeMessage(message));

  void _write(String line) {
    if (_ending || _closed.isCompleted) return;
    _socket.write('$line\n');
  }

  /// Sends what is written so far, then ends the connection; waits a moment
  /// for the client to end its side, so nothing it sent is left unread.
  Future<void> end() {
    if (!_ending) {
      _ending = true;
      // A failure means the client has gone already; `done` reports it.
      _socket.close().then((_) {}, onError: (Object _) {});
    }
    return closed.timeout(const Duration(seconds: 1), onTimeout: _finish);
  }

  void _finish() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _ending = true;
    _socket.destroy();
    _subscription.cancel();
  }
}
