import 'dart:async';

import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';

import 'codes.dart';

/// The version of the conversation between a client and the window. It goes
/// in the endpoint file and in the `hello` answer.
const controlProtocol = 2;

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

  /// How JSON names it: `BAD_ARGUMENT` and so on.
  String get code => codeOf(this);

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

  /// The error [toRpc] sent. JSON-RPC's own "method not found" is
  /// [ControlErrorKind.unknownMethod]; any other error without a kind of
  /// ours is [ControlErrorKind.badArgument].
  factory ControlError.fromRpc(RpcException e) {
    final data = e.data;
    final kind = fromCode(
      ControlErrorKind.values,
      data is Map ? data['kind'] : null,
    );
    return ControlError(
      kind ??
          (e.code == error_code.METHOD_NOT_FOUND
              ? ControlErrorKind.unknownMethod
              : ControlErrorKind.badArgument),
      e.message,
    );
  }

  final ControlErrorKind kind;
  final String message;

  /// This error as JSON-RPC sends it: a number of the kind's position clear
  /// of JSON-RPC's own, and the kind's code.
  RpcException toRpc() => RpcException(
    _errorCodeBase + kind.index,
    message,
    data: {'kind': kind.code},
  );

  @override
  String toString() => message;
}

const _errorCodeBase = 1000;

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

/// A message that wants no answer: an event from the window.
class ControlNotification {
  const ControlNotification(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
}

/// One JSON value per line, as a channel json_rpc_2 can talk over: [lines]
/// come in without their breaks, and each line to send goes to [write] at
/// once, without one. A line that is not JSON reaches the stream as a
/// [FormatException].
StreamChannel<Object?> jsonLines(
  Stream<String> lines,
  void Function(String line) write,
) {
  final out = StreamController<String>(sync: true);
  out.stream.listen(write);
  return jsonDocument.bind(StreamChannel(lines, out.sink));
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

/// What the window tells a subscribed client, each by its code.
abstract final class Events {
  static const snapshot = 'SNAPSHOT';
  static const videoAdded = 'VIDEO_ADDED';
  static const videoReady = 'VIDEO_READY';
  static const videoUnreadable = 'VIDEO_UNREADABLE';
  static const videoRemoved = 'VIDEO_REMOVED';
  static const jobAdded = 'JOB_ADDED';
  static const jobChecking = 'JOB_CHECKING';
  static const jobStarted = 'JOB_STARTED';
  static const jobProgress = 'JOB_PROGRESS';
  static const jobFinished = 'JOB_FINISHED';
  static const jobRemoved = 'JOB_REMOVED';
  static const queuePaused = 'QUEUE_PAUSED';
  static const queueResumed = 'QUEUE_RESUMED';
  static const queueIdle = 'QUEUE_IDLE';
  static const compareFinished = 'COMPARE_FINISHED';
  static const appClosing = 'APP_CLOSING';
}
