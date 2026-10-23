import 'dart:convert';

/// The version of the conversation between a client and the window. It goes
/// in the endpoint file and in the `hello` answer.
const controlProtocol = 1;

/// Why a request failed, as the client needs to tell it apart.
enum ControlErrorKind {
  badArgument,
  notFound,
  busy,
  unknownMethod,
  ffmpegMissing,
  unauthorized,
  notRunning,
  appClosed;

  /// The code the client exits with for this kind of failure.
  int get exitCode => switch (this) {
    badArgument || notFound || busy || unknownMethod => ExitCode.badArguments,
    ffmpegMissing => ExitCode.ffmpegMissing,
    unauthorized || notRunning => ExitCode.notRunning,
    appClosed => ExitCode.appClosed,
  };
}

class ControlError implements Exception {
  const ControlError(this.kind, this.message);

  final ControlErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// The codes the client exits with.
abstract final class ExitCode {
  static const ok = 0;
  static const jobsFailed = 1;
  static const notRunning = 2;
  static const timeout = 3;
  static const appClosed = 4;
  static const badArguments = 5;
  static const ffmpegMissing = 6;
}

sealed class ControlMessage {
  const ControlMessage();
}

class ControlRequest extends ControlMessage {
  const ControlRequest(this.id, this.method, this.params);

  final int id;
  final String method;
  final Map<String, Object?> params;
}

class ControlResponse extends ControlMessage {
  const ControlResponse(this.id, {this.result, this.error});

  final int id;
  final Object? result;
  final ControlError? error;
}

/// A message that wants no answer: an event from the window.
class ControlNotification extends ControlMessage {
  const ControlNotification(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
}

/// Error codes are the kind's position plus this, clear of JSON-RPC's own.
const _errorCodeBase = 1000;

/// One line of JSON-RPC 2.0, without a line break inside.
String encodeMessage(ControlMessage m) {
  final Map<String, Object?> json = switch (m) {
    ControlRequest() => {'id': m.id, 'method': m.method, 'params': m.params},
    ControlNotification() => {'method': m.method, 'params': m.params},
    ControlResponse(:final error) when error != null => {
      'id': m.id,
      'error': {
        'code': error.kind.index + _errorCodeBase,
        'message': error.message,
        'data': {'kind': error.kind.name},
      },
    },
    ControlResponse() => {'id': m.id, 'result': m.result},
  };
  return jsonEncode({'jsonrpc': '2.0', ...json});
}

/// Throws [FormatException] for anything that is not a request, a response
/// or a notification.
ControlMessage decodeMessage(String line) {
  final Object? json;
  try {
    json = jsonDecode(line);
  } on FormatException {
    throw const FormatException('Not JSON');
  }
  if (json is! Map<String, Object?> || json['jsonrpc'] != '2.0') {
    throw const FormatException('Not JSON-RPC 2.0');
  }
  final id = json['id'];
  final method = json['method'];
  if (id != null && id is! int) throw const FormatException('Bad id');
  if (method != null) {
    if (method is! String) throw const FormatException('Bad method');
    final params = json['params'] ?? <String, Object?>{};
    if (params is! Map<String, Object?>) {
      throw const FormatException('Bad params');
    }
    return id == null
        ? ControlNotification(method, params)
        : ControlRequest(id as int, method, params);
  }
  if (id is int) {
    final error = json['error'];
    if (error == null && json.containsKey('result')) {
      return ControlResponse(id, result: json['result']);
    }
    if (error is Map<String, Object?>) {
      final data = error['data'];
      final kind = data is Map<String, Object?> ? data['kind'] : null;
      return ControlResponse(
        id,
        error: ControlError(
          ControlErrorKind.values.firstWhere(
            (k) => k.name == kind,
            orElse: () => ControlErrorKind.badArgument,
          ),
          '${error['message'] ?? ''}',
        ),
      );
    }
  }
  throw const FormatException('Not a request, response or notification');
}

/// What a client can ask for.
abstract final class Methods {
  static const hello = 'hello';
  static const status = 'status';
  static const goals = 'goals';
  static const videosAdd = 'videos.add';
  static const videosList = 'videos.list';
  static const videosRemove = 'videos.remove';
  static const videosDetails = 'videos.details';
  static const videosEstimate = 'videos.estimate';
  static const queueList = 'queue.list';
  static const queueAdd = 'queue.add';
  static const queueRemove = 'queue.remove';
  static const queueMove = 'queue.move';
  static const queueRetry = 'queue.retry';
  static const queueClearFinished = 'queue.clearFinished';
  static const queuePause = 'queue.pause';
  static const queueResume = 'queue.resume';
  static const queueCancel = 'queue.cancel';
  static const queueConvertAnyway = 'queue.convertAnyway';
  static const queueConvertWhole = 'queue.convertWhole';
  static const jobGet = 'job.get';
  static const jobCompare = 'job.compare';
  static const wait = 'wait';
  static const subscribe = 'subscribe';
}

/// What the window tells a subscribed client.
abstract final class Events {
  static const snapshot = 'snapshot';
  static const videoAdded = 'video-added';
  static const videoReady = 'video-ready';
  static const videoUnreadable = 'video-unreadable';
  static const videoRemoved = 'video-removed';
  static const jobAdded = 'job-added';
  static const jobChecking = 'job-checking';
  static const jobStarted = 'job-started';
  static const jobProgress = 'job-progress';
  static const jobFinished = 'job-finished';
  static const jobRemoved = 'job-removed';
  static const queuePaused = 'queue-paused';
  static const queueResumed = 'queue-resumed';
  static const queueIdle = 'queue-idle';
  static const compareFinished = 'compare-finished';
  static const appClosing = 'app-closing';
}
