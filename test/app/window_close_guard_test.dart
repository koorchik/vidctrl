import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/control/control_controller.dart';
import 'package:vidctrl/app/home/home_screen.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/queue/queue_controller.dart';
import 'package:vidctrl/app/window_close_guard.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

/// A control server that fails when asked to stop.
class _FailingControl extends ControlController {
  @override
  Future<void> stop() async => throw const FileSystemException('gone');
}

void main() {
  const plugin = MethodChannel('window_manager');
  const question = 'Stop converting and quit?';

  late FakeEnvironment env;

  /// What the window plugin was asked to do, in order.
  late List<String> asked;

  int timesDestroyed() => asked.where((method) => method == 'destroy').length;

  setUp(() {
    env = FakeEnvironment();
    asked = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      asked.add(call.method);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(plugin, null));
  });

  /// What the window plugin reports when the window is asked to close.
  Future<void> closeWindow(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      plugin.name,
      plugin.codec.encodeMethodCall(
        const MethodCall('onEvent', {'eventName': 'close'}),
      ),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
  }

  /// The app as it runs, with one video in the list.
  Future<void> startApp(WidgetTester tester) async {
    env.ffprobe.add('/videos/a.mp4');
    final sources = await pumpApp(
      tester,
      env,
      home: const WindowCloseGuard(child: HomeScreen()),
    );
    await addVideos(tester, sources, ['/videos/a.mp4']);
  }

  Future<void> startConverting(WidgetTester tester) async {
    await startApp(tester);
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    await tester.pump();
    expect(env.executor.started, hasLength(1));
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    // The dialog's closing animation; a running job never lets it settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('closing the window destroys it only once', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: WindowCloseGuard(child: SizedBox())),
    );

    // The plugin reports the close button, and then again the close that
    // destroying the window causes. Asked to destroy a window that is already
    // gone, it crashes the app.
    await closeWindow(tester);
    await closeWindow(tester);

    expect(timesDestroyed(), 1);
  });

  testWidgets(
    'a control server that cannot stop does not keep FFmpeg running',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          ...env.overrides,
          controlProvider.overrideWith(_FailingControl.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const WindowCloseGuard(child: SizedBox()),
        ),
      );
      await container.read(environmentProvider.future);
      container.read(controlProvider);
      container.read(queueProvider);

      await closeWindow(tester);

      expect(container.read(queueProvider).paused, isTrue);
      expect(timesDestroyed(), 1);
    },
  );

  testWidgets('with nothing converting the window closes without a question', (
    tester,
  ) async {
    await startApp(tester);

    await closeWindow(tester);

    expect(find.text(question), findsNothing);
    expect(timesDestroyed(), 1);
  });

  testWidgets('closing while converting asks first', (tester) async {
    await startConverting(tester);

    await closeWindow(tester);

    expect(find.text(question), findsOneWidget);
    expect(timesDestroyed(), 0);
    expect(env.executor.last.cancelRequested, isFalse);
  });

  testWidgets('"Keep converting" leaves the window and the conversion alone', (
    tester,
  ) async {
    await startConverting(tester);
    await closeWindow(tester);

    await press(tester, 'Keep converting');

    expect(find.text(question), findsNothing);
    expect(timesDestroyed(), 0);
    expect(env.executor.last.cancelRequested, isFalse);

    // And the question comes again the next time.
    await closeWindow(tester);
    expect(find.text(question), findsOneWidget);
  });

  testWidgets('closing again while the question is up does not ask twice', (
    tester,
  ) async {
    await startConverting(tester);

    await closeWindow(tester);
    await closeWindow(tester);

    expect(find.text(question), findsOneWidget);
  });

  testWidgets('"Quit" cancels the conversion and waits for it to stop', (
    tester,
  ) async {
    await startConverting(tester);
    final conversion = env.executor.last..stopsLate = true;
    await closeWindow(tester);

    await press(tester, 'Quit');

    // FFmpeg has been asked to stop but is still finishing its file: leaving
    // now would abandon it and the unfinished file.
    expect(conversion.cancelRequested, isTrue);
    expect(timesDestroyed(), 0);

    conversion.stop();
    await tester.pump();
    await tester.pump();

    expect(timesDestroyed(), 1);
  });

  testWidgets('"Quit" does not start the next video in the queue', (
    tester,
  ) async {
    env.ffprobe.add('/videos/b.mp4');
    env.ffprobe.add('/videos/a.mp4');
    final sources = await pumpApp(
      tester,
      env,
      home: const WindowCloseGuard(child: HomeScreen()),
    );
    await addVideos(tester, sources, ['/videos/a.mp4', '/videos/b.mp4']);
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    await tester.pump();
    await closeWindow(tester);

    await press(tester, 'Quit');
    await tester.pump();

    expect(env.executor.started, hasLength(1));
    expect(timesDestroyed(), 1);
  });

  testWidgets('closing while sizes are being measured stops the measuring', (
    tester,
  ) async {
    env.estimator.hold = true;
    await startApp(tester);
    expect(env.estimator.measured, isNotEmpty);

    await closeWindow(tester);

    expect(find.text(question), findsNothing);
    expect(env.estimator.cancels, 1);
    expect(timesDestroyed(), 1);
  });

  testWidgets('closing while comparing a result stops the comparison', (
    tester,
  ) async {
    await startConverting(tester);
    env.executor.last.finish();
    await tester.pump();
    await tester.tap(find.byTooltip('More').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Compare with the original'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await closeWindow(tester);

    expect(find.text(question), findsNothing);
    expect(env.qualityMeter.last.cancelRequested, isTrue);
    expect(timesDestroyed(), 1);
  });
}
