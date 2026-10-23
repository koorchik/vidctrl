import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/control/connection.dart';
import '../../core/control/endpoint.dart';
import '../../core/control/listener.dart';
import '../../core/control/protocol.dart';
import '../build_info.dart';
import '../providers.dart';
import '../quality/quality_controller.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_state.dart';
import '../sources/sources_controller.dart';
import 'events.dart';
import 'handlers.dart';
import 'waiter.dart';

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
/// Once FFmpeg is found it follows the videos, the queue and the comparisons,
/// to tell subscribed clients what happens and to answer waiting ones.
class ControlController extends Notifier<ControlState>
    implements ControlSessions {
  ControlListener? _listener;
  EndpointFile? _file;
  String? _token;
  Future<void>? _starting;
  List<ProviderSubscription<Object?>>? _following;
  final _subscribers = <ControlPeer, _Subscriber>{};
  final _waits = <_Wait>[];
  final _clock = Stopwatch()..start();

  /// The least time between two `job-progress` events for one job.
  static const _progressEvery = Duration(seconds: 1);

  @override
  ControlState build() {
    ref.onDispose(() {
      _unfollow();
      unawaited(_listener?.close(farewell: false));
    });
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
          handleControl(ref, this, method, params, peer),
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
    unawaited(_followWhenReady(listener));
  }

  /// The videos, queue and comparisons need FFmpeg found before they exist.
  Future<void> _followWhenReady(ControlListener listener) async {
    try {
      await ref.read(environmentProvider.future);
    } on Object {
      // Nothing happens in a window without FFmpeg.
      return;
    }
    if (ref.mounted && identical(_listener, listener)) _follow();
  }

  /// Starts following, once the environment is ready.
  void _follow() {
    if (_following != null) return;
    _following = [
      ref.listen<QueueState>(queueProvider, (before, after) {
        _tell(queueEvents(before ?? const QueueState(), after));
        _updateWaits(after);
      }),
      ref.listen<SourcesState>(
        sourcesProvider,
        (before, after) =>
            _tell(sourceEvents(before ?? const SourcesState(), after)),
      ),
      ref.listen<Map<int, QualityCheck>>(
        qualityProvider,
        (before, after) => _tell(qualityEvents(before ?? const {}, after)),
      ),
    ];
  }

  void _unfollow() {
    for (final subscription in _following ?? const []) {
      subscription.close();
    }
    _following = null;
  }

  void _tell(List<ControlEvent> events) {
    for (final event in events) {
      for (final MapEntry(key: peer, value: subscriber)
          in _subscribers.entries.toList()) {
        if (event.name == Events.jobProgress &&
            !subscriber.progressDue(event.data['job'] as int, _clock.elapsed)) {
          continue;
        }
        peer.notify(event.name, eventParams(event.data));
      }
    }
  }

  void _updateWaits(QueueState queue) {
    for (final wait in _waits.toList()) {
      final wasPaused = wait.tracker.paused;
      wait.tracker.update(queue);
      if (wait.tracker.finished) {
        _waits.remove(wait);
        wait.done.complete();
      } else if (!wasPaused && wait.tracker.paused) {
        _tellPaused(wait.peer);
      }
    }
  }

  /// Tells a waiting client that the queue is paused, unless its events say
  /// so already.
  void _tellPaused(ControlPeer peer) {
    if (_subscribers.containsKey(peer)) return;
    peer.notify(Events.queuePaused, eventParams(const {}));
  }

  @override
  void subscribe(ControlPeer peer) {
    _follow();
    if (_subscribers.containsKey(peer)) return;
    _subscribers[peer] = _Subscriber();
    peer.closed.then((_) => _subscribers.remove(peer));
  }

  @override
  Future<void> waitFor(ControlPeer peer, WaitTracker tracker) {
    if (tracker.finished) return Future.value();
    _follow();
    final wait = _Wait(peer, tracker);
    _waits.add(wait);
    if (tracker.paused) _tellPaused(peer);
    peer.closed.then((_) {
      if (_waits.remove(wait)) wait.done.completeError(_closed);
    });
    return wait.done.future;
  }

  static const _closed = ControlError(
    ControlErrorKind.appClosed,
    'VidCtrl was closed.',
  );

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
    _unfollow();
    _subscribers.clear();
    if (ref.mounted) state = const ControlState();
    await listener.close(farewell: true);
    // Their clients have been told the window is closing.
    for (final wait in _waits) {
      wait.done.completeError(_closed);
    }
    _waits.clear();
    if ((await file.read())?.token == _token) await file.delete();
  }
}

/// A client that asked to be told every event.
class _Subscriber {
  /// When each job's progress was last told, on the controller's clock.
  final _progressTold = <int, Duration>{};

  /// Whether [job]'s progress may be told [now]; if so it counts as told.
  bool progressDue(int job, Duration now) {
    final last = _progressTold[job];
    if (last != null && now - last < ControlController._progressEvery) {
      return false;
    }
    _progressTold[job] = now;
    return true;
  }
}

/// A `wait` not answered yet.
class _Wait {
  _Wait(this.peer, this.tracker);

  final ControlPeer peer;
  final WaitTracker tracker;
  final done = Completer<void>();
}
