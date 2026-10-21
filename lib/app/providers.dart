import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/estimate/size_estimator.dart';
import '../core/ffmpeg/capabilities.dart';
import '../core/ffmpeg/locator.dart';
import '../core/ffmpeg/runner.dart';
import '../core/media/ffprobe.dart';
import '../core/media/thumbnail.dart';
import '../core/platform/sleep_inhibitor.dart';
import '../core/quality/quality_meter.dart';
import '../core/queue/job_executor.dart';
import 'settings.dart';

/// Everything the app needs from the machine it runs on, found once at
/// startup. Tests replace this with fakes.
class AppEnvironment {
  const AppEnvironment({
    required this.ffmpeg,
    required this.ffprobe,
    required this.executor,
    required this.capabilities,
    required this.sleepInhibitor,
    required this.estimator,
    required this.qualityMeter,
    this.thumbnailer,
  });

  /// The FFmpeg in use and where it was found.
  final FfmpegPaths ffmpeg;
  final Ffprobe ffprobe;
  final JobExecutor executor;
  final Capabilities capabilities;
  final SleepInhibitor sleepInhibitor;

  /// Predicts output sizes before anything is converted.
  final OutputEstimator estimator;

  /// Compares converted files with their originals, when asked.
  final QualityMeter qualityMeter;

  /// Grabs preview frames of videos. Null where there is no FFmpeg to ask.
  final Thumbnailer? thumbnailer;
}

/// Thrown at startup when no usable FFmpeg can be found.
class FfmpegMissing implements Exception {
  const FfmpegMissing();
}

final environmentProvider = FutureProvider<AppEnvironment>(
  (ref) async {
    // Read, not watched: everything the app holds is built on this, so a
    // newly chosen folder is used from the next start.
    final paths = FfmpegLocator().locate(
      overrideDir: ref.read(ffmpegFolderProvider),
    );
    if (paths == null) throw const FfmpegMissing();
    return AppEnvironment(
      ffmpeg: paths,
      ffprobe: Ffprobe(paths.ffprobe),
      executor: JobExecutor(FfmpegRunner(paths.ffmpeg)),
      capabilities: await CapabilityProbe(paths.ffmpeg).detect(),
      sleepInhibitor: SleepInhibitor.forPlatform(),
      estimator: SampleEstimator(FfmpegRunner(paths.ffmpeg)),
      qualityMeter: QualityMeter(FfmpegRunner(paths.ffmpeg)),
      thumbnailer: Thumbnailer(paths.ffmpeg),
    );
  },
  // A missing FFmpeg does not appear by waiting; show the message at once.
  retry: (_, _) => null,
);
