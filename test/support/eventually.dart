import 'package:flutter_test/flutter_test.dart';

/// Waits until [condition] holds, giving the window's asynchronous work, and
/// a client's, time to run. Fails the test when it still does not hold after
/// [within]. For tests on the real clock; widget tests pump instead.
Future<void> eventually(
  bool Function() condition, {
  Duration within = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(within);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'still not so after $within');
}
