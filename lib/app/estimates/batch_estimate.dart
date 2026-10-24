import '../../core/scenarios/scenario.dart';
import '../sources/preview_controller.dart';
import '../sources/sources_controller.dart';

/// Expected total size and time for [videos], or null while nothing has been
/// worked out yet.
///
/// Videos not measured yet are assumed to shrink like the measured ones, in
/// proportion to their size, and to take time in proportion to their length.
/// One left as it is keeps its size and takes no time.
({int before, int after, Duration? time})? batchEstimate(
  List<SourceVideo> videos,
  Map<int, Preview> previews,
) {
  final known = [
    for (final video in videos)
      if (previews[video.id]?.estimate case final estimate?) (video, estimate),
  ];
  if (known.isEmpty) return null;
  int size(SourceVideo v) => v.info?.sizeBytes ?? 0;
  int length(SourceVideo v) => v.info?.duration.inMilliseconds ?? 0;

  final before = videos.fold(0, (sum, v) => sum + size(v));
  final knownBefore = known.fold(0, (sum, k) => sum + size(k.$1));
  bool kept(SourceVideo v) => previews[v.id]?.keptAsIs ?? false;
  final knownAfter = known.fold(
    0,
    (sum, k) => sum + (kept(k.$1) ? size(k.$1) : k.$2.bytes),
  );
  // The ratio is taken first: byte counts multiplied together overflow.
  final after = knownBefore > 0
      ? (knownAfter * (before / knownBefore)).round()
      : knownAfter;

  // Only re-encodes take noticeable time; quick fixes take seconds.
  final timed = known.where((k) => k.$2.time != null && !kept(k.$1)).toList();
  final encodes = videos.where(
    (v) => previews[v.id]?.plan.kind == PlanKind.encode && !kept(v),
  );
  final timedLength = timed.fold(0, (sum, k) => sum + length(k.$1));
  final encodeLength = encodes.fold(0, (sum, v) => sum + length(v));
  final timedSpent = timed.fold(Duration.zero, (sum, k) => sum + k.$2.time!);
  final time = timedLength > 0
      ? timedSpent * (encodeLength / timedLength)
      : null;
  return (before: before, after: after, time: time);
}
