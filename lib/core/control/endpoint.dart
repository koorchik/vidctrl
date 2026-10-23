import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Where the open window listens, and the secret a client must present.
/// The window writes it when it starts listening and removes it on closing.
class Endpoint {
  const Endpoint({
    required this.port,
    required this.token,
    required this.pid,
    required this.version,
    required this.protocol,
  });

  final int port;
  final String token;
  final int pid;
  final String version;
  final int protocol;

  Map<String, Object?> toJson() => {
    'port': port,
    'token': token,
    'pid': pid,
    'version': version,
    'protocol': protocol,
  };

  /// Null for anything that is not a whole endpoint.
  static Endpoint? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final port = json['port'];
    final token = json['token'];
    final pid = json['pid'];
    final version = json['version'];
    final protocol = json['protocol'];
    if (port is! int ||
        token is! String ||
        pid is! int ||
        version is! String ||
        protocol is! int) {
      return null;
    }
    return Endpoint(
      port: port,
      token: token,
      pid: pid,
      version: version,
      protocol: protocol,
    );
  }
}

/// The endpoint file's place for [os] (a `Platform.operatingSystem` value),
/// in a folder only this user can reach where the system has one.
String endpointPath({
  required String os,
  required Map<String, String> environment,
}) {
  switch (os) {
    case 'windows':
      return p.windows.join(
        environment['LOCALAPPDATA'] ?? '',
        'VidCtrl',
        'control.json',
      );
    case 'macos':
      return p.posix.join(
        environment['HOME'] ?? '',
        'Library',
        'Application Support',
        'app.camctrl.vidctrl',
        'control.json',
      );
    default:
      final runtime = environment['XDG_RUNTIME_DIR'];
      final base = runtime != null && runtime.isNotEmpty
          ? runtime
          : p.posix.join(environment['HOME'] ?? '', '.cache');
      return p.posix.join(base, 'vidctrl', 'control.json');
  }
}

class EndpointFile {
  EndpointFile(this.path);

  final String path;

  static EndpointFile forThisUser() => EndpointFile(
    endpointPath(
      os: Platform.operatingSystem,
      environment: Platform.environment,
    ),
  );

  /// Null when the file is missing or damaged.
  Future<Endpoint?> read() async {
    try {
      return Endpoint.fromJson(jsonDecode(await File(path).readAsString()));
    } on Object {
      return null;
    }
  }

  Future<void> write(Endpoint e) async {
    final file = File(path);
    final folder = file.parent;
    final unixLike = Platform.isLinux || Platform.isMacOS;
    final folderIsNew = !await folder.exists();
    await folder.create(recursive: true);
    // A folder made here, like ~/.cache/vidctrl, is for this user only.
    if (unixLike && folderIsNew) await _chmod('700', folder.path);
    // Written aside and renamed, so a client never reads half a file. The
    // file is made empty and restricted before the token goes in, so the
    // token is never readable by others.
    final temporary = File('$path.tmp');
    try {
      await temporary.writeAsString('');
      if (unixLike) await _chmod('600', temporary.path);
      await temporary.writeAsString(jsonEncode(e.toJson()));
      await temporary.rename(path);
    } on Object {
      try {
        await temporary.delete();
      } on Object {
        // Nothing left to clean.
      }
      rethrow;
    }
  }

  static Future<void> _chmod(String mode, String target) async {
    final result = await Process.run('chmod', [mode, target]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${result.stderr}', target);
    }
  }

  Future<void> delete() async {
    try {
      await File(path).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}

/// A secret for one run of the window: 32 random bytes, URL-safe.
String newToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
