import 'dart:io';

import 'package:path/path.dart' as p;

/// The identifier the Linux build gives the app's window
/// (`APPLICATION_ID` in `linux/CMakeLists.txt`).
const linuxApplicationId = 'app.camctrl.vidctrl';

/// Lets a Linux desktop show the app's icon on its window.
///
/// A Wayland desktop does not take the icon from the window: it looks for a
/// desktop entry named after the window's identifier and shows the icon that
/// entry names; without one the taskbar shows a generic icon. There is no
/// installer to put one in place, so the app registers its own for the
/// current user, under [dataHome], with the icons the build put beside
/// [executable] (`data/icons/app_icon_<size>.png`). The entry is hidden from
/// the application menu and starts the app from where it is now.
///
/// Writes only what is missing or out of date, so a second start leaves the
/// files alone. Returns whether anything was written.
Future<bool> registerDesktopEntry({
  required String executable,
  required String dataHome,
}) async {
  final icons = await _bundledIcons(executable);
  if (icons.isEmpty) return false;
  var changed = false;
  for (final MapEntry(key: size, value: icon) in icons.entries) {
    final target = p.join(
      dataHome,
      'icons',
      'hicolor',
      '${size}x$size',
      'apps',
      '$linuxApplicationId.png',
    );
    changed |= await _writeIfChanged(target, await icon.readAsBytes());
  }
  final entry = p.join(dataHome, 'applications', '$linuxApplicationId.desktop');
  changed |= await _writeIfChanged(entry, _entry(executable).codeUnits);
  return changed;
}

/// Where the desktop looks for the current user's entries and icons:
/// `$XDG_DATA_HOME`, else `~/.local/share`. Null without a home folder.
String? desktopDataHome(Map<String, String> environment) {
  final named = environment['XDG_DATA_HOME'];
  if (named != null && p.isAbsolute(named)) return named;
  final home = environment['HOME'];
  if (home == null || home.isEmpty) return null;
  return p.join(home, '.local', 'share');
}

/// The icons beside [executable], by size in pixels.
Future<Map<int, File>> _bundledIcons(String executable) async {
  final folder = Directory(p.join(p.dirname(executable), 'data', 'icons'));
  if (!await folder.exists()) return {};
  final name = RegExp(r'^app_icon_(\d+)\.png$');
  return {
    await for (final file in folder.list())
      if (file is File)
        if (name.firstMatch(p.basename(file.path)) case final match?)
          int.parse(match.group(1)!): file,
  };
}

String _entry(String executable) =>
    '''
[Desktop Entry]
Type=Application
Name=VidCtrl
Icon=$linuxApplicationId
Exec=${_execArgument(executable)}
StartupWMClass=$linuxApplicationId
NoDisplay=true
''';

/// [path] as one argument of an entry's `Exec`: quoted, with the characters
/// special inside quotes escaped, then escaped again as the entry's string
/// values are (a backslash is written twice), and `%` doubled.
String _execArgument(String path) {
  final quoted = path.replaceAllMapped(
    RegExp(r'["`$\\]'),
    (match) => '\\${match[0]}',
  );
  return '"${quoted.replaceAll(r'\', r'\\').replaceAll('%', '%%')}"';
}

/// Writes [bytes] to [path] unless it already holds them. Written aside and
/// renamed, so the desktop never reads a half-written file.
Future<bool> _writeIfChanged(String path, List<int> bytes) async {
  final file = File(path);
  if (await file.exists() && _same(await file.readAsBytes(), bytes)) {
    return false;
  }
  await file.parent.create(recursive: true);
  final temporary = File('$path.$pid.tmp');
  await temporary.writeAsBytes(bytes);
  await temporary.rename(path);
  return true;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
