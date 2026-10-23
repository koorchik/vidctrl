import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;

import 'endpoint.dart';
import 'protocol.dart';

/// The client's side of the conversation with the open window.
class ControlConnection {
  ControlConnection._(this._socket) {
    _subscription = utf8.decoder
        .bind(_socket)
        .transform(const LineSplitter())
        .listen(
          _lines.add,
          onError: (Object _) => _finish(),
          onDone: _finish,
          cancelOnError: true,
        );
    _socket.done.then((_) {}, onError: (Object _) => _finish());
    final messages = jsonLines(_lines.stream, (line) {
      if (!_done.isCompleted) _socket.write('$line\n');
    });
    _rpc =
        rpc.Peer.withoutJson(
            messages.transformStream(
              StreamTransformer.fromHandlers(
                // Not JSON: not VidCtrl talking.
                handleError: (_, _, _) => _finish(),
              ),
            ),
          )
          // The window asks nothing of a client; what it sends is events.
          ..registerFallback(_onNotification);
    unawaited(_rpc.listen());
  }

  /// Connects to [endpoint] and says `hello`. Throws [ControlError]:
  /// [ControlErrorKind.notRunning] when nothing listens there,
  /// [ControlErrorKind.unauthorized] when what listens refuses the token or
  /// does not answer like VidCtrl, and the window's own error when it speaks
  /// another protocol.
  static Future<ControlConnection> open(
    Endpoint endpoint, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        endpoint.port,
        timeout: timeout,
      );
    } on SocketException {
      throw const ControlError(
        ControlErrorKind.notRunning,
        'VidCtrl is not running.',
      );
    }
    final connection = ControlConnection._(socket);
    try {
      await connection
          .call(Methods.hello, {
            'token': endpoint.token,
            'protocol': controlProtocol,
          })
          .timeout(timeout);
      return connection;
    } on ControlError catch (e) {
      await connection.close();
      if (e.kind == ControlErrorKind.badArgument) rethrow;
      throw _refused;
    } on TimeoutException {
      await connection.close();
      throw _refused;
    }
  }

  static const _refused = ControlError(
    ControlErrorKind.unauthorized,
    'VidCtrl refused the connection.',
  );

  final Socket _socket;
  late final StreamSubscription<String> _subscription;
  // Synchronous, so an event that comes just before the end is not lost.
  final _lines = StreamController<String>(sync: true);
  late final rpc.Peer _rpc;
  // Kept until listened to, so an event that arrives first is not lost.
  final _notifications = StreamController<ControlNotification>();
  final _done = Completer<void>();

  /// Throws the window's [ControlError], or [ControlErrorKind.appClosed]
  /// when the connection ends before the answer comes.
  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_done.isCompleted) throw _appClosed;
    try {
      return await _rpc.sendRequest(method, params);
    } on rpc.RpcException catch (e) {
      throw ControlError.fromRpc(e);
    } on StateError {
      // json_rpc_2's word for a connection that ended first.
      throw _appClosed;
    }
  }

  /// What the window tells this client unasked; ends with the connection.
  Stream<ControlNotification> get notifications => _notifications.stream;

  /// Completes when the connection ends, from either side.
  Future<void> get done => _done.future;

  Future<void> close() async => _finish();

  static const _appClosed = ControlError(
    ControlErrorKind.appClosed,
    'VidCtrl was closed.',
  );

  void _onNotification(rpc.Parameters event) {
    if (_done.isCompleted) return;
    _notifications.add(
      ControlNotification(
        event.method,
        event.value == null ? {} : event.asMap.cast<String, Object?>(),
      ),
    );
  }

  /// Calls still waiting fail with [ControlErrorKind.appClosed].
  void _finish() {
    if (_done.isCompleted) return;
    _done.complete();
    _socket.destroy();
    _subscription.cancel();
    _lines.close();
    _rpc.close();
    _notifications.close();
  }
}

/// A connection to the window [file] names, or null when there is none to
/// be had: no file, nothing listening on its port, or something there that
/// refuses the token (a file left by a window that is gone, or another
/// program on that port now). Throws when the window speaks another
/// protocol, as starting another would not help.
Future<ControlConnection?> connectIfLive(EndpointFile file) async {
  final endpoint = await file.read();
  if (endpoint == null) return null;
  try {
    return await ControlConnection.open(endpoint);
  } on ControlError catch (e) {
    if (e.kind == ControlErrorKind.badArgument) rethrow;
    return null;
  }
}
