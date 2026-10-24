import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/estimate/size_estimator.dart';
import '../../core/media/media_info.dart';
import '../../core/scenarios/scenario.dart';
import '../providers.dart';
import '../recipe/recipe.dart';

/// Identifies the expected output of a video converted with a goal: samples
/// and whole-video jobs with the same goal share it.
String estimateKey(String path, Recipe recipe) => '$path|${recipe.goalKey}';

class EstimateCacheState {
  const EstimateCacheState({
    this.estimates = const {},
    this.measuring = const {},
    this.attempts = const {},
    this.failed = const {},
  });

  /// Whole-video estimates by [estimateKey].
  final Map<String, OutputEstimate> estimates;
  final Set<String> measuring;

  /// The try under way where the quality is being chosen: 1 measures the
  /// standard quality, from 2 on better ones are tried.
  final Map<String, int> attempts;
  final Set<String> failed;

  /// Whether a better quality is being looked for.
  bool choosing(String key) => (attempts[key] ?? 0) > 1;

  EstimateCacheState copyWith({
    Map<String, OutputEstimate>? estimates,
    Set<String>? measuring,
    Map<String, int>? attempts,
    Set<String>? failed,
  }) => EstimateCacheState(
    estimates: estimates ?? this.estimates,
    measuring: measuring ?? this.measuring,
    attempts: attempts ?? this.attempts,
    failed: failed ?? this.failed,
  );
}

final estimateCacheProvider =
    NotifierProvider<EstimateCache, EstimateCacheState>(EstimateCache.new);

/// Expected output sizes and closeness to the original, measured or learned
/// from finished samples, shared by the video list and the queue.
class EstimateCache extends Notifier<EstimateCacheState> {
  late AppEnvironment _env;

  /// Raised to discard measurements that were under way when stopped.
  var _generation = 0;

  /// Set as the app leaves: a measurement started then would outlive it.
  var _left = false;

  @override
  EstimateCacheState build() {
    _env = ref.watch(environmentProvider).requireValue;
    ref.onDispose(_env.estimator.cancelAll);
    return const EstimateCacheState();
  }

  /// How many more measurements the processor has room for, given the cost
  /// of [plan].
  int room(ConversionPlan plan) =>
      (Platform.numberOfProcessors / plan.cost.cpuThreads).floor().clamp(1, 3) -
      state.measuring.length;

  /// Measures the expected size of [plan] on [info], unless it is known,
  /// being measured, or could not be measured before. With [raise], the
  /// quality is raised where the standard one falls short.
  Future<void> measure(
    String key,
    MediaInfo info,
    ConversionPlan plan, {
    RaisesQuality? raise,
  }) async {
    if (_left ||
        state.estimates.containsKey(key) ||
        state.measuring.contains(key) ||
        state.failed.contains(key)) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(measuring: {...state.measuring, key});
    OutputEstimate? estimate;
    try {
      estimate = await _env.estimator.estimate(
        info,
        plan,
        raise: raise,
        onAttempt: (attempt) {
          if (ref.mounted && generation == _generation) {
            state = state.copyWith(attempts: {...state.attempts, key: attempt});
          }
        },
      );
    } on Object {
      estimate = null;
    }
    if (!ref.mounted) return;
    final stopped = generation != _generation;
    state = state.copyWith(
      measuring: {...state.measuring}..remove(key),
      attempts: {...state.attempts}..remove(key),
      estimates: estimate == null ? null : {...state.estimates, key: estimate},
      // A stopped measurement is tried again later; a failed one is not.
      failed: estimate == null && !stopped ? {...state.failed, key} : null,
    );
  }

  /// Records what a finished sample showed about the whole video. Ten seconds
  /// measure better than the automatic three-second pieces, so this wins.
  /// The sample says nothing about closeness, so the measured one stays,
  /// with the quality chosen for the video.
  void learn(String key, OutputEstimate estimate) {
    final known = state.estimates[key];
    final learned = OutputEstimate(
      bytes: estimate.bytes,
      time: estimate.time,
      measured: estimate.measured,
      quality: estimate.quality ?? known?.quality,
      choice: estimate.choice ?? known?.choice,
    );
    state = state.copyWith(estimates: {...state.estimates, key: learned});
  }

  /// Keeps an estimate made elsewhere, as when a job measured its video
  /// before converting it.
  void record(String key, OutputEstimate estimate) {
    state = state.copyWith(
      estimates: {...state.estimates, key: estimate},
      failed: {...state.failed}..remove(key),
    );
  }

  /// Stops measuring for good and deletes the pieces kept to show hardest
  /// frames, as the app leaves. Completes once FFmpeg has exited.
  Future<void> leave() async {
    _left = true;
    await stopMeasuring();
    await _env.estimator.discardKept();
  }

  /// Stops measuring, so converting gets the whole processor. Completes once
  /// FFmpeg has exited.
  Future<void> stopMeasuring() async {
    if (state.measuring.isEmpty) return;
    _generation++;
    await _env.estimator.cancelAll();
  }
}
