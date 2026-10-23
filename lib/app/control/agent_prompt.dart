import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/manual.dart';

/// Where `vidctrl-client` is in a download: in the same folder as the app's
/// own program ([appExecutable]), on macOS `Contents/MacOS/` too. Null when
/// it is not there, as in a development build.
String? clientExecutable({
  required String appExecutable,
  required String os,
  required bool Function(String path) exists,
}) {
  final windows = os == 'windows';
  final paths = p.Context(style: windows ? p.Style.windows : p.Style.posix);
  final client = paths.join(
    paths.dirname(appExecutable),
    windows ? 'vidctrl-client.exe' : 'vidctrl-client',
  );
  return exists(client) ? client : null;
}

/// The system the app runs on (`Platform.operatingSystem`), whose terminal
/// the prompt is typed for; tests set another.
final operatingSystemProvider = Provider<String>(
  (ref) => Platform.operatingSystem,
);

/// The `vidctrl-client` beside this app, or null.
final clientExecutableProvider = Provider<String?>(
  (ref) => clientExecutable(
    appExecutable: Platform.resolvedExecutable,
    os: ref.watch(operatingSystemProvider),
    exists: (path) => File(path).existsSync(),
  ),
);

/// English names of the app's languages, for asking the agent to answer in
/// the person's.
const agentLanguageNames = {'en': 'English', 'uk': 'Ukrainian'};

/// What "Use with an AI agent" gives to paste into an agent: the quick start
/// with the program's path quoted for [os]'s terminal, in English like the
/// manual and the program's answers, and a line asking the agent to answer
/// in [languageName] when the person reads another language.
String agentPrompt({
  required String clientPath,
  required String languageName,
  required String os,
}) {
  final start = quickStart(clientPath, os: os);
  if (languageName == 'English') return start;
  return '$start\nAnswer me in $languageName.\n';
}
