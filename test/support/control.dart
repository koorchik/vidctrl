import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/control/control_controller.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/protocol.dart';

import 'fakes.dart';
import 'machine_json.dart';

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

/// Everything the window has told a client unasked, in order; each must be
/// fit for a program ([expectMachineJson]).
class Heard {
  Heard(ControlConnection client) {
    client.notifications.listen((notification) {
      // Each event as `events --json` prints it.
      expectMachineJson({'event': notification.method, ...notification.params});
      all.add(notification);
      for (final (matches, found) in [..._awaited]) {
        if (!matches(notification)) continue;
        _awaited.remove((matches, found));
        found.complete(notification);
      }
    });
  }

  final all = <ControlNotification>[];
  final _awaited =
      <(bool Function(ControlNotification), Completer<ControlNotification>)>[];

  /// The names of all notifications so far.
  List<String> get names => [for (final n in all) n.method];

  /// The first notification named [method] (and, with [job], about that
  /// job), heard already or within two seconds.
  Future<ControlNotification> first(String method, {int? job}) {
    bool matches(ControlNotification n) =>
        n.method == method &&
        (job == null || (n.params['id'] ?? n.params['job']) == job);
    for (final notification in all) {
      if (matches(notification)) return Future.value(notification);
    }
    final found = Completer<ControlNotification>();
    _awaited.add((matches, found));
    return found.future.timeout(const Duration(seconds: 2));
  }
}

/// The endpoint file a window started on [dir] writes.
EndpointFile controlFile(Directory dir) =>
    EndpointFile(p.join(dir.path, 'control.json'));

Future<Directory> _temporaryFolder() async {
  final dir = await Directory.systemTemp.createTemp('vidctrl_control_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}
