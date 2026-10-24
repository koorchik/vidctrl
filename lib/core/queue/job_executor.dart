import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../estimate/progress_estimator.dart';
import '../ffmpeg/command_builder.dart';
import '../ffmpeg/runner.dart';
import '../media/media_info.dart';
import '../output/output_namer.dart';
import '../scenarios/scenario.dart';

/// Everything needed to convert one file.
class ConversionJob {
  const ConversionJob({
    required this.input,
    required this.plan,
    required this.outputPath,
    this.sample,
  });

  final MediaInfo input;
  final ConversionPlan plan;
  final String outputPath;

  /// When set, only this piece of the input is converted.
  final SampleRange? sample;

  Duration get durationToConvert => sample?.length ?? input.duration;
}

enum ConversionStatus { done, failed, cancelled }

class ConversionResult {
  const ConversionResult({
    required this.status,
    required this.elapsed,
    this.outputPath,
    this.outputBytes,
    this.errorLines = const [],
  });

  final ConversionStatus status;

  /// Time spent converting, not counting pauses.
  final Duration elapsed;

  /// Set only when [status] is [ConversionStatus.done].
  final String? outputPath;
  final int? outputBytes;
  final List<String> errorLines;
}

/// A conversion in flight.
abstract interface class ConversionHandle {
  Stream<JobProgress> get progress;
  Future<ConversionResult> get result;

  Future<void> cancel();

  /// Returns false where pausing is not supported.
  bool pause();
  bool resume();
}

class _FfmpegConversionHandle implements ConversionHandle {
  _FfmpegConversionHandle(
    this._run,
    this._stopwatch,
    this.progress,
    this.result,
  );

  final FfmpegRun _run;
  final Stopwatch _stopwatch;

  @override
  final Stream<JobProgress> progress;
  @override
  final Future<ConversionResult> result;

  @override
  Future<void> cancel() => _run.cancel();

  @override
  bool pause() {
    final paused = _run.pause();
    if (paused) _stopwatch.stop();
    return paused;
  }

  @override
  bool resume() {
    final resumed = _run.resume();
    if (resumed) _stopwatch.start();
    return resumed;
  }
}

/// Runs one conversion from plan to finished file.
///
/// The output is written under a temporary name and renamed on success. On
/// failure or cancellation the partial file is deleted, so the output folder
/// only ever contains complete files.
class JobExecutor {
  JobExecutor(this._runner);

  final FfmpegRunner _runner;

  Future<ConversionHandle> start(ConversionJob job) async {
    final temporary = temporaryPathFor(job.outputPath);
    await Directory(p.dirname(job.outputPath)).create(recursive: true);

    final args = buildFfmpegArgs(
      input: job.input.path,
      output: temporary,
      plan: job.plan,
      sample: job.sample,
    );
    final stopwatch = Stopwatch()..start();
    final run = await _runner.start(args);
    final estimator = ProgressEstimator(job.durationToConvert);
    // One subscription feeds the estimator, however many listeners there are.
    final progress = StreamController<JobProgress>.broadcast();
    run.progress.listen(
      (snapshot) => progress.add(estimator.update(snapshot, stopwatch.elapsed)),
      onDone: progress.close,
    );
    final result = run.result.then(
      (outcome) => _finish(job, temporary, outcome, stopwatch),
    );
    return _FfmpegConversionHandle(run, stopwatch, progress.stream, result);
  }

  Future<ConversionResult> _finish(
    ConversionJob job,
    String temporary,
    RunResult outcome,
    Stopwatch stopwatch,
  ) async {
    stopwatch.stop();
    final partial = File(temporary);
    if (outcome.status != RunStatus.completed) {
      await _discard(partial);
      return ConversionResult(
        status: outcome.status == RunStatus.cancelled
            ? ConversionStatus.cancelled
            : ConversionStatus.failed,
        elapsed: stopwatch.elapsed,
        errorLines: outcome.errorLines,
      );
    }

    final File output;
    try {
      output = await partial.rename(job.outputPath);
    } on FileSystemException catch (e) {
      // Something took the name meanwhile, or the folder went away.
      await _discard(partial);
      return ConversionResult(
        status: ConversionStatus.failed,
        elapsed: stopwatch.elapsed,
        errorLines: ['$e'],
      );
    }
    if (job.plan.keepFileDate) {
      // Keeps converted footage sorted by shooting date in file managers.
      // Only a convenience: the original may be gone by now (a card pulled
      // out), and the result is whole all the same.
      try {
        final modified = await File(job.input.path).lastModified();
        await output.setLastModified(modified);
      } on FileSystemException {
        // Left with the time it was written.
      }
    }
    return ConversionResult(
      status: ConversionStatus.done,
      elapsed: stopwatch.elapsed,
      outputPath: output.path,
      outputBytes: await output.length(),
    );
  }

  /// Deletes the unfinished file, where it can. One that cannot be deleted
  /// is hidden, and does not change how the conversion ended.
  Future<void> _discard(File partial) async {
    try {
      if (await partial.exists()) await partial.delete();
    } on FileSystemException {
      // Left behind, hidden.
    }
  }
}
