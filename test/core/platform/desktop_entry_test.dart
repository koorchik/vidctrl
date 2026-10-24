// Desktop entries are how Linux desktops find an app's icon.
@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/platform/desktop_entry.dart';

void main() {
  late Directory scratch;
  late String dataHome;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('desktop_entry_test');
    dataHome = p.join(scratch.path, 'share');
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  /// A built app at [folder] with the icons the Linux build puts beside it.
  String bundle(String folder, {List<int> sizes = const [16, 256]}) {
    final icons = Directory(p.join(scratch.path, folder, 'data', 'icons'))
      ..createSync(recursive: true);
    for (final size in sizes) {
      File(p.join(icons.path, 'app_icon_$size.png'))
          .writeAsStringSync('icon $size');
    }
    return p.join(scratch.path, folder, 'vidctrl');
  }

  File entryFile() =>
      File(p.join(dataHome, 'applications', '$linuxApplicationId.desktop'));

  File iconFile(int size) => File(
    p.join(
      dataHome,
      'icons',
      'hicolor',
      '${size}x$size',
      'apps',
      '$linuxApplicationId.png',
    ),
  );

  test('names an entry after the window, with the app\'s icon', () async {
    final app = bundle('bundle');

    expect(
      await registerDesktopEntry(executable: app, dataHome: dataHome),
      isTrue,
    );

    final entry = entryFile().readAsStringSync();
    expect(entry, contains('Icon=$linuxApplicationId\n'));
    expect(entry, contains('StartupWMClass=$linuxApplicationId\n'));
    expect(entry, contains('Exec="$app"\n'));
    expect(entry, contains('NoDisplay=true\n'));
    expect(iconFile(16).readAsStringSync(), 'icon 16');
    expect(iconFile(256).readAsStringSync(), 'icon 256');
  });

  test('a second start finds everything in place and writes nothing', () async {
    final app = bundle('bundle');
    await registerDesktopEntry(executable: app, dataHome: dataHome);
    final written = entryFile().lastModifiedSync();

    expect(
      await registerDesktopEntry(executable: app, dataHome: dataHome),
      isFalse,
    );
    expect(entryFile().lastModifiedSync(), written);
  });

  test('an app moved elsewhere is started from its new place', () async {
    await registerDesktopEntry(executable: bundle('old'), dataHome: dataHome);
    final moved = bundle('new');

    expect(
      await registerDesktopEntry(executable: moved, dataHome: dataHome),
      isTrue,
    );
    expect(entryFile().readAsStringSync(), contains('Exec="$moved"\n'));
  });

  test('a changed icon replaces the one registered', () async {
    final app = bundle('bundle');
    await registerDesktopEntry(executable: app, dataHome: dataHome);
    File(p.join(p.dirname(app), 'data', 'icons', 'app_icon_16.png'))
        .writeAsStringSync('new icon');

    expect(
      await registerDesktopEntry(executable: app, dataHome: dataHome),
      isTrue,
    );
    expect(iconFile(16).readAsStringSync(), 'new icon');
  });

  test('a path with spaces and dollar signs stays one argument', () async {
    final app = bundle(r'My $Apps');

    await registerDesktopEntry(executable: app, dataHome: dataHome);

    final escaped = app.replaceAll(r'$', r'\\$');
    expect(entryFile().readAsStringSync(), contains('Exec="$escaped"\n'));
  });

  test('an app without icons beside it registers nothing', () async {
    final app = bundle('bare', sizes: []);

    expect(
      await registerDesktopEntry(executable: app, dataHome: dataHome),
      isFalse,
    );
    expect(entryFile().existsSync(), isFalse);
  });

  group('where the entry goes', () {
    test('the folder the desktop names', () {
      expect(
        desktopDataHome({
          'XDG_DATA_HOME': '/data/share',
          'HOME': '/home/alice',
        }),
        '/data/share',
      );
    });

    test('the usual folder in the home folder otherwise', () {
      expect(
        desktopDataHome({'HOME': '/home/alice'}),
        '/home/alice/.local/share',
      );
      expect(
        desktopDataHome({'XDG_DATA_HOME': 'relative', 'HOME': '/home/alice'}),
        '/home/alice/.local/share',
      );
    });

    test('nowhere without a home folder', () {
      expect(desktopDataHome({}), isNull);
    });
  });

  test('the identifier is the one the Linux build gives the window', () {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();

    expect(cmake, contains('set(APPLICATION_ID "$linuxApplicationId")'));
  });
}
