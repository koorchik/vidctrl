import 'dart:io';

import 'package:vidctrl/core/control/client.dart';

Future<void> main(List<String> args) async {
  final code = await runClient(
    args,
    ClientIo(
      out: stdout,
      err: stderr,
      environment: Platform.environment,
      workingDirectory: Directory.current.path,
      executable: Platform.resolvedExecutable,
    ),
  );
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
