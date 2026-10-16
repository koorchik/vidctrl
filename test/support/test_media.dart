import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vidctrl/core/ffmpeg/locator.dart';

/// Generates small synthetic clips that stand in for real camera files, so
/// conversion tests need no footage in the repository.
class TestMedia {
  TestMedia._(this.paths, this.dir);

  final FfmpegPaths paths;
  final Directory dir;

  /// Returns null when FFmpeg is not installed, so tests can skip.
  static Future<TestMedia?> create() async {
    final paths = FfmpegLocator().locate();
    if (paths == null) return null;
    final dir = await Directory.systemTemp.createTemp('vidctrl_test_');
    return TestMedia._(paths, dir);
  }

  Future<void> dispose() => dir.delete(recursive: true);

  String file(String name) => p.join(dir.path, name);

  /// Makes a clip of a moving test pattern with a tone.
  ///
  /// [video] and [audio] are FFmpeg encoder arguments; pass an empty [audio]
  /// list for a silent file.
  Future<String> clip(
    String name, {
    List<String> video = const ['-c:v', 'libx264', '-preset', 'ultrafast'],
    String pixFmt = 'yuv420p',
    List<String> audio = const ['-c:a', 'aac'],
    String size = '320x240',
    String rate = '25',
    double seconds = 2,
    List<String> filters = const [],
    List<String> extra = const [],
  }) async {
    final path = file(name);
    await ffmpeg([
      '-f',
      'lavfi',
      '-i',
      'testsrc2=s=$size:r=$rate:d=$seconds',
      if (audio.isNotEmpty) ...[
        '-f',
        'lavfi',
        '-i',
        'sine=r=48000:d=$seconds',
        '-ac',
        '2',
      ],
      ...video,
      if (filters.isNotEmpty) ...['-vf', filters.join(',')],
      '-pix_fmt',
      pixFmt,
      ...audio,
      ...extra,
      path,
    ]);
    return path;
  }

  /// Runs FFmpeg for fixtures [clip] cannot express.
  Future<void> ffmpeg(List<String> args) async {
    final result = await Process.run(
      paths.ffmpeg,
      ['-hide_banner', '-loglevel', 'error', '-y', ...args],
      environment: const {'SVT_LOG': '1'},
    );
    if (result.exitCode != 0) {
      throw StateError('could not create test clip: ${result.stderr}');
    }
  }

  /// One ffprobe value per stream, e.g. `streams(path, 'codec_name')`.
  Future<List<String>> streams(String path, String entry) async {
    final result = await Process.run(paths.ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'stream=$entry',
      '-of',
      'json',
      path,
    ]);
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return [
      for (final stream in json['streams'] as List<dynamic>)
        '${(stream as Map<String, dynamic>)[entry] ?? ''}',
    ];
  }

  /// A fingerprint of the video stream's compressed data. Equal fingerprints
  /// mean the picture was copied bit for bit, not re-encoded.
  Future<String> videoFingerprint(String path) async {
    final result = await Process.run(paths.ffmpeg, [
      '-v',
      'error',
      '-i',
      path,
      '-map',
      '0:v:0',
      '-c',
      'copy',
      '-f',
      'hash',
      '-',
    ]);
    return (result.stdout as String).trim();
  }
}
