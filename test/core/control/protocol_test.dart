import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:vidctrl/core/control/protocol.dart';

/// A json_rpc_2 server with [methods] and a client talking to it, in memory.
Client _clientOf(Map<String, Object? Function(Parameters)> methods) {
  final wire = StreamChannelController<Object?>();
  final server = Server.withoutJson(wire.local);
  methods.forEach(server.registerMethod);
  unawaited(server.listen());
  final client = Client.withoutJson(wire.foreign);
  unawaited(client.listen());
  addTearDown(client.close);
  addTearDown(server.close);
  return client;
}

/// What [call] fails with, as the client tells it.
Future<ControlError> _failure(Future<Object?> call) async {
  try {
    await call;
  } on RpcException catch (e) {
    return ControlError.fromRpc(e);
  }
  fail('The call did not fail');
}

void main() {
  test('an error reaches the client with its kind', () async {
    final client = _clientOf({
      'videos.add': (_) => throw const ControlError(
        ControlErrorKind.ffmpegMissing,
        'no FFmpeg',
      ).toRpc(),
    });
    final error = await _failure(client.sendRequest('videos.add', {}));
    expect(error.kind, ControlErrorKind.ffmpegMissing);
    expect(error.message, 'no FFmpeg');
    expect(error.kind.exitCode, ExitCode.ffmpegMissing);
  });

  test('every kind of error keeps its kind on the way', () async {
    final client = _clientOf({
      for (final kind in ControlErrorKind.values)
        kind.name: (_) => throw ControlError(kind, kind.name).toRpc(),
    });
    for (final kind in ControlErrorKind.values) {
      final error = await _failure(client.sendRequest(kind.name));
      expect([error.kind, error.message], [kind, kind.name]);
    }
  });

  test('a method the window does not have is an unknown method', () async {
    final client = _clientOf({});
    final error = await _failure(client.sendRequest('videos.shred'));
    expect(error.kind, ControlErrorKind.unknownMethod);
  });

  test('an error of no kind of ours is a bad argument', () async {
    final client = _clientOf({'status': (params) => params['missing'].value});
    final error = await _failure(client.sendRequest('status', {}));
    expect(error.kind, ControlErrorKind.badArgument);
    expect(error.message, contains('missing'));
  });

  test('each kind of error maps to its exit code', () {
    expect(
      {for (final k in ControlErrorKind.values) k: k.exitCode},
      {
        ControlErrorKind.badArgument: 5,
        ControlErrorKind.notFound: 5,
        ControlErrorKind.busy: 5,
        ControlErrorKind.unknownMethod: 5,
        ControlErrorKind.ffmpegMissing: 6,
        ControlErrorKind.unauthorized: 2,
        ControlErrorKind.notRunning: 2,
        ControlErrorKind.appClosed: 4,
      },
    );
  });

  test('method names are dotted with camelCase after the dot', () {
    expect(Methods.videosAdd, 'videos.add');
    expect(Methods.queueClearFinished, 'queue.clearFinished');
    expect(Methods.jobGet, 'job.get');
  });

  test('an error goes on the wire with its code', () {
    expect(
      const ControlError(ControlErrorKind.badArgument, 'no').toRpc().data,
      {'kind': 'BAD_ARGUMENT'},
    );
  });

  test('every event is named by its code', () {
    expect(
      [
        Events.videoAdded,
        Events.videoReady,
        Events.videoUnreadable,
        Events.videoRemoved,
        Events.jobAdded,
        Events.jobChecking,
        Events.jobStarted,
        Events.jobProgress,
        Events.jobFinished,
        Events.jobRemoved,
        Events.queuePaused,
        Events.queueResumed,
        Events.queueIdle,
        Events.compareFinished,
        Events.appClosing,
        Events.snapshot,
      ],
      [
        'VIDEO_ADDED',
        'VIDEO_READY',
        'VIDEO_UNREADABLE',
        'VIDEO_REMOVED',
        'JOB_ADDED',
        'JOB_CHECKING',
        'JOB_STARTED',
        'JOB_PROGRESS',
        'JOB_FINISHED',
        'JOB_REMOVED',
        'QUEUE_PAUSED',
        'QUEUE_RESUMED',
        'QUEUE_IDLE',
        'COMPARE_FINISHED',
        'APP_CLOSING',
        'SNAPSHOT',
      ],
    );
  });
}
