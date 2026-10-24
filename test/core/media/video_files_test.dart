import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/media/video_files.dart';

void main() {
  group('file dialog', () {
    test('on Linux a camera\'s upper-case names are offered too', () {
      final extensions = dialogExtensions(linux: true);
      expect(extensions, containsAll(['[mM][oO][vV]', '[mM]2[tT][sS]']));
      expect(extensions, contains('3[gG][pP]'));
      expect(extensions, hasLength(videoExtensions.length));
    });

    test('elsewhere the dialog is given plain extensions', () {
      expect(dialogExtensions(linux: false), containsAll(['mov', 'm2ts']));
    });
  });

  group('adding a folder', () {
    late Directory folder;
    setUp(() async => folder = await Directory.systemTemp.createTemp());
    tearDown(() => folder.delete(recursive: true));

    Future<void> touch(String relative) async {
      final file = File(p.join(folder.path, relative));
      await file.create(recursive: true);
    }

    test('finds videos whatever the case of their extension', () async {
      for (final name in [
        'DSC_0001.MOV',
        'C0001.MP4',
        'PRIVATE/AVCHD/00000.MTS',
        'clip.Mkv',
        'notes.TXT',
        '.hidden.MOV',
      ]) {
        await touch(name);
      }

      final found = await expandDroppedPaths([folder.path]);

      expect(found.map((f) => p.relative(f, from: folder.path)), [
        'C0001.MP4',
        'DSC_0001.MOV',
        // In the system's own form: backslashes on Windows.
        p.join('PRIVATE', 'AVCHD', '00000.MTS'),
        'clip.Mkv',
      ]);
    });

    test(
      'a subfolder that cannot be read is passed over',
      () async {
        await touch('A001.MOV');
        await touch(p.join('B', 'B001.MOV'));
        // Like a drive's lost+found, readable only by the system.
        final locked = Directory(p.join(folder.path, 'lost+found'));
        await locked.create();
        await Process.run('chmod', ['000', locked.path]);
        addTearDown(() => Process.run('chmod', ['755', locked.path]));

        final found = await expandDroppedPaths([folder.path]);

        expect(found.map((f) => p.relative(f, from: folder.path)), [
          'A001.MOV',
          p.join('B', 'B001.MOV'),
        ]);
      },
      // Windows has no chmod, and root reads every folder.
      skip: Platform.isWindows || _isRoot(),
    );
  });
}

bool _isRoot() =>
    (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
