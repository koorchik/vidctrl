// Makes a Linux desktop show the app's icon while there is no installer to do
// it. For the developer's own computer.
//
// A Wayland desktop does not take the icon from the window. It looks for a
// desktop entry named after the window's application identifier and shows the
// icon that entry names; without one the taskbar shows a generic icon. This
// registers such an entry and the icons for the current user, through the
// desktop's own `xdg-desktop-menu` and `xdg-icon-resource`:
//
//   dart run tool/desktop_entry.dart            # add, or refresh after a change
//   dart run tool/desktop_entry.dart --remove
//
// Run it again after the icon changes. Before changing the application
// identifier, remove the entry: it is found by that name.
//
// The entry is hidden from the application menu. It names no program to
// start, only what the desktop needs to recognise the app's window.

import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  // The project folder, wherever the tool is started from.
  final project = p.dirname(p.dirname(Platform.script.toFilePath()));
  final id = _applicationId(project);
  final icons = _icons(project);

  if (arguments.contains('--remove')) {
    _run('xdg-desktop-menu', ['uninstall', '$id.desktop']);
    for (final size in icons.keys) {
      _run('xdg-icon-resource', ['uninstall', '--size', '$size', id]);
    }
    stdout.writeln('Removed the desktop entry and icons of $id.');
    return;
  }

  // "--novendor": the name must be the identifier exactly, with no prefix.
  for (final MapEntry(key: size, value: file) in icons.entries) {
    _run('xdg-icon-resource', [
      'install',
      '--novendor',
      '--noupdate',
      '--size',
      '$size',
      file,
      id,
    ]);
  }
  _run('xdg-icon-resource', ['forceupdate']);

  final scratch = Directory.systemTemp.createTempSync('desktop_entry');
  try {
    final entry = File(p.join(scratch.path, '$id.desktop'))
      ..writeAsStringSync(_entry(id));
    _run('xdg-desktop-menu', ['install', '--novendor', entry.path]);
  } finally {
    scratch.deleteSync(recursive: true);
  }
  stdout.writeln(
    'Registered the icon for $id. Windows opened from now on show it.',
  );
}

/// The identifier the runner gives its windows, which the desktop looks the
/// entry up by.
String _applicationId(String project) {
  final cmake = File(p.join(project, 'linux', 'CMakeLists.txt'));
  final match = RegExp(r'set\(APPLICATION_ID "([^"]+)"\)')
      .firstMatch(cmake.readAsStringSync());
  if (match == null) _fail('No APPLICATION_ID in ${cmake.path}.');
  return match.group(1)!;
}

/// The icon files written by `tool/make_icons.dart`, by size in pixels.
Map<int, String> _icons(String project) {
  final folder = Directory(p.join(project, 'linux', 'runner', 'resources'));
  final name = RegExp(r'^app_icon_(\d+)\.png$');
  final icons = {
    for (final file in folder.listSync().whereType<File>())
      if (name.firstMatch(p.basename(file.path)) case final match?)
        int.parse(match.group(1)!): file.path,
  };
  if (icons.isEmpty) _fail('No icons in ${folder.path}.');
  return icons;
}

String _entry(String id) =>
    '''
[Desktop Entry]
Type=Application
Name=VidCtrl
Icon=$id
Exec=vidctrl
StartupWMClass=$id
NoDisplay=true
''';

void _run(String program, List<String> arguments) {
  final ProcessResult result;
  try {
    result = Process.runSync(program, arguments);
  } on ProcessException {
    _fail('$program was not found; it comes with the xdg-utils package.');
  }
  if (result.exitCode != 0) {
    _fail('$program ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
