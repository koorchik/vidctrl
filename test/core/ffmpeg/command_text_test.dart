import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/command_text.dart';

void main() {
  const args = [
    '-hide_banner',
    '-i',
    "/videos/my trip's clip.mp4",
    '-map',
    '0:v:0',
    '-map',
    '0:a?',
    '-c:v',
    'libx265',
    '-crf',
    '20',
    '-c:a',
    'copy',
    '-f',
    'mp4',
    '/videos/Converted/my trip_hevc.mp4',
  ];

  String describe(CommandPart part) => part.meaning.name;

  group('one line', () {
    test('bash quotes spaces, apostrophes and wildcards', () {
      expect(
        singleLineCommand('ffmpeg', args, shell: ShellStyle.posix),
        "ffmpeg -hide_banner -i '/videos/my trip'\\''s clip.mp4' "
        "-map 0:v:0 -map '0:a?' -c:v libx265 -crf 20 -c:a copy -f mp4 "
        "'/videos/Converted/my trip_hevc.mp4'",
      );
    });

    test('PowerShell quotes options it would otherwise reinterpret', () {
      final line = singleLineCommand('ffmpeg', [
        '-c:v',
        'copy',
        '-i',
        r"C:\Videos\it's here.mp4",
      ], shell: ShellStyle.powershell);

      expect(line, r"ffmpeg '-c:v' copy '-i' 'C:\Videos\it''s here.mp4'");
    });
  });

  group('splitting', () {
    test('pairs each option with its value and names what it does', () {
      final parts = splitCommand(args);

      expect(parts.map((p) => p.args.join(' ')), [
        '-hide_banner',
        "-i /videos/my trip's clip.mp4",
        '-map 0:v:0',
        '-map 0:a?',
        '-c:v libx265',
        '-crf 20',
        '-c:a copy',
        '-f mp4',
        '/videos/Converted/my trip_hevc.mp4',
      ]);
      expect(parts.map((p) => p.meaning), [
        ArgMeaning.hideBanner,
        ArgMeaning.input,
        ArgMeaning.keepPicture,
        ArgMeaning.keepSound,
        ArgMeaning.pictureEncoder,
        ArgMeaning.quality,
        ArgMeaning.soundCopy,
        ArgMeaning.container,
        ArgMeaning.output,
      ]);
    });

    test('a negative value is a value, not another option', () {
      final parts = splitCommand(['-map_metadata', '-1', 'out.mp4']);

      expect(parts.first.args, ['-map_metadata', '-1']);
      expect(parts.first.meaning, ArgMeaning.dropMetadata);
    });

    test('keeping the camera tags and dropping a stale one are told apart', () {
      final parts = splitCommand([
        '-movflags',
        '+faststart',
        '-movflags',
        '+faststart+use_metadata_tags',
        '-metadata',
        'major_brand=',
        '-maxrate',
        '40M',
        'out.mp4',
      ]);

      expect(parts.map((p) => p.meaning).take(4), [
        ArgMeaning.fastStart,
        ArgMeaning.fastStartKeepingTags,
        ArgMeaning.dropTag,
        ArgMeaning.levelLimit,
      ]);
    });
  });

  group('explained', () {
    test('bash form has one commented option per line', () {
      final text = explainedCommand(
        'ffmpeg',
        ['-hide_banner', '-crf', '20', 'out.mp4'],
        describe: describe,
        shell: ShellStyle.posix,
      );

      expect(text, '''
args=(
  -hide_banner  # hideBanner
  -crf 20       # quality
  out.mp4       # output
)
ffmpeg "\${args[@]}"''');
    });

    test('a long line gets its comment above, keeping the column', () {
      const path = '/videos/Converted/a rather long name.mp4';
      final text = explainedCommand(
        'ffmpeg',
        ['-crf', '20', path],
        describe: describe,
        shell: ShellStyle.posix,
      );

      expect(text, '''
args=(
  -crf 20  # quality
  # output
  '$path'
)
ffmpeg "\${args[@]}"''');
    });

    test('PowerShell form quotes every element and splats the array', () {
      final text = explainedCommand(
        'ffmpeg',
        ['-crf', '20', r'C:\out.mp4'],
        describe: describe,
        shell: ShellStyle.powershell,
      );

      expect(text, r'''
$ffmpegArgs = @(
  '-crf', '20'  # quality
  'C:\out.mp4'  # output
)
& ffmpeg @ffmpegArgs''');
    });

    test(
      'the bash form runs when pasted and passes every argument intact',
      () async {
        // `printf` stands in for ffmpeg and prints each argument it receives.
        final text = explainedCommand(
          'printf',
          ['%s\n', ...args],
          describe: describe,
          shell: ShellStyle.posix,
        );
        final result = await Process.run('bash', ['-c', text]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect((result.stdout as String).trimRight().split('\n'), args);
      },
      skip: Platform.isWindows ? 'needs bash' : false,
    );

    test('the one-line bash form runs when pasted too', () async {
      final line = singleLineCommand('printf', [
        '%s\n',
        ...args,
      ], shell: ShellStyle.posix);
      final result = await Process.run('bash', ['-c', line]);

      expect((result.stdout as String).trimRight().split('\n'), args);
    }, skip: Platform.isWindows ? 'needs bash' : false);
  });
}
