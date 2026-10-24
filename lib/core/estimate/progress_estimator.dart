import '../ffmpeg/progress_parser.dart';

/// Where one conversion stands, in terms a person cares about.
class JobProgress {
  const JobProgress({
    required this.fraction,
    required this.outTime,
    this.speed,
    this.remaining,
    this.currentBytes,
    this.predictedBytes,
  });

  /// 0.0 to 1.0.
  final double fraction;
  final Duration outTime;

  /// Seconds of video converted per second of waiting: 2.0 is twice realtime.
  final double? speed;
  final Duration? remaining;
  final int? currentBytes;

  /// Expected size of the finished file. Null until enough has been written
  /// for the extrapolation to mean something.
  final int? predictedBytes;
}

/// Turns raw FFmpeg progress reports into speed, time remaining and a size
/// prediction.
///
/// Speed is measured over a recent window rather than the whole run, so the
/// estimate follows the footage: a busy scene encodes slower than a static
/// one, and the estimate should say so.
class ProgressEstimator {
  ProgressEstimator(
    this.total, {
    this.window = const Duration(seconds: 10),
    this.minWindow = const Duration(seconds: 1),
  });

  final Duration total;
  final Duration window;
  final Duration minWindow;

  final List<({Duration elapsed, Duration outTime})> _samples = [];
  Duration _outTime = Duration.zero;
  int? _bytes;

  /// [elapsed] is time spent converting so far, not counting pauses.
  JobProgress update(ProgressSnapshot snapshot, Duration elapsed) {
    final reported = snapshot.outTime;
    if (reported != null && reported > _outTime) _outTime = reported;
    if (snapshot.isEnd && total > Duration.zero) _outTime = total;
    _bytes = snapshot.totalSize ?? _bytes;

    _samples.add((elapsed: elapsed, outTime: _outTime));
    while (_samples.length > 2 && elapsed - _samples[1].elapsed >= window) {
      _samples.removeAt(0);
    }

    final speed = _speed(elapsed);
    return JobProgress(
      fraction: total > Duration.zero
          ? (_outTime.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0)
          : 0,
      outTime: _outTime,
      speed: speed,
      remaining: _remaining(speed),
      currentBytes: _bytes,
      predictedBytes: _predictedBytes(),
    );
  }

  Duration? _remaining(double? speed) {
    final left = total - _outTime;
    if (left <= Duration.zero) return Duration.zero;
    if (speed == null || speed <= 0) return null;
    return Duration(microseconds: (left.inMicroseconds / speed).round());
  }

  double? _speed(Duration elapsed) {
    final first = _samples.first;
    final span = elapsed - first.elapsed;
    if (span >= minWindow) {
      return (_outTime - first.outTime).inMicroseconds / span.inMicroseconds;
    }
    // Too little recent history: fall back to the average since the start.
    if (elapsed >= minWindow) {
      return _outTime.inMicroseconds / elapsed.inMicroseconds;
    }
    return null;
  }

  /// Extrapolates the final size once 5% of the file, or 20 seconds of it,
  /// has been written. Earlier than that the opening seconds dominate and
  /// the number jumps around.
  int? _predictedBytes() {
    final bytes = _bytes;
    if (bytes == null || total <= Duration.zero) return null;
    if (_outTime <= Duration.zero) return null;
    final enough =
        _outTime.inMicroseconds >= total.inMicroseconds * 0.05 ||
        _outTime >= const Duration(seconds: 20);
    if (!enough) return null;
    // The ratio first: bytes times microseconds overflows on a long film.
    return (bytes * (total.inMicroseconds / _outTime.inMicroseconds)).round();
  }
}
