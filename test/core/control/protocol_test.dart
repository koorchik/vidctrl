import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/control/protocol.dart';

void main() {
  test('a request survives encoding and decoding', () {
    final line = encodeMessage(
      const ControlRequest(7, 'queue.add', {'goal': 'archive'}),
    );
    expect(line, isNot(contains('\n')));
    expect(line, contains('"jsonrpc":"2.0"'));
    final back = decodeMessage(line) as ControlRequest;
    expect(
      [back.id, back.method, back.params],
      [
        7,
        'queue.add',
        {'goal': 'archive'},
      ],
    );
  });

  test('a notification has no id and keeps its parameters', () {
    final line = encodeMessage(
      const ControlNotification(Events.jobFinished, {'id': 'j1'}),
    );
    final back = decodeMessage(line) as ControlNotification;
    expect(
      [back.method, back.params],
      [
        'job-finished',
        {'id': 'j1'},
      ],
    );
  });

  test('a result survives encoding and decoding', () {
    final line = encodeMessage(const ControlResponse(2, result: {'n': 1}));
    final back = decodeMessage(line) as ControlResponse;
    expect(
      [back.id, back.result, back.error],
      [
        2,
        {'n': 1},
        null,
      ],
    );
  });

  test('an error carries its kind', () {
    final line = encodeMessage(
      const ControlResponse(
        3,
        error: ControlError(ControlErrorKind.ffmpegMissing, 'no FFmpeg'),
      ),
    );
    final back = decodeMessage(line) as ControlResponse;
    expect(back.error!.kind, ControlErrorKind.ffmpegMissing);
    expect(back.error!.message, 'no FFmpeg');
    expect(back.error!.kind.exitCode, ExitCode.ffmpegMissing);
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

  test('a line that is not JSON-RPC is refused', () {
    expect(() => decodeMessage('POST / HTTP/1.1'), throwsFormatException);
    expect(() => decodeMessage('{"jsonrpc":"2.0"}'), throwsFormatException);
    expect(() => decodeMessage('[1]'), throwsFormatException);
    expect(
      () => decodeMessage('{"jsonrpc":"1.0","id":1,"method":"x"}'),
      throwsFormatException,
    );
  });

  test('method names are dotted with camelCase after the dot', () {
    expect(Methods.videosAdd, 'videos.add');
    expect(Methods.queueClearFinished, 'queue.clearFinished');
    expect(Methods.jobGet, 'job.get');
    expect(Events.appClosing, 'app-closing');
  });
}
