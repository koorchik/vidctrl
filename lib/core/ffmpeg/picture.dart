import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Runs [ffmpeg] with [args], which write one picture to its output, and
/// returns that picture. Null when it could not be made: FFmpeg missing or
/// failing, nothing written, or no answer within [timeout], when FFmpeg is
/// stopped.
Future<Uint8List?> ffmpegPicture(
  String ffmpeg,
  List<String> args, {
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(ffmpeg, args);
  } on ProcessException {
    return null;
  }
  final bytes = BytesBuilder(copy: false);
  final reading = process.stdout.forEach(bytes.add);
  unawaited(process.stderr.drain<void>());
  try {
    final exitCode = await process.exitCode.timeout(timeout);
    await reading;
    return exitCode == 0 && bytes.isNotEmpty ? bytes.takeBytes() : null;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return null;
  }
}
