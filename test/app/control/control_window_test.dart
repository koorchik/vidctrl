import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/control/control_controller.dart';
import 'package:vidctrl/app/home/home_screen.dart';
import 'package:vidctrl/app/home/widgets/queue_pane.dart';
import 'package:vidctrl/app/home/widgets/videos_pane.dart';
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/protocol.dart';

import '../../support/control.dart';
import '../../support/fakes.dart';
import '../../support/pump_app.dart';

void main() {
  testWidgets('what a client adds and queues shows in the window', (
    tester,
  ) async {
    final env = FakeEnvironment();
    final folder = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('vidctrl_window_'),
    ))!;
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'a.mp4');
    File(path).writeAsStringSync('');
    env.ffprobe.add(path);

    await pumpApp(tester, env);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final control = container.read(controlProvider.notifier);
    ControlConnection? client;
    addTearDown(
      () => tester.runAsync(() async {
        await client?.close();
        await control.stop();
      }),
    );

    await tester.runAsync(() async {
      // What the window does for a client completes on the test's clock,
      // which stands still unless pumped.
      final pumping = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => tester.pump(),
      );
      await control.start(file: controlFile(folder));
      client = await connectIfLive(controlFile(folder));
      final answer = await client!.call(Methods.videosAdd, {
        'paths': [path],
      }) as Map;
      final id = ((answer['videos'] as List).single as Map)['id'];
      await client!.call(Methods.queueAdd, {
        'videos': [id],
      });
      pumping.cancel();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byType(VideosPane),
        matching: find.text('a.mp4'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(of: find.byType(QueuePane), matching: find.text('a.mp4')),
      findsOneWidget,
    );
  });
}
