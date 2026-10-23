import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/estimate/size_estimator.dart';
import '../../core/ffmpeg/command_builder.dart';
import '../../core/media/media_info.dart';
import '../../core/output/output_namer.dart';
import '../../core/quality/quality_meter.dart';
import '../../core/quality/quality_search.dart';
import '../../core/queue/job_executor.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../estimates/estimate_cache.dart';
import '../providers.dart';
import '../recipe/recipe.dart';
import '../recipe/recipe_controller.dart';
import '../sources/sources_controller.dart';
import 'queue_state.dart';

final queueProvider = NotifierProvider<QueueController, QueueState>(
  QueueController.new,
);

/// The conversions to do, in order. Adding a job starts the queue if it is
/// not already running; the list stays editable throughout.
class QueueController extends Notifier<QueueState> {
  late AppEnvironment _env;
  var _nextId = 0;
  ConversionHandle? _activeHandle;

  /// The job measuring its video before converting, if one is.
  int? _checkingJob;

  /// Set when that measuring is to stop.
  var _checkCancelled = false;

  /// Set when it stopped for a pause: the job waits and measures again.
  var _checkPaused = false;

  /// The loop working through the queue, while there is one.
  Future<void>? _loop;
  var _shuttingDown = false;

  @override
  QueueState build() {
    _env = ref.watch(environmentProvider).requireValue;
    return const QueueState();
  }

  // ---- Adding -----------------------------------------------------------

  /// Queues the selected videos with the panel's current settings.
  void addSelected() => _addWithPanel(ref.read(sourcesProvider).selectedReady);

  /// Queues every video in the list with the panel's current settings.
  void addAll() => _addWithPanel(ref.read(sourcesProvider).ready);

  /// How many of [videos] Add would actually queue: a video that already has
  /// an identical job waiting or under way is not queued twice.
  int addable(List<SourceVideo> videos) {
    final settings = ref.read(recipeProvider);
    return videos
        .where((v) => !_alreadyQueued(v.id, settings.recipe, settings.output))
        .length;
  }

  void _addWithPanel(List<SourceVideo> videos) {
    final settings = ref.read(recipeProvider);
    addVideos(videos, recipe: settings.recipe, output: settings.output);
  }

  /// Queues [videos] with [recipe] and [output], as Add does with the
  /// panel's. `alreadyQueued` holds the ids skipped because an identical job
  /// is waiting or under way.
  ({List<QueueJob> added, List<int> alreadyQueued}) addVideos(
    List<SourceVideo> videos, {
    required Recipe recipe,
    required OutputSettings output,
  }) {
    final reserved = _reservedOutputs();
    final added = <QueueJob>[];
    final alreadyQueued = <int>[];
    for (final video in videos) {
      // The same recipe and output for every video here, so a repeated id is
      // a duplicate of the job just made for it.
      if (added.any((job) => job.sourceId == video.id) ||
          _alreadyQueued(video.id, recipe, output)) {
        alreadyQueued.add(video.id);
        continue;
      }
      final job = _makeJob(
        sourceId: video.id,
        info: video.info!,
        recipe: recipe,
        output: output,
        reserved: reserved,
      );
      reserved.add(job.outputPath);
      added.add(job);
    }
    if (added.isNotEmpty) {
      state = state.copyWith(jobs: [...state.jobs, ...added]);
      _ensureRunning();
    }
    return (added: added, alreadyQueued: alreadyQueued);
  }

  bool _alreadyQueued(int sourceId, Recipe recipe, OutputSettings output) =>
      state.jobs.any(
        (job) =>
            job.isPending &&
            job.sourceId == sourceId &&
            job.recipe == recipe &&
            sameOutput(job.output, output),
      );

  QueueJob _makeJob({
    required int sourceId,
    required MediaInfo info,
    required Recipe recipe,
    required OutputSettings output,
    required Set<String> reserved,
    int? id,
    QualityChoice? quality,
  }) {
    final preset = findPreset(recipe.presetId)!;
    var plan = preset.plan(info, recipe.values, _env.capabilities);
    // Where the quality for this video is known, the job starts with it.
    QualityChoice? choice;
    if (preset case final RaisesQuality raise) {
      choice = _forJob(quality ?? _knownChoice(info.path, recipe), recipe);
      if (choice != null && choice.converts) {
        plan = planWithChoice(raise, plan, choice);
      }
    }
    return QueueJob(
      id: id ?? _nextId++,
      sourceId: sourceId,
      info: info,
      recipe: recipe,
      plan: plan,
      output: output,
      sample: sampleRangeFor(recipe.sample, info.duration),
      // One left as it is writes nothing.
      outputPath: plan.producesOutput && choice?.converts != false
          ? _outputPath(info, plan, recipe, output, reserved)
          : '',
      quality: choice,
    );
  }

  /// The quality already chosen for [path] with [recipe]'s goal, by the
  /// video list's measuring or an earlier job.
  QualityChoice? _knownChoice(String path, Recipe recipe) => ref
      .read(estimateCacheProvider)
      .estimates[estimateKey(path, recipe)]
      ?.choice;

  /// [choice] for a job with [recipe]: a sample asked for is made even of a
  /// video not worth converting, to show what converting would give.
  QualityChoice? _forJob(QualityChoice? choice, Recipe recipe) =>
      recipe.isSample && choice?.converts == false ? choice!.anyway() : choice;

  /// The goal of [job] where it raises the quality of videos that need it,
  /// and the job's result can be compared with its original to tell.
  RaisesQuality? _raiserFor(QueueJob job) {
    return switch (findPreset(job.recipe.presetId)) {
      final RaisesQuality raise
          when canComparePlan(job.plan) &&
              _env.capabilities.hasFilter('xpsnr') =>
        raise,
      _ => null,
    };
  }

  /// `<folder>/<name><settings tag>.<ext>`; samples go to a `Samples`
  /// folder inside the output folder and are marked as samples.
  String _outputPath(
    MediaInfo info,
    ConversionPlan plan,
    Recipe recipe,
    OutputSettings output,
    Set<String> reserved,
  ) {
    var settings = output;
    var suffix = plan.nameSuffix;
    if (recipe.isSample) {
      final customDir = output.customDir;
      final base = output.mode == OutputMode.customFolder && customDir != null
          ? customDir
          : p.join(p.dirname(info.path), output.subfolderName);
      settings = OutputSettings(
        mode: OutputMode.customFolder,
        customDir: p.join(base, 'Samples'),
      );
      suffix += sampleSuffix(recipe.sample);
    }
    return planOutputPath(
      sourcePath: info.path,
      settings: settings,
      suffix: suffix,
      extension: plan.extension,
      exists: (path) => File(path).existsSync(),
      reserved: reserved,
    );
  }

  /// Output names promised to jobs that will still write them, or wrote them.
  Set<String> _reservedOutputs() => {
    for (final job in state.jobs)
      if (job.outputPath.isNotEmpty && !job.canRetry) job.outputPath,
  };

  // ---- Running ----------------------------------------------------------

  void _ensureRunning() {
    if (state.busy || state.paused || state.waiting.isEmpty) return;
    _loop = _run();
  }

  Future<void> _run() async {
    state = state.copyWith(busy: true);
    // Measuring sizes competes with converting for the processor.
    unawaited(ref.read(estimateCacheProvider.notifier).stopMeasuring());
    await _env.sleepInhibitor.acquire();
    try {
      while (ref.mounted && !state.paused) {
        final waiting = state.waiting;
        if (waiting.isEmpty) break;
        await _convert(waiting.first);
      }
    } finally {
      await _env.sleepInhibitor.release();
      if (ref.mounted) state = state.copyWith(busy: false);
    }
    // Continued while the loop was ending.
    if (ref.mounted && !_shuttingDown) _ensureRunning();
  }

  Future<void> _convert(QueueJob queued) async {
    if (!queued.plan.producesOutput) {
      _update(queued.id, (j) => j.copyWith(status: JobStatus.skipped));
      return;
    }
    var job = queued;
    final raise = _raiserFor(job);
    if (raise != null && job.quality == null) {
      final choice = _forJob(
        _knownChoice(job.path, job.recipe) ?? await _check(job, raise),
        job.recipe,
      );
      if (!ref.mounted) return;
      if (_checkPaused) {
        _checkPaused = false;
        _update(
          job.id,
          (j) => j.copyWith(status: JobStatus.waiting, clearAttempt: true),
        );
        return;
      }
      if (_checkCancelled) {
        _checkCancelled = false;
        _update(
          job.id,
          (j) => j.copyWith(status: JobStatus.cancelled, clearAttempt: true),
        );
        return;
      }
      _update(job.id, (j) {
        if (choice == null) return j.copyWith(clearAttempt: true);
        final plan = choice.converts
            ? planWithChoice(raise, j.plan, choice)
            : j.plan;
        return j.copyWith(
          plan: plan,
          quality: choice,
          clearAttempt: true,
          // Named for the quality chosen; one left as it is writes nothing.
          outputPath: choice.converts
              ? _outputPath(
                  j.info,
                  plan,
                  j.recipe,
                  j.output,
                  _reservedOutputs()..remove(j.outputPath),
                )
              : '',
        );
      });
      final checked = _find(job.id);
      // Removed while its video was measured.
      if (checked == null) return;
      job = checked;
      // Paused meanwhile: it waits, its quality known.
      if (state.paused) {
        _update(job.id, (j) => j.copyWith(status: JobStatus.waiting));
        return;
      }
    }
    if (job.keptAsIs) {
      _update(
        job.id,
        (j) => j.copyWith(status: JobStatus.skipped, outputPath: ''),
      );
      return;
    }
    // Something may have appeared under that name since the job was added.
    var outputPath = job.outputPath;
    if (File(outputPath).existsSync()) {
      outputPath = _outputPath(
        job.info,
        job.plan,
        job.recipe,
        job.output,
        _reservedOutputs()..remove(job.outputPath),
      );
    }
    _update(
      job.id,
      (j) => j.copyWith(status: JobStatus.running, outputPath: outputPath),
    );

    final ConversionResult result;
    try {
      final handle = await _env.executor.start(
        ConversionJob(
          input: job.info,
          plan: job.plan,
          outputPath: outputPath,
          sample: job.sample,
        ),
      );
      _activeHandle = handle;
      // Asked to shut down, or taken out of the queue, while this job was
      // starting: nothing could be cancelled then.
      if (_shuttingDown || _find(job.id) == null) unawaited(handle.cancel());
      final updates = handle.progress.listen(
        (progress) => _update(job.id, (j) => j.copyWith(progress: progress)),
      );
      result = await handle.result;
      unawaited(updates.cancel());
    } on Object catch (error) {
      // The conversion could not even be started (FFmpeg vanished, the
      // output folder is not writable).
      _update(
        job.id,
        (j) => j.copyWith(
          status: JobStatus.failed,
          result: ConversionResult(
            status: ConversionStatus.failed,
            elapsed: Duration.zero,
            errorLines: ['$error'],
          ),
        ),
      );
      return;
    } finally {
      _activeHandle = null;
    }

    _update(
      job.id,
      (j) => j.copyWith(
        status: switch (result.status) {
          ConversionStatus.done => JobStatus.done,
          ConversionStatus.failed => JobStatus.failed,
          ConversionStatus.cancelled => JobStatus.cancelled,
        },
        result: result,
      ),
    );
    final estimate = wholeVideoEstimate(job, result);
    if (estimate != null && ref.mounted) {
      ref
          .read(estimateCacheProvider.notifier)
          .learn(estimateKey(job.path, job.recipe), estimate);
    }
  }

  /// Measures [job]'s video at the goal's standard quality and, where it
  /// falls short, at better ones; the result is kept for the video list too.
  /// Null when it could not be measured: the job then converts at the
  /// standard quality.
  Future<QualityChoice?> _check(QueueJob job, RaisesQuality raise) async {
    _checkingJob = job.id;
    _update(job.id, (j) => j.copyWith(status: JobStatus.running, attempt: 1));
    try {
      final estimate = await _env.estimator.estimate(
        job.info,
        job.plan,
        raise: raise,
        onAttempt: (attempt) =>
            _update(job.id, (j) => j.copyWith(attempt: attempt)),
      );
      if (estimate != null && ref.mounted && !_checkCancelled) {
        ref
            .read(estimateCacheProvider.notifier)
            .record(estimateKey(job.path, job.recipe), estimate);
      }
      return estimate?.choice;
    } on Object {
      return null;
    } finally {
      _checkingJob = null;
    }
  }

  // ---- Controls ---------------------------------------------------------

  /// Pauses the queue: the job under way is suspended (where the system
  /// allows; otherwise it finishes) and nothing new starts. Calling again
  /// continues.
  void togglePause() => state.paused ? resume() : pause();

  /// Pauses the queue; does nothing if it is paused already.
  void pause() {
    if (state.paused) return;
    final active = state.activeJob;
    state = state.copyWith(paused: true);
    if (_checkingJob != null) {
      // Measuring cannot be held midway; it starts again on continuing.
      _checkPaused = true;
      unawaited(_env.estimator.cancelAll());
    } else if (active != null && (_activeHandle?.pause() ?? false)) {
      _update(active.id, (j) => j.copyWith(status: JobStatus.paused));
    }
  }

  /// Continues the queue; does nothing if it is not paused.
  void resume() {
    if (!state.paused) return;
    final active = state.activeJob;
    state = state.copyWith(paused: false);
    if (active != null && (_activeHandle?.resume() ?? false)) {
      _update(active.id, (j) => j.copyWith(status: JobStatus.running));
    }
    _ensureRunning();
  }

  /// Cancels the job under way; the queue moves on to the next one.
  Future<void> cancelActive() async {
    if (_checkingJob != null) {
      _checkCancelled = true;
      await _env.estimator.cancelAll();
      return;
    }
    if (state.activeJob?.status == JobStatus.paused) _activeHandle?.resume();
    await _activeHandle?.cancel();
  }

  /// Stops for good, as when the app closes: nothing new starts and the job
  /// under way is cancelled. Completes once FFmpeg has exited and the
  /// unfinished file is removed. Leaving sooner would let FFmpeg carry on
  /// alone and the unfinished file stay behind.
  Future<void> shutDown() async {
    _shuttingDown = true;
    state = state.copyWith(paused: true);
    await cancelActive();
    await _loop;
  }

  /// Takes a job off the list, cancelling it first if it is under way.
  Future<void> remove(int jobId) async {
    final job = _find(jobId);
    if (job == null) return;
    if (job.isActive) await cancelActive();
    state = state.copyWith(
      jobs: [
        for (final j in state.jobs)
          if (j.id != jobId) j,
      ],
    );
  }

  /// Moves the job at [oldIndex] so that it ends up at [newIndex].
  void reorder(int oldIndex, int newIndex) {
    final jobs = [...state.jobs];
    jobs.insert(newIndex, jobs.removeAt(oldIndex));
    state = state.copyWith(jobs: jobs);
  }

  void retry(int jobId) {
    _update(jobId, (j) {
      if (!j.canRetry) return j;
      return j.copyWith(status: JobStatus.waiting, clearProgress: true);
    });
    _ensureRunning();
  }

  void clearFinished() {
    state = state.copyWith(
      jobs: [
        for (final j in state.jobs)
          if (!j.isFinished) j,
      ],
    );
  }

  /// After a sample: queues the whole video with the same settings. Returns
  /// the new job; null when there is none, an identical one included.
  QueueJob? convertWhole(int jobId) {
    final job = _find(jobId);
    if (job == null || !job.isSample) return null;
    final recipe = job.recipe.withoutSample();
    if (_alreadyQueued(job.sourceId, recipe, job.output)) return null;
    final whole = _makeJob(
      sourceId: job.sourceId,
      info: job.info,
      recipe: recipe,
      output: job.output,
      reserved: _reservedOutputs(),
    );
    state = state.copyWith(jobs: [...state.jobs, whole]);
    _ensureRunning();
    return whole;
  }

  /// After a video was left as it is: converts it all the same, at the
  /// quality found for it. Returns the new job; null when there is none, an
  /// identical one included.
  QueueJob? convertAnyway(int jobId) {
    final job = _find(jobId);
    final quality = job?.quality;
    if (job == null || quality == null || !job.keptAsIs) return null;
    if (_alreadyQueued(job.sourceId, job.recipe, job.output)) return null;
    final anyway = _makeJob(
      sourceId: job.sourceId,
      info: job.info,
      recipe: job.recipe,
      output: job.output,
      reserved: _reservedOutputs(),
      quality: quality.anyway(),
    );
    state = state.copyWith(jobs: [...state.jobs, anyway]);
    _ensureRunning();
    return anyway;
  }

  /// Puts a job's settings back into the panel and selects its video, to
  /// adjust them and queue again.
  void useSettings(int jobId) {
    final job = _find(jobId);
    if (job == null) return;
    ref.read(recipeProvider.notifier).load(job.recipe);
    ref.read(sourcesProvider.notifier).select(job.sourceId);
  }

  // ---- Showing ----------------------------------------------------------

  /// The FFmpeg arguments for [job] as shown to people.
  List<String>? commandFor(QueueJob job) {
    // One left as it is runs nothing.
    if (!job.plan.producesOutput || job.outputPath.isEmpty) return null;
    return buildFfmpegArgs(
      input: job.path,
      output: job.outputPath,
      plan: job.plan,
      sample: job.sample,
      forDisplay: true,
    );
  }

  /// The arguments [video] would get with the panel's current settings.
  List<String>? commandForVideo(SourceVideo video) {
    final info = video.info;
    if (info == null) return null;
    final settings = ref.read(recipeProvider);
    return commandFor(
      _makeJob(
        id: -1,
        sourceId: video.id,
        info: info,
        recipe: settings.recipe,
        output: settings.output,
        reserved: _reservedOutputs(),
      ),
    );
  }

  QueueJob? _find(int id) {
    for (final job in state.jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  void _update(int id, QueueJob Function(QueueJob) change) {
    if (!ref.mounted) return;
    state = state.copyWith(
      jobs: [for (final job in state.jobs) job.id == id ? change(job) : job],
    );
  }
}

/// What a finished sample says about the whole video: its size and the time
/// it took, scaled up by how much of the video the sample covered.
OutputEstimate? wholeVideoEstimate(QueueJob job, ConversionResult result) {
  final sample = job.sample;
  final bytes = result.outputBytes;
  if (sample == null ||
      bytes == null ||
      result.status != ConversionStatus.done ||
      sample.length <= Duration.zero) {
    return null;
  }
  final scale = job.info.duration.inMicroseconds / sample.length.inMicroseconds;
  return OutputEstimate(
    bytes: (bytes * scale).round(),
    time: result.elapsed * scale,
    measured: true,
  );
}
