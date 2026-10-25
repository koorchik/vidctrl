import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'windows_power.dart';

/// Keeps the computer from going to sleep while conversions run. The screen
/// may still turn off.
///
/// Each implementation holds something the operating system ends together
/// with this app: a helper process, or on Windows a power request of the
/// app's own. So a crash can never leave the computer unable to sleep.
abstract interface class SleepInhibitor {
  factory SleepInhibitor.forPlatform() {
    if (Platform.isLinux) return _HelperInhibitor.linux();
    if (Platform.isMacOS) return _HelperInhibitor.macOS();
    if (Platform.isWindows) return _WindowsInhibitor();
    return const _NoInhibitor();
  }

  /// Whether sleep is being prevented now: true only once the operating
  /// system has agreed to it.
  bool get isActive;

  /// [isActive] each time it changes, also when the operating system ends
  /// it unasked.
  Stream<bool> get changes;

  Future<void> acquire();
  Future<void> release();
}

/// Tells [SleepInhibitor.changes] listeners.
mixin _Changes {
  final _changes = StreamController<bool>.broadcast(sync: true);
  bool _active = false;

  bool get isActive => _active;
  Stream<bool> get changes => _changes.stream;

  void _set(bool active) {
    if (active == _active) return;
    _active = active;
    _changes.add(active);
  }
}

class _HelperInhibitor with _Changes implements SleepInhibitor {
  _HelperInhibitor(this._executable, this._arguments, {this.saysHeld = false});

  /// `systemd-inhibit` holds the lock for as long as its child command runs,
  /// and starts it only once it has the lock: the child says so, then `cat`
  /// runs until its stdin closes, which that pipe does when this app exits
  /// for any reason.
  factory _HelperInhibitor.linux() => _HelperInhibitor('systemd-inhibit', [
    '--what=sleep:idle',
    '--mode=block',
    '--who=VidCtrl',
    '--why=Converting videos',
    'sh',
    '-c',
    'echo held; exec cat',
  ], saysHeld: true);

  /// `-w <pid>` makes caffeinate exit together with this app.
  factory _HelperInhibitor.macOS() =>
      _HelperInhibitor('caffeinate', ['-i', '-s', '-w', '$pid']);

  final String _executable;
  final List<String> _arguments;

  /// Whether the helper prints a line once sleep is prevented; otherwise
  /// that is so as soon as it runs.
  final bool saysHeld;
  Process? _helper;

  @override
  Future<void> acquire() async {
    if (_helper != null) return;
    final Process helper;
    try {
      helper = await Process.start(_executable, _arguments);
    } on ProcessException {
      // The helper is missing on this system. Converting still works; the
      // computer just follows its normal sleep settings.
      return;
    }
    _helper = helper;
    final held = Completer<bool>();
    unawaited(
      helper.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach((line) {
            if (line == 'held' && !held.isCompleted) held.complete(true);
          }),
    );
    // Nothing reads the helper's errors, so they must be drained.
    unawaited(helper.stderr.drain<void>());
    unawaited(
      helper.exitCode.then((_) {
        if (!held.isCompleted) held.complete(false);
        if (identical(_helper, helper)) {
          _helper = null;
          _set(false);
        }
      }),
    );
    if (!saysHeld || await held.future) {
      if (identical(_helper, helper)) _set(true);
    }
  }

  @override
  Future<void> release() async {
    final helper = _helper;
    _helper = null;
    helper?.kill();
    _set(false);
  }
}

class _WindowsInhibitor with _Changes implements SleepInhibitor {
  PowerRequest? _request;

  @override
  Future<void> acquire() async {
    if (_request != null) return;
    _request = PowerRequest.systemRequired('Converting videos');
    _set(_request != null);
  }

  @override
  Future<void> release() async {
    _request?.clear();
    _request = null;
    _set(false);
  }
}

class _NoInhibitor implements SleepInhibitor {
  const _NoInhibitor();

  @override
  bool get isActive => false;

  @override
  Stream<bool> get changes => const Stream.empty();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}
