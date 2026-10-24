import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quality/quality_meter.dart';
import '../providers.dart';
import '../queue/queue_state.dart';

/// What comparing one finished job with its original has shown so far.
sealed class QualityCheck {
  const QualityCheck();
}

class QualityComparing extends QualityCheck {
  const QualityComparing(this.fraction);

  /// The part compared so far, from 0 to 1.
  final double fraction;
}

class QualityMeasured extends QualityCheck {
  const QualityMeasured(this.lumaDb, {this.vmaf});

  final double lumaDb;

  /// Null where this FFmpeg cannot measure VMAF.
  final double? vmaf;

  Closeness get closeness => closenessOf(xpsnr: lumaDb, vmaf: vmaf);
}

class QualityFailed extends QualityCheck {
  const QualityFailed(this.errorLines);

  final List<String> errorLines;
}

final qualityProvider =
    NotifierProvider<QualityController, Map<int, QualityCheck>>(
      QualityController.new,
    );

/// Compares finished conversions with their originals when asked, one at a
/// time, and keeps what each comparison showed by job id while the app runs.
class QualityController extends Notifier<Map<int, QualityCheck>> {
  late AppEnvironment _env;
  ComparisonHandle? _active;

  /// The comparison under way, from the request until FFmpeg has exited.
  Future<void>? _comparing;

  /// Set when the comparison under way is to stop, even before FFmpeg has
  /// started.
  bool _cancelling = false;

  /// Set when the app is leaving: nothing new starts.
  bool _stopped = false;

  @override
  Map<int, QualityCheck> build() {
    _env = ref.watch(environmentProvider).requireValue;
    ref.onDispose(() => _active?.cancel());
    return const {};
  }

  bool get busy => _comparing != null;

  /// Whether [job]'s result can be compared with its original: it is
  /// finished, its frames pair with the original's, and this FFmpeg has the
  /// filter that compares them.
  bool canCompare(QueueJob job) =>
      job.status == JobStatus.done &&
      job.result?.outputPath != null &&
      comparableHere(job.plan, _env.capabilities);

  /// Compares [job]'s result with its original, unless another comparison is
  /// under way.
  Future<void> compare(QueueJob job) async {
    if (busy || _stopped || !canCompare(job)) return;
    _cancelling = false;
    final comparing = _compare(job);
    _comparing = comparing;
    try {
      await comparing;
    } finally {
      _comparing = null;
    }
  }

  Future<void> _compare(QueueJob job) async {
    _set(job.id, const QualityComparing(0));
    final ComparisonHandle handle;
    try {
      handle = await _env.qualityMeter.start(
        original: job.info,
        result: job.result!.outputPath!,
        range: job.sample,
        vmaf: _env.capabilities.hasFilter('libvmaf'),
      );
    } on Exception catch (e) {
      _set(job.id, QualityFailed(['$e']));
      return;
    }
    _active = handle;
    // Stopped while FFmpeg was starting.
    if (_cancelling) unawaited(handle.cancel());
    final progress = handle.progress.listen(
      (fraction) => _set(job.id, QualityComparing(fraction)),
    );
    final result = await handle.result;
    // Not awaited: in widget tests that would escape the fake clock.
    unawaited(progress.cancel());
    _active = null;
    if (!ref.mounted) return;
    switch (result.status) {
      case ComparisonStatus.done:
        _set(job.id, QualityMeasured(result.lumaDb!, vmaf: result.vmaf));
      case ComparisonStatus.failed:
        _set(job.id, QualityFailed(result.errorLines));
      case ComparisonStatus.cancelled:
        state = {...state}..remove(job.id);
    }
  }

  /// Stops the comparison under way. Completes once FFmpeg has exited.
  Future<void> cancel() async {
    final comparing = _comparing;
    if (comparing == null) return;
    _cancelling = true;
    await _active?.cancel();
    await comparing;
  }

  /// Stops comparing for good, as the app leaves. Completes once FFmpeg has
  /// exited.
  Future<void> stop() {
    _stopped = true;
    return cancel();
  }

  void _set(int jobId, QualityCheck check) {
    if (ref.mounted) state = {...state, jobId: check};
  }
}
