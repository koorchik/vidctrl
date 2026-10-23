import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/control/manual.dart';
import '../../l10n/app_localizations.dart';

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

/// The folder of the app's own program, where `vidctrl-client` belongs (on
/// macOS `Contents/MacOS`); tests set another.
final appFolderProvider = Provider<String>(
  (ref) => p.dirname(Platform.resolvedExecutable),
);

/// The `vidctrl-client` beside this app, or null. Looked for again each
/// time "Use with an AI agent" opens, so a client built while the app runs
/// is found.
final clientExecutableProvider = Provider.autoDispose<String?>(
  (ref) => clientExecutable(
    appExecutable: Platform.resolvedExecutable,
    os: ref.watch(operatingSystemProvider),
    exists: (path) => File(path).existsSync(),
  ),
);

/// What builds `vidctrl-client` into [appFolder], run in the project's
/// folder: for a development build, which has none beside it.
String buildClientCommand(String appFolder, {required String os}) =>
    'tool/build_client.sh ${shellWord(appFolder, os: os)}';

/// What "Use with an AI agent" gives to paste into an agent, in the app's
/// language: what the program at [clientPath] is, quoted for [os]'s
/// terminal, and to read its manual. In English it is the client's
/// [quickStart].
String agentPrompt(
  AppLocalizations l10n, {
  required String clientPath,
  required String os,
}) {
  final c = shellWord(clientPath, os: os);
  return [
    l10n.agentPromptIntro(c),
    '',
    l10n.agentPromptManual(c),
    if (needsCallOperator(clientPath, os: os)) l10n.agentPromptPowerShell(c),
    '',
  ].join('\n');
}
