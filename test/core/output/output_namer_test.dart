import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/ffmpeg/locator.dart';
import 'package:vidctrl/core/output/output_namer.dart';

void main() {
  group('output path', () {
    String plan({
      String source = '/videos/trip/clip.mp4',
      OutputSettings settings = const OutputSettings(),
      String suffix = '_resolve',
      String extension = 'mov',
      Set<String> existing = const {},
      Set<String> reserved = const {},
    }) => planOutputPath(
      sourcePath: source,
      settings: settings,
      suffix: suffix,
      extension: extension,
      exists: existing.contains,
      reserved: reserved,
      pathContext: p.posix,
    );

    test('defaults to a "Converted" folder next to the original', () {
      expect(plan(), '/videos/trip/Converted/clip_resolve.mov');
    });

    test('a chosen folder collects everything in one place', () {
      const settings = OutputSettings(
        mode: OutputMode.customFolder,
        customDir: '/exports',
      );

      expect(plan(settings: settings), '/exports/clip_resolve.mov');
    });

    test('an existing file is never overwritten', () {
      expect(
        plan(
          existing: {
            '/videos/trip/Converted/clip_resolve.mov',
            '/videos/trip/Converted/clip_resolve (2).mov',
          },
        ),
        '/videos/trip/Converted/clip_resolve (3).mov',
      );
    });

    test('two sources with the same name get different outputs', () {
      final first = plan(source: '/videos/trip/clip.mp4');
      final second = plan(source: '/videos/trip/clip.mov', reserved: {first});

      expect(second, '/videos/trip/Converted/clip_resolve (2).mov');
    });

    test('the original itself is never the target', () {
      const sameFolder = OutputSettings(
        mode: OutputMode.customFolder,
        customDir: '/videos/trip',
      );

      expect(
        plan(settings: sameFolder, suffix: '', extension: 'mp4'),
        '/videos/trip/clip (2).mp4',
      );
    });

    test('dots in the file name are kept', () {
      expect(
        plan(source: '/videos/2026.05.01 trip.mp4'),
        '/videos/Converted/2026.05.01 trip_resolve.mov',
      );
    });

    test('the in-progress name is hidden and marked partial', () {
      expect(
        temporaryPathFor('/videos/Converted/clip.mov', pathContext: p.posix),
        '/videos/Converted/.clip.mov.part',
      );
    });
  });

  group('FFmpeg locator', () {
    FfmpegLocator locator(Set<String> files, {bool windows = false}) =>
        FfmpegLocator(
          executableDir: windows ? r'C:\App' : '/opt/app',
          environment: {
            'PATH': windows
                ? r'C:\Tools;C:\Windows'
                : '/usr/local/bin:/usr/bin',
          },
          isWindows: windows,
          exists: files.contains,
        );

    test('prefers the copy shipped with the app over the system one', () {
      final paths = locator({
        '/opt/app/lib/ffmpeg/ffmpeg',
        '/opt/app/lib/ffmpeg/ffprobe',
        '/usr/bin/ffmpeg',
        '/usr/bin/ffprobe',
      }).locate();

      expect(paths!.ffmpeg, '/opt/app/lib/ffmpeg/ffmpeg');
    });

    test('falls back to PATH when nothing is bundled', () {
      final paths = locator({'/usr/bin/ffmpeg', '/usr/bin/ffprobe'}).locate();

      expect(paths!.ffprobe, '/usr/bin/ffprobe');
    });

    test('a folder with ffmpeg but no ffprobe does not count', () {
      expect(locator({'/usr/bin/ffmpeg'}).locate(), isNull);
    });

    test('looks for .exe files next to the app on Windows', () {
      final paths = locator({
        r'C:\App\ffmpeg.exe',
        r'C:\App\ffprobe.exe',
      }, windows: true).locate();

      expect(paths!.ffmpeg, r'C:\App\ffmpeg.exe');
    });
  });
}
