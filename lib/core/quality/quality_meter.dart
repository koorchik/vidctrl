/// Measures how close a converted picture comes to its original: a separate
/// pass that decodes both files and compares them frame by frame.
///
/// Two measures, where the FFmpeg has both. XPSNR (FFmpeg's `xpsnr` filter,
/// brightness only, as when the archive goal's quality numbers were set)
/// weighs differences by how visible they are. VMAF (the `libvmaf` filter,
/// from Netflix) is trained on what people saw in viewing tests, so it gives
/// the verdict when it is there.
library;

import 'dart:async';
import 'dart:io';

import '../ffmpeg/command_builder.dart';
import '../ffmpeg/runner.dart';
import '../media/ffprobe.dart';
import '../media/media_info.dart';
import '../scenarios/scenario.dart';

// Measured in October 2026 on a 4K camera clip that was hard to compress.
// The archive goal's AV1 gave XPSNR 41.4 dB and VMAF 96.0, and no difference
// showed in watching. A faulty encoder gave 39.5 dB and VMAF 92.5 on the same
// clip, at the same size, with blocks visible on faces. Reaching 42 dB took
// 1.5 times the size, for no difference to be seen.

/// XPSNR from here up counts as looking the same as the original: the level
/// reported as visually lossless, and the archive goal's own target
/// (`archive.dart`).
const sameAsOriginalDb = 42.0;

/// XPSNR from here up is very close.
const veryCloseDb = 40.0;

/// VMAF from here up counts as looking the same: about where people stop
/// telling the two apart.
const sameAsOriginalVmaf = 95.0;

/// VMAF from here up is very close.
const veryCloseVmaf = 93.0;

enum Closeness { same, veryClose, differs }

Closeness closenessOfXpsnr(double db) => db >= sameAsOriginalDb
    ? Closeness.same
    : db >= veryCloseDb
    ? Closeness.veryClose
    : Closeness.differs;

Closeness closenessOfVmaf(double vmaf) => vmaf >= sameAsOriginalVmaf
    ? Closeness.same
    : vmaf >= veryCloseVmaf
    ? Closeness.veryClose
    : Closeness.differs;

/// The verdict: by VMAF where it was measured, by XPSNR otherwise.
Closeness closenessOf({required double xpsnr, double? vmaf}) =>
    vmaf != null ? closenessOfVmaf(vmaf) : closenessOfXpsnr(xpsnr);

/// The VMAF model for a picture of [width] by [height]: the 4K one, made for
/// a 4K screen seen from closer, for anything larger than 1080p.
String vmafModelFor(int width, int height) =>
    width * height > 1920 * 1080 ? 'vmaf_4k_v0.6.1' : 'vmaf_v0.6.1';

/// Whether the output of [plan] can be compared with its original: its
/// picture was encoded (a copy is the original), and each of its frames
/// stands for one frame of the source at the same size and in the same
/// colours. A resized, retimed or tone-mapped picture would be compared with
/// the wrong frames, or would differ by design.
bool canComparePlan(ConversionPlan plan) {
  final video = plan.video;
  if (video is! VideoEncode) return false;
  final resized = video.filters.any(RegExp(r'^scale=\d+:').hasMatch);
  final toneMapped = video.filters.any((f) => f.startsWith('tonemap'));
  final retimed =
      plan.outputArgs.contains('-r') ||
      plan.outputArgs.contains('-fps_mode') ||
      video.filters.any((f) => f.startsWith('fps='));
  return !resized && !toneMapped && !retimed;
}

/// FFmpeg arguments comparing [result] with [original]. For a sample,
/// [range] picks the same piece of the original: the seek is made before the
/// input, as the conversion made it, so both start at the same frame. With a
/// [vmafModel], VMAF is measured in the same pass, on [threads] threads.
///
/// `xpsnr` takes the original first: it weighs each difference by how busy
/// the first picture is there, and the original is what a person compares
/// against. With the copy first, scores came out 0.3 to 0.8 dB low. VMAF is
/// the other way round: copy first, original second.
///
/// Frames are paired by order, not by time. Containers round times
/// differently (Matroska to milliseconds, MP4 not), and at 29.97 frames a
/// second pairing by time compared every other frame with its neighbour.
///
/// FFmpeg's `xpsnr` (8.0 and 8.1) reads a 10-bit second picture as if its
/// rows lay end to end in memory. Where they do not (a width that is not a
/// multiple of 32, such as every upright phone video, or a picture cropped
/// in place), it compares the wrong pixels: about 7 dB where 40 is right, and
/// a file against itself far from `inf`. So both pictures lose the columns
/// past the last multiple of 32 on the right (at most 31, the same in both,
/// so the scores barely move) and are copied into fresh, packed frames.
List<String> comparisonArgs({
  required String original,
  required String result,
  SampleRange? range,
  String? vmafModel,
  int threads = 1,
}) {
  const byOrder =
      'settb=1/30,setpts=N,crop=trunc(iw/32)*32:ih:0:0,format=yuv420p10le,'
      'copy';
  String seconds(Duration d) => (d.inMicroseconds / 1e6).toStringAsFixed(3);
  return [
    '-hide_banner',
    // Not `-loglevel error`: the score is printed at the normal level.
    '-nostats',
    '-progress',
    'pipe:1',
    '-i',
    inputUrl(result),
    if (range != null && range.start > Duration.zero) ...[
      '-ss',
      seconds(range.start),
    ],
    if (range != null) ...['-t', seconds(range.length)],
    '-i',
    inputUrl(original),
    '-lavfi',
    if (vmafModel == null)
      '[0:v:0]$byOrder[d];[1:v:0]$byOrder[r];[r][d]xpsnr=shortest=1'
    else ...[
      // Both measures see the same decoded frames: each file is read once.
      '[0:v:0]$byOrder,split[d][dv];[1:v:0]$byOrder,split[r][rv];'
          '[r][d]xpsnr=shortest=1[x];'
          '[dv][rv]libvmaf=model=version=$vmafModel'
          ':n_threads=$threads:shortest=1[v]',
      '-map',
      '[x]',
      '-map',
      '[v]',
    ],
    '-f',
    'null',
    '-',
  ];
}

/// The luma score from FFmpeg's output, or null when there is none.
/// Identical pictures score `inf`, read as [double.infinity].
double? parseXpsnr(Iterable<String> lines) {
  final pattern = RegExp(r'XPSNR\s+y:\s*(inf|[\d.]+)');
  double? score;
  for (final line in lines) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    final value = match.group(1)!;
    score = value == 'inf' ? double.infinity : double.parse(value);
  }
  return score;
}

/// The VMAF score from FFmpeg's output, or null when there is none.
double? parseVmaf(Iterable<String> lines) {
  final pattern = RegExp(r'VMAF score:\s*([\d.]+)');
  double? score;
  for (final line in lines) {
    if (pattern.firstMatch(line) case final match?) {
      score = double.parse(match.group(1)!);
    }
  }
  return score;
}

enum ComparisonStatus { done, failed, cancelled }

class ComparisonResult {
  const ComparisonResult({
    required this.status,
    this.lumaDb,
    this.vmaf,
    this.errorLines = const [],
  });

  final ComparisonStatus status;

  /// Set only when [status] is [ComparisonStatus.done].
  final double? lumaDb;

  /// Set when done and VMAF was measured.
  final double? vmaf;
  final List<String> errorLines;
}

/// A comparison in flight.
abstract interface class ComparisonHandle {
  /// The part compared so far, from 0 to 1.
  Stream<double> get progress;
  Future<ComparisonResult> get result;

  /// Stops FFmpeg. [result] completes once it has exited.
  Future<void> cancel();
}

class _FfmpegComparisonHandle implements ComparisonHandle {
  _FfmpegComparisonHandle(this._run, this.progress, this.result);

  final FfmpegRun _run;

  @override
  final Stream<double> progress;
  @override
  final Future<ComparisonResult> result;

  @override
  Future<void> cancel() => _run.cancel();
}

/// Compares converted files with their originals. Nothing is written.
class QualityMeter {
  QualityMeter(this._runner);

  final FfmpegRunner _runner;

  /// Compares [result] with [original]; with [vmaf], VMAF too (the FFmpeg
  /// needs the `libvmaf` filter).
  Future<ComparisonHandle> start({
    required MediaInfo original,
    required String result,
    SampleRange? range,
    bool vmaf = false,
  }) async {
    final video = original.video;
    final run = await _runner.start(
      comparisonArgs(
        original: original.path,
        result: result,
        range: range,
        vmafModel: vmaf && video != null
            ? vmafModelFor(video.width, video.height)
            : null,
        threads: Platform.numberOfProcessors,
      ),
    );
    final seconds = (range?.length ?? original.duration).inMicroseconds / 1e6;
    final frames = seconds * (video?.frameRate ?? 30);
    final progress = StreamController<double>.broadcast();
    run.progress.listen((snapshot) {
      final frame = snapshot.frame;
      if (frame != null && frames > 0) {
        progress.add((frame / frames).clamp(0.0, 1.0));
      }
    }, onDone: progress.close);
    final outcome = run.result.then((outcome) {
      final score = parseXpsnr(outcome.errorLines);
      return switch (outcome.status) {
        RunStatus.cancelled => const ComparisonResult(
          status: ComparisonStatus.cancelled,
        ),
        RunStatus.completed when score != null => ComparisonResult(
          status: ComparisonStatus.done,
          lumaDb: score,
          vmaf: parseVmaf(outcome.errorLines),
        ),
        _ => ComparisonResult(
          status: ComparisonStatus.failed,
          errorLines: outcome.errorLines,
        ),
      };
    });
    return _FfmpegComparisonHandle(run, progress.stream, outcome);
  }
}
