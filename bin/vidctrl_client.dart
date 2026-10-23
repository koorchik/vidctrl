import 'dart:async';
import 'dart:io';

import 'package:vidctrl/core/control/client.dart';
import 'package:vidctrl/core/control/protocol.dart';

Future<void> main(List<String> args) async {
  // A reader that stopped reading (`events | head`) has had what it wanted:
  // leave quietly, not with a trace of the failed write.
  for (final sink in [stdout, stderr]) {
    unawaited(sink.done.then((_) {}, onError: (Object _) => exit(ExitCode.ok)));
  }
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
