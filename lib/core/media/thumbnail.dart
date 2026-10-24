import 'dart:async';
import 'dart:typed_data';

import '../ffmpeg/picture.dart';
import 'ffprobe.dart';

/// Grabs a single frame of a video as a small picture, to show which video
/// a window is about.
class Thumbnailer {
  Thumbnailer(this.ffmpeg, {this.timeout = const Duration(seconds: 15)});

  final String ffmpeg;
  final Duration timeout;

  /// A JPEG of the frame at [at], [width] pixels wide. Null when no frame
  /// could be read (not a video, damaged file, FFmpeg took too long).
  Future<Uint8List?> frame(
    String path, {
    Duration at = Duration.zero,
    int width = 480,
  }) async {
    return ffmpegPicture(ffmpeg, [
      '-hide_banner',
      '-nostdin',
      '-v', 'error',
      // Before the input, so FFmpeg jumps there instead of decoding
      // everything up to that point.
      '-ss', (at.inMilliseconds / 1000).toStringAsFixed(3),
      '-i', inputUrl(path),
      '-frames:v', '1',
      '-vf', 'scale=$width:-2',
      '-c:v', 'mjpeg',
      '-q:v', '4',
      '-f', 'image2pipe',
      'pipe:1',
    ], timeout: timeout);
  }
}
