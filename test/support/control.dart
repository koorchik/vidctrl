import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/control/control_controller.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/endpoint.dart';

import 'fakes.dart';

/// A window over [env] that serves clients through the endpoint file in
/// [dir] (a new temporary folder when not given). [environment] stands in for
/// looking for FFmpeg, as `env` would answer at once; with
/// [awaitEnvironment] the window waits until it is answered. Everything is
/// closed when the test ends.
Future<ProviderContainer> startWindow(
  FakeEnvironment env, {
  Directory? dir,
  bool awaitEnvironment = true,
  Future<AppEnvironment> Function()? environment,
}) async {
  final folder = dir ?? await _temporaryFolder();
  final container = ProviderContainer(
    overrides: environment == null
        ? env.overrides
        : [
            environmentProvider.overrideWith((ref) => environment()),
            buildInfoProvider.overrideWithValue(env.build),
            releaseSourceProvider.overrideWithValue(env.releases),
          ],
  );
  addTearDown(container.dispose);
  if (awaitEnvironment) await container.read(environmentProvider.future);
  final control = container.read(controlProvider.notifier);
  addTearDown(control.stop);
  await control.start(file: controlFile(folder));
  return container;
}

/// A window as [startWindow] makes it, and a client connected to it.
Future<(ProviderContainer, ControlConnection)> startControlled(
  FakeEnvironment env, {
  Directory? dir,
  bool awaitEnvironment = true,
  Future<AppEnvironment> Function()? environment,
}) async {
  final folder = dir ?? await _temporaryFolder();
  final container = await startWindow(
    env,
    dir: folder,
    awaitEnvironment: awaitEnvironment,
    environment: environment,
  );
  final client = await connectIfLive(controlFile(folder));
  if (client == null) throw StateError('The window is not serving');
  addTearDown(client.close);
  return (container, client);
}

/// The endpoint file a window started on [dir] writes.
EndpointFile controlFile(Directory dir) =>
    EndpointFile(p.join(dir.path, 'control.json'));

Future<Directory> _temporaryFolder() async {
  final dir = await Directory.systemTemp.createTemp('vidctrl_control_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}
