import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the FFmpeg in use was found.
enum FfmpegSource {
  /// A folder the user chose.
  chosen,

  /// The copy that comes inside the app.
  bundled,

  /// One installed on the computer: on the `PATH`, or Homebrew's on macOS.
  system,
}

class FfmpegPaths {
  const FfmpegPaths({
    required this.ffmpeg,
    required this.ffprobe,
    required this.source,
  });

  final String ffmpeg;
  final String ffprobe;
  final FfmpegSource source;
}

/// Finds the FFmpeg and ffprobe executables to use.
///
/// Order: a folder the user chose, then the copy shipped inside the app
/// bundle, then the computer's own. The bundled copy is the supported one;
/// the computer's is the fallback for development, where nothing is bundled.
/// A chosen folder that no longer holds FFmpeg is passed over.
class FfmpegLocator {
  FfmpegLocator({
    String? executableDir,
    Map<String, String>? environment,
    bool? isWindows,
    bool? isMacOS,
    bool Function(String path)? exists,
  }) : _executableDir = executableDir ?? p.dirname(Platform.resolvedExecutable),
       _environment = environment ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _exists = exists ?? ((path) => File(path).existsSync());

  final String _executableDir;
  final Map<String, String> _environment;
  final bool _isWindows;
  final bool _isMacOS;
  final bool Function(String path) _exists;

  p.Context get _context => _isWindows ? p.windows : p.posix;

  FfmpegPaths? locate({String? overrideDir}) {
    final candidates = [
      if (overrideDir != null) (overrideDir, FfmpegSource.chosen),
      // Linux bundle: <bundle>/lib/ffmpeg next to the app binary.
      (_context.join(_executableDir, 'lib', 'ffmpeg'), FfmpegSource.bundled),
      // Windows: next to the .exe. macOS: Contents/MacOS.
      (_executableDir, FfmpegSource.bundled),
      for (final dir in (_environment['PATH'] ?? '').split(
        _isWindows ? ';' : ':',
      ))
        if (dir.isNotEmpty) (dir, FfmpegSource.system),
      // An app opened from the Finder gets a PATH without Homebrew's folders.
      if (_isMacOS) ...[
        ('/opt/homebrew/bin', FfmpegSource.system),
        ('/usr/local/bin', FfmpegSource.system),
      ],
    ];
    for (final (dir, source) in candidates) {
      final paths = inFolder(dir, source: source);
      if (paths != null) return paths;
    }
    return null;
  }

  /// The FFmpeg in [dir], or null when it does not hold both programs.
  FfmpegPaths? inFolder(
    String dir, {
    FfmpegSource source = FfmpegSource.chosen,
  }) {
    final suffix = _isWindows ? '.exe' : '';
    final ffmpeg = _context.join(dir, 'ffmpeg$suffix');
    final ffprobe = _context.join(dir, 'ffprobe$suffix');
    if (!_exists(ffmpeg) || !_exists(ffprobe)) return null;
    return FfmpegPaths(ffmpeg: ffmpeg, ffprobe: ffprobe, source: source);
  }
}
