import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/locator.dart';

/// A locator on a pretend computer where only [files] exist.
FfmpegLocator _locator(
  Set<String> files, {
  String executableDir = '/opt/vidctrl',
  String path = '/usr/bin',
  bool isWindows = false,
  bool isMacOS = false,
}) => FfmpegLocator(
  executableDir: executableDir,
  environment: {'PATH': path},
  isWindows: isWindows,
  isMacOS: isMacOS,
  exists: files.contains,
);

Set<String> _both(String dir) => {'$dir/ffmpeg', '$dir/ffprobe'};

void main() {
  group('Finding FFmpeg', () {
    test('the copy inside a Linux bundle comes before the PATH', () {
      final paths = _locator({
        ..._both('/opt/vidctrl/lib/ffmpeg'),
        ..._both('/usr/bin'),
      }).locate();

      expect(paths?.ffmpeg, '/opt/vidctrl/lib/ffmpeg/ffmpeg');
      expect(paths?.ffprobe, '/opt/vidctrl/lib/ffmpeg/ffprobe');
      expect(paths?.source, FfmpegSource.bundled);
    });

    test('the copy beside the app counts as bundled (Windows, macOS)', () {
      final paths = _locator(
        {r'C:\VidCtrl\ffmpeg.exe', r'C:\VidCtrl\ffprobe.exe'},
        executableDir: r'C:\VidCtrl',
        path: r'C:\ffmpeg\bin',
        isWindows: true,
      ).locate();

      expect(paths?.ffmpeg, r'C:\VidCtrl\ffmpeg.exe');
      expect(paths?.source, FfmpegSource.bundled);
    });

    test('without a bundled copy the PATH is used, in its order', () {
      final paths = _locator({
        ..._both('/usr/local/bin'),
        ..._both('/usr/bin'),
      }, path: '/usr/local/bin:/usr/bin').locate();

      expect(paths?.ffmpeg, '/usr/local/bin/ffmpeg');
      expect(paths?.source, FfmpegSource.system);
    });

    test('a folder with only one of the two programs is not enough', () {
      expect(_locator({'/usr/bin/ffmpeg'}).locate(), isNull);
    });

    test('on macOS Homebrew is found although the PATH lacks it', () {
      // An app opened from the Finder gets only the system's folders.
      const finderPath = '/usr/bin:/bin:/usr/sbin:/sbin';
      for (final brew in ['/opt/homebrew/bin', '/usr/local/bin']) {
        final paths = _locator(
          _both(brew),
          path: finderPath,
          isMacOS: true,
        ).locate();

        expect(paths?.ffmpeg, '$brew/ffmpeg', reason: brew);
        expect(paths?.source, FfmpegSource.system);
      }
    });

    test('Homebrew is looked in only on macOS', () {
      expect(_locator(_both('/opt/homebrew/bin')).locate(), isNull);
    });
  });
}
