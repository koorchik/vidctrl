// Removes the desktop entry and icons the app registers for the current
// user on Linux (`lib/core/platform/desktop_entry.dart`), through the
// desktop's own `xdg-desktop-menu` and `xdg-icon-resource`:
//
//   dart run tool/desktop_entry.dart --remove
//
// The app writes them itself at each start, so nothing is needed to add
// them. Remove them before changing the application identifier: they are
// found by that name, and the old ones would stay behind.

import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  // The project folder, wherever the tool is started from.
  final project = p.dirname(p.dirname(Platform.script.toFilePath()));
  final id = _applicationId(project);
  final icons = _icons(project);

  if (!arguments.contains('--remove')) {
    _fail(
      'The app registers its desktop entry itself. To remove it: '
      'dart run tool/desktop_entry.dart --remove',
    );
  }
  _run('xdg-desktop-menu', ['uninstall', '$id.desktop']);
  for (final size in icons.keys) {
    _run('xdg-icon-resource', ['uninstall', '--size', '$size', id]);
  }
  stdout.writeln('Removed the desktop entry and icons of $id.');
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
