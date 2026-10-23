import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/control/connection.dart';
import '../../core/control/endpoint.dart';
import '../../core/control/listener.dart';
import '../../core/control/protocol.dart';
import '../build_info.dart';
import 'handlers.dart';

class ControlState {
  const ControlState({this.port});

  /// Where this window listens for `vidctrl-client`; null while it does not.
  final int? port;

  bool get serving => port != null;
}

final controlProvider = NotifierProvider<ControlController, ControlState>(
  ControlController.new,
);

/// Lets `vidctrl-client` control this window. The first window to start owns
/// the endpoint file; a later one, finding that window live, does not serve.
class ControlController extends Notifier<ControlState> {
  ControlListener? _listener;
  EndpointFile? _file;
  String? _token;
  Future<void>? _starting;

  @override
  ControlState build() {
    ref.onDispose(() => unawaited(_listener?.close(farewell: false)));
    return const ControlState();
  }

  /// Starts serving through [file] (the one for this user by default),
  /// unless another window already does.
  Future<void> start({EndpointFile? file}) =>
      _starting ??= _start(file ?? EndpointFile.forThisUser());

  Future<void> _start(EndpointFile file) async {
    try {
      final other = await connectIfLive(file);
      if (other != null) {
        await other.close();
        return;
      }
    } on ControlError {
      // A window of another version is live there; it keeps the endpoint.
      return;
    }
    final token = newToken();
    final listener = await ControlListener.bind(
      token: token,
      handler: (method, params, peer) =>
          handleControl(ref, method, params, peer),
    );
    try {
      await file.write(
        Endpoint(
          port: listener.port,
          token: token,
          pid: pid,
          version: ref.read(buildInfoProvider).version,
          protocol: controlProtocol,
        ),
      );
    } on Object {
      await listener.close(farewell: false);
      rethrow;
    }
    _listener = listener;
    _file = file;
    _token = token;
    state = ControlState(port: listener.port);
  }

  /// Tells every client the window is closing, ends their connections and
  /// removes the endpoint file, unless another window has written its own
  /// there since.
  Future<void> stop() async {
    await _starting?.catchError((Object _) {});
    _starting = null;
    final listener = _listener;
    final file = _file;
    if (listener == null || file == null) return;
    _listener = null;
    _file = null;
    if (ref.mounted) state = const ControlState();
    await listener.close(farewell: true);
    if ((await file.read())?.token == _token) await file.delete();
  }
}
