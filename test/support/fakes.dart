import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/core/estimate/progress_estimator.dart';
import 'package:vidctrl/core/estimate/size_estimator.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/command_builder.dart';
import 'package:vidctrl/core/ffmpeg/locator.dart';
import 'package:vidctrl/core/media/ffprobe.dart';

import 'dart:typed_data';

import 'package:vidctrl/core/media/media_info.dart';
import 'package:vidctrl/core/media/thumbnail.dart';
import 'package:vidctrl/core/platform/sleep_inhibitor.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';
import 'package:vidctrl/core/updates/releases.dart';

import 'fake_media.dart';

/// Answers probes from a table instead of running ffprobe. Paths not in the
/// table are reported as unreadable, like a file that is not a video.
class FakeFfprobe implements Ffprobe {
  final files = <String, MediaInfo>{};

  /// Registers a file. [like] supplies everything but the path.
  void add(String path, {MediaInfo? like}) {
    final info = like ?? clip();
    files[path] = MediaInfo(
      path: path,
      formatName: info.formatName,
      duration: info.duration,
      sizeBytes: info.sizeBytes,
      bitRate: info.bitRate,
      tags: info.tags,
      video: info.video,
      audio: info.audio,
      raw: info.raw,
    );
  }

  @override
  String get executable => 'ffprobe';

  @override
  Future<MediaInfo> probe(String path) async {
    final info = files[path];
    if (info == null) throw FfprobeException('not a video');
    return info;
  }
}

/// A conversion that finishes only when the test says so.
class FakeHandle implements ConversionHandle {
  FakeHandle(this.job);

  final ConversionJob job;
  final _progress = StreamController<JobProgress>.broadcast();
  final _result = Completer<ConversionResult>();
  bool paused = false;

  /// When set, cancelling only asks: the conversion stops when the test calls
  /// [stop], as FFmpeg takes a moment to finish its file.
  bool stopsLate = false;
  bool cancelRequested = false;

  @override
  Stream<JobProgress> get progress => _progress.stream;

  @override
  Future<ConversionResult> get result => _result.future;

  void report(double fraction) => _progress.add(
    JobProgress(
      fraction: fraction,
      outTime: job.durationToConvert * fraction,
      speed: 2,
      remaining: job.durationToConvert * ((1 - fraction) / 2),
      currentBytes: 1000,
    ),
  );

  void finish({int bytes = 1000000, Duration elapsed = Duration.zero}) {
    _complete(
      ConversionResult(
        status: ConversionStatus.done,
        elapsed: elapsed,
        outputPath: job.outputPath,
        outputBytes: bytes,
      ),
    );
  }

  void fail() => _complete(
    const ConversionResult(
      status: ConversionStatus.failed,
      elapsed: Duration.zero,
      errorLines: ['Invalid data found when processing input'],
    ),
  );

  @override
  Future<void> cancel() async {
    cancelRequested = true;
    if (!stopsLate) stop();
  }

  /// The cancelled conversion has ended.
  void stop() => _complete(
    const ConversionResult(
      status: ConversionStatus.cancelled,
      elapsed: Duration.zero,
    ),
  );

  void _complete(ConversionResult result) {
    if (_result.isCompleted) return;
    _progress.close();
    _result.complete(result);
  }

  @override
  bool pause() => paused = true;

  @override
  bool resume() {
    paused = false;
    return true;
  }
}

/// Records the conversions that were started and hands out [FakeHandle]s.
class FakeExecutor implements JobExecutor {
  final started = <FakeHandle>[];

  FakeHandle get last => started.last;

  /// Names of the source files converted so far, in order.
  List<String> get startedNames => [
    for (final handle in started) handle.job.input.path.split('/').last,
  ];

  @override
  Future<ConversionHandle> start(ConversionJob job) async {
    final handle = FakeHandle(job);
    started.add(handle);
    return handle;
  }
}

class FakeSleepInhibitor implements SleepInhibitor {
  @override
  bool isActive = false;

  @override
  Future<void> acquire() async => isActive = true;

  @override
  Future<void> release() async => isActive = false;
}

/// Pretends to measure: every re-encode comes out at [ratio] of the source
/// size and takes as long as the video lasts.
class FakeEstimator implements OutputEstimator {
  double ratio = 0.2;

  /// When set, measuring fails.
  bool fail = false;

  /// When set, measurements wait until [release] or [cancelAll].
  bool hold = false;

  /// Files actually measured (not calculated), in order.
  final measured = <String>[];
  var cancels = 0;
  var _generation = 0;
  final _held = <Completer<void>>[];

  void release() {
    for (final waiting in _held) {
      waiting.complete();
    }
    _held.clear();
  }

  @override
  Future<OutputEstimate?> estimate(MediaInfo info, ConversionPlan plan) async {
    final calculated = estimateWithoutEncoding(info, plan);
    if (calculated != null) return calculated;
    measured.add(info.path);
    final generation = _generation;
    if (hold) {
      final waiting = Completer<void>();
      _held.add(waiting);
      await waiting.future;
    }
    if (fail || generation != _generation) return null;
    return OutputEstimate(
      bytes: (info.sizeBytes * ratio).round(),
      time: info.duration,
      measured: true,
    );
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    _generation++;
    release();
  }
}

/// A comparison that finishes only when the test says so.
class FakeComparison implements ComparisonHandle {
  FakeComparison(this.original, this.resultPath, this.range, this.vmaf);

  final MediaInfo original;
  final String resultPath;
  final SampleRange? range;

  /// Whether VMAF was asked for.
  final bool vmaf;
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<ComparisonResult>();
  bool cancelRequested = false;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<ComparisonResult> get result => _result.future;

  void report(double fraction) => _progress.add(fraction);

  void finish(double lumaDb, {double? vmaf}) => _complete(
    ComparisonResult(status: ComparisonStatus.done, lumaDb: lumaDb, vmaf: vmaf),
  );

  void fail() => _complete(
    const ComparisonResult(
      status: ComparisonStatus.failed,
      errorLines: ['Invalid data found when processing input'],
    ),
  );

  @override
  Future<void> cancel() async {
    cancelRequested = true;
    _complete(const ComparisonResult(status: ComparisonStatus.cancelled));
  }

  void _complete(ComparisonResult result) {
    if (_result.isCompleted) return;
    _progress.close();
    _result.complete(result);
  }
}

/// Records the comparisons that were started and hands out
/// [FakeComparison]s.
class FakeQualityMeter implements QualityMeter {
  final started = <FakeComparison>[];

  FakeComparison get last => started.last;

  @override
  Future<ComparisonHandle> start({
    required MediaInfo original,
    required String result,
    SampleRange? range,
    bool vmaf = false,
  }) async {
    final comparison = FakeComparison(original, result, range, vmaf);
    started.add(comparison);
    return comparison;
  }
}

/// Hands out the same picture for every video.
class FakeThumbnailer implements Thumbnailer {
  FakeThumbnailer(this.bytes);

  final Uint8List? bytes;

  @override
  String get ffmpeg => 'ffmpeg';

  @override
  Duration get timeout => Duration.zero;

  @override
  Future<Uint8List?> frame(
    String path, {
    Duration at = Duration.zero,
    int width = 480,
  }) async => bytes;
}

/// A complete stand-in for the machine: no FFmpeg, no real files.
class FakeEnvironment {
  FakeEnvironment({
    this.capabilities = softwareOnly,
    this.ffmpegPaths = const FfmpegPaths(
      ffmpeg: '/opt/vidctrl/lib/ffmpeg/ffmpeg',
      ffprobe: '/opt/vidctrl/lib/ffmpeg/ffprobe',
      source: FfmpegSource.bundled,
    ),
    this.thumbnail,
    this.build = const BuildInfo(),
    this.releases,
  });

  final Capabilities capabilities;

  /// What the app was built as; a development build by default.
  final BuildInfo build;

  /// Where newer versions are looked for; nowhere by default, so no test
  /// goes on the internet.
  final ReleaseSource? releases;

  /// Where the FFmpeg in use was found; the copy inside the app by default.
  final FfmpegPaths ffmpegPaths;

  /// The picture shown for every video; none by default.
  final Uint8List? thumbnail;
  final ffprobe = FakeFfprobe();
  final executor = FakeExecutor();
  final inhibitor = FakeSleepInhibitor();
  final estimator = FakeEstimator();
  final qualityMeter = FakeQualityMeter();

  late final environment = AppEnvironment(
    ffmpeg: ffmpegPaths,
    ffprobe: ffprobe,
    executor: executor,
    capabilities: capabilities,
    sleepInhibitor: inhibitor,
    estimator: estimator,
    qualityMeter: qualityMeter,
    thumbnailer: FakeThumbnailer(thumbnail),
  );

  /// Overrides that make the app use this environment.
  List<Override> get overrides => [
    environmentProvider.overrideWith((ref) async => environment),
    buildInfoProvider.overrideWithValue(build),
    releaseSourceProvider.overrideWithValue(releases),
  ];
}

/// Answers the check for a newer version when the test says, with a release
/// or by failing.
class FakeReleaseSource implements ReleaseSource {
  final _answer = Completer<Release>();

  void answer(String version) => _answer.complete(
    Release(
      version: Version.tryParse(version)!,
      page: Uri.parse('https://example.com/releases/v$version'),
    ),
  );

  void fail() => _answer.completeError(const ReleaseCheckFailed('offline'));

  @override
  Future<Release> latest() => _answer.future;
}
