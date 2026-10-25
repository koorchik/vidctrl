import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/control/agent_prompt.dart';
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
import 'package:vidctrl/core/quality/frame_grabber.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/quality/quality_search.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';
import 'package:vidctrl/core/updates/releases.dart';

import 'fake_media.dart';

/// Answers probes from a table instead of running ffprobe. Paths not in the
/// table are reported as unreadable, like a file that is not a video.
class FakeFfprobe implements Ffprobe {
  final files = <String, MediaInfo>{};

  /// What probing a path throws instead of answering, as when ffprobe
  /// cannot be started.
  final errors = <String, Object>{};

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
    if (errors[path] case final error?) throw error;
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
    unawaited(_progress.close());
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

  /// When set, each start waits until [releaseStarts], as a real start
  /// takes a moment: the job is under way with nothing to cancel yet.
  bool holdStarts = false;
  final _heldStarts = <Completer<void>>[];

  void releaseStarts() {
    for (final waiting in _heldStarts) {
      waiting.complete();
    }
    _heldStarts.clear();
  }

  @override
  Future<ConversionHandle> start(ConversionJob job) async {
    if (holdStarts) {
      final waiting = Completer<void>();
      _heldStarts.add(waiting);
      await waiting.future;
    }
    final handle = FakeHandle(job);
    started.add(handle);
    return handle;
  }
}

class FakeSleepInhibitor implements SleepInhibitor {
  final _changes = StreamController<bool>.broadcast(sync: true);

  @override
  bool isActive = false;

  @override
  Stream<bool> get changes => _changes.stream;

  /// When set, keeping the computer awake fails.
  bool fails = false;

  /// When set, the operating system says no, as a real one may.
  bool refuses = false;

  @override
  Future<void> acquire() async {
    if (fails) throw StateError('No helper to keep the computer awake');
    if (!refuses) _set(true);
  }

  @override
  Future<void> release() async => _set(false);

  /// As when the operating system ends it unasked.
  void end() => _set(false);

  void _set(bool active) {
    if (active == isActive) return;
    isActive = active;
    _changes.add(active);
  }
}

/// Pretends to measure: every re-encode comes out at [ratio] of the source
/// size, [quality] close to it, and takes as long as the video lasts.
class FakeEstimator implements OutputEstimator {
  double ratio = 0.2;

  /// How close the samples came to the original; null for not compared.
  QualityScore? quality;

  /// The quality chosen for a file, when the goal raises it. Each of its
  /// tries is announced before the estimate ends.
  final choices = <String, QualityChoice>{};

  /// Files measured with the quality raised where needed, in order.
  final raised = <String>[];
  var discards = 0;

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
  Future<OutputEstimate?> estimate(
    MediaInfo info,
    ConversionPlan plan, {
    RaisesQuality? raise,
    void Function(int attempt)? onAttempt,
  }) async {
    final calculated = estimateWithoutEncoding(info, plan);
    if (calculated != null) return calculated;
    measured.add(info.path);
    final choice = raise == null ? null : choices[info.path];
    if (raise != null) raised.add(info.path);
    for (var attempt = 1; attempt <= (choice?.trials.length ?? 1); attempt++) {
      onAttempt?.call(attempt);
    }
    final generation = _generation;
    if (hold) {
      final waiting = Completer<void>();
      _held.add(waiting);
      await waiting.future;
    }
    if (fail || generation != _generation) return null;
    if (choice != null) {
      return OutputEstimate(
        bytes: choice.chosen.bytes,
        time: info.duration,
        measured: true,
        quality: choice.chosen.score,
        choice: choice,
      );
    }
    return OutputEstimate(
      bytes: (info.sizeBytes * ratio).round(),
      time: info.duration,
      measured: true,
      quality: quality,
    );
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    _generation++;
    release();
  }

  @override
  Future<void> discardKept() async => discards++;
}

/// A choice as the archive's search makes it, for a video of [sourceBytes]
/// (the size `clip()` gives). A video that falls short tried crf 35 first.
QualityChoice fakeChoice(
  QualityOutcome outcome, {
  int sourceBytes = 750000000,
}) {
  QualityTrial trial(int crf, double vmaf, double share) => QualityTrial(
    value: crf,
    score: QualityScore(vmaf - 55, vmaf: vmaf),
    bytes: (sourceBytes * share).round(),
    pieces: 6,
    hardest: HardestFrame(
      pieceStart: const Duration(minutes: 2, seconds: 23),
      pieceLength: const Duration(seconds: 3),
      frame: 40,
      encodedPiece: '/tmp/vidctrl_estimates/sample_$crf.mp4',
    ),
  );
  final trials = switch (outcome) {
    QualityOutcome.standard => [trial(35, 96.0, 0.2)],
    QualityOutcome.raised => [
      trial(35, 92.6, 0.2),
      trial(20, 99.0, 0.6),
      trial(26, 95.3, 0.35),
    ],
    QualityOutcome.belowTarget => [trial(35, 90.9, 0.2), trial(20, 92.8, 0.6)],
    QualityOutcome.notWorthIt => [trial(35, 99.0, 0.9)],
  };
  return QualityChoice(
    outcome: outcome,
    trials: trials,
    chosen: trials.last,
    sourceBytes: sourceBytes,
  );
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
    unawaited(_progress.close());
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

/// Hands out a small picture for every frame asked for, and records what
/// was asked. With [fail] set, no frame can be read.
class FakeFrameGrabber implements FrameGrabber {
  bool fail = false;

  /// What every frame looks like; a tiny grey square unless set.
  Uint8List? picture;

  /// What was grabbed: path, seek and frame.
  final grabbed = <(String, Duration, int)>[];

  @override
  String get ffmpeg => 'ffmpeg';

  @override
  Duration get timeout => Duration.zero;

  @override
  Future<Uint8List?> grab(
    String path, {
    Duration seek = Duration.zero,
    required int frame,
  }) async {
    grabbed.add((path, seek, frame));
    return fail ? null : picture ?? tinyPng;
  }

  @override
  Future<FramePair?> pair({
    required String original,
    required Duration originalSeek,
    required String result,
    required Duration resultSeek,
    required int frame,
  }) async {
    final first = await grab(original, seek: originalSeek, frame: frame);
    final second = await grab(result, seek: resultSeek, frame: frame);
    if (first == null || second == null) return null;
    return FramePair(original: first, result: second);
  }
}

/// A 2 by 2 grey PNG.
final tinyPng = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, //
  0, 0, 0, 2, 8, 0, 0, 0, 0, 87, 221, 82, 248, 0, 0, 0, 14, 73, 68, 65, 84, //
  120, 156, 99, 104, 104, 96, 104, 104, 0, 0, 6, 6, 2, 1, 44, 193, 80, 215, //
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

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
    this.clientPath = '/opt/vidctrl/vidctrl-client',
    this.appFolder = '/home/alice/work/vidctrl/build/linux/x64/debug/bundle',
    this.os = 'linux',
  });

  final Capabilities capabilities;

  /// What the app was built as; a development build by default.
  final BuildInfo build;

  /// Where newer versions are looked for; nowhere by default, so no test
  /// goes on the internet.
  final ReleaseSource? releases;

  /// Where vidctrl-client is beside the app; null for a build without it.
  /// A test may set it while the app runs, as when the client is built then.
  String? clientPath;

  /// The folder of the app's own program, where a missing client is built.
  final String appFolder;

  /// The system the app takes itself to run on (`Platform.operatingSystem`),
  /// whatever the tests run on; Linux by default.
  final String os;

  /// Where the FFmpeg in use was found; the copy inside the app by default.
  final FfmpegPaths ffmpegPaths;

  /// The picture shown for every video; none by default.
  final Uint8List? thumbnail;
  final ffprobe = FakeFfprobe();
  final executor = FakeExecutor();
  final inhibitor = FakeSleepInhibitor();
  final estimator = FakeEstimator();
  final qualityMeter = FakeQualityMeter();
  final frames = FakeFrameGrabber();

  late final environment = AppEnvironment(
    ffmpeg: ffmpegPaths,
    ffprobe: ffprobe,
    executor: executor,
    capabilities: capabilities,
    sleepInhibitor: inhibitor,
    estimator: estimator,
    qualityMeter: qualityMeter,
    thumbnailer: FakeThumbnailer(thumbnail),
    frameGrabber: frames,
  );

  /// Overrides that make the app use this environment.
  List<Override> get overrides => [
    environmentProvider.overrideWith((ref) async => environment),
    buildInfoProvider.overrideWithValue(build),
    releaseSourceProvider.overrideWithValue(releases),
    clientExecutableProvider.overrideWith((ref) => clientPath),
    appFolderProvider.overrideWithValue(appFolder),
    operatingSystemProvider.overrideWithValue(os),
  ];
}

/// Answers the check for a newer version when the test says, with a release
/// or by failing.
class FakeReleaseSource implements ReleaseSource {
  final _answer = Completer<Release>();

  /// How many times the app has looked.
  int asked = 0;

  void answer(String version) =>
      _answer.complete(Release(version: Version.tryParse(version)!));

  void fail() => _answer.completeError(const ReleaseCheckFailed('offline'));

  @override
  Future<Release> latest() {
    asked++;
    return _answer.future;
  }
}
