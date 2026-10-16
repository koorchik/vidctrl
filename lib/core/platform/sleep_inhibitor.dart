import 'dart:io';

/// Keeps the computer from going to sleep while conversions run.
///
/// Each implementation holds a helper process that the operating system
/// treats as "something important is running". The helper ends by itself when
/// this app ends, so a crash can never leave the computer unable to sleep.
abstract interface class SleepInhibitor {
  factory SleepInhibitor.forPlatform() {
    if (Platform.isLinux) return _HelperInhibitor.linux();
    if (Platform.isMacOS) return _HelperInhibitor.macOS();
    // Windows needs a power request through the Win32 API; not built yet.
    return const _NoInhibitor();
  }

  /// Whether sleep is currently being prevented.
  bool get isActive;

  Future<void> acquire();
  Future<void> release();
}

class _HelperInhibitor implements SleepInhibitor {
  _HelperInhibitor(this._executable, this._arguments);

  /// `systemd-inhibit` holds the lock for as long as its child command runs.
  /// `cat` runs until its stdin closes, and that pipe closes when this app
  /// exits for any reason.
  factory _HelperInhibitor.linux() => _HelperInhibitor('systemd-inhibit', [
    '--what=sleep:idle',
    '--mode=block',
    '--who=VidCtrl',
    '--why=Converting videos',
    'cat',
  ]);

  /// `-w <pid>` makes caffeinate exit together with this app.
  factory _HelperInhibitor.macOS() =>
      _HelperInhibitor('caffeinate', ['-i', '-s', '-w', '$pid']);

  final String _executable;
  final List<String> _arguments;
  Process? _helper;

  @override
  bool get isActive => _helper != null;

  @override
  Future<void> acquire() async {
    if (_helper != null) return;
    try {
      final helper = await Process.start(_executable, _arguments);
      _helper = helper;
      // Nothing reads the helper's output, so it must be drained.
      helper.stdout.drain<void>();
      helper.stderr.drain<void>();
      helper.exitCode.then((_) {
        if (identical(_helper, helper)) _helper = null;
      });
    } on ProcessException {
      // The helper is missing on this system. Converting still works; the
      // computer just follows its normal sleep settings.
    }
  }

  @override
  Future<void> release() async {
    final helper = _helper;
    _helper = null;
    helper?.kill();
  }
}

class _NoInhibitor implements SleepInhibitor {
  const _NoInhibitor();

  @override
  bool get isActive => false;

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}
