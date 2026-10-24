import 'dart:async';
import 'dart:typed_data';

import '../ffmpeg/command_builder.dart';
import '../ffmpeg/picture.dart';
import '../media/ffprobe.dart';

/// The two pictures of one frame a person compares: the original's and the
/// result's, at full size.
class FramePair {
  const FramePair({required this.original, required this.result});

  final Uint8List original;
  final Uint8List result;
}

/// Grabs single frames at full size, without loss, so a person can compare
/// a result with its original where it differs most.
///
/// Both pictures are turned into RGB the same, exact way. FFmpeg's quicker
/// default takes another path for 8-bit pictures than for 10-bit ones, and
/// an 8-bit original then looked darker and more contrasty than its 10-bit
/// copy, a difference that is not in the files.
class FrameGrabber {
  FrameGrabber(this.ffmpeg, {this.timeout = const Duration(seconds: 60)});

  final String ffmpeg;
  final Duration timeout;

  /// A PNG of the [frame]th frame after [seek] in [path], counted from 0.
  /// Null when it could not be read.
  Future<Uint8List?> grab(
    String path, {
    Duration seek = Duration.zero,
    required int frame,
  }) async {
    return ffmpegPicture(ffmpeg, [
      '-hide_banner',
      '-nostdin',
      '-v', 'error',
      // Before the input and to the millisecond, as the piece was cut and
      // compared, so frames are counted from the same one: a finer seek
      // can land a frame later.
      if (seek > Duration.zero) ...['-ss', ffmpegSeconds(seek)],
      '-i', inputUrl(path),
      '-map', '0:v:0',
      '-vf',
      'select=eq(n\\,$frame),'
          'scale=flags=accurate_rnd+full_chroma_int,format=rgb24',
      '-frames:v', '1',
      '-c:v', 'png',
      '-f', 'image2pipe',
      'pipe:1',
    ], timeout: timeout);
  }

  /// The same frame of [original] and [result]. [result] is either the
  /// encoded piece itself ([resultSeek] zero) or a whole converted video
  /// ([resultSeek] the piece's start, like [originalSeek]). Null when either
  /// could not be read.
  Future<FramePair?> pair({
    required String original,
    required Duration originalSeek,
    required String result,
    required Duration resultSeek,
    required int frame,
  }) async {
    final pictures = await Future.wait([
      grab(original, seek: originalSeek, frame: frame),
      grab(result, seek: resultSeek, frame: frame),
    ]);
    final [originalPicture, resultPicture] = pictures;
    if (originalPicture == null || resultPicture == null) return null;
    return FramePair(original: originalPicture, result: resultPicture);
  }
}
