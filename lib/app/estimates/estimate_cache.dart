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
    this.failed = const {},
  });

  /// Whole-video estimates by [estimateKey].
  final Map<String, OutputEstimate> estimates;
  final Set<String> measuring;
  final Set<String> failed;

  EstimateCacheState copyWith({
    Map<String, OutputEstimate>? estimates,
    Set<String>? measuring,
    Set<String>? failed,
  }) => EstimateCacheState(
    estimates: estimates ?? this.estimates,
    measuring: measuring ?? this.measuring,
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
  /// being measured, or could not be measured before.
  Future<void> measure(String key, MediaInfo info, ConversionPlan plan) async {
    if (state.estimates.containsKey(key) ||
        state.measuring.contains(key) ||
        state.failed.contains(key)) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(measuring: {...state.measuring, key});
    OutputEstimate? estimate;
    try {
      estimate = await _env.estimator.estimate(info, plan);
    } on Object {
      estimate = null;
    }
    if (!ref.mounted) return;
    final stopped = generation != _generation;
    state = state.copyWith(
      measuring: {...state.measuring}..remove(key),
      estimates: estimate == null ? null : {...state.estimates, key: estimate},
      // A stopped measurement is tried again later; a failed one is not.
      failed: estimate == null && !stopped ? {...state.failed, key} : null,
    );
  }

  /// Records what a finished sample showed about the whole video. Ten seconds
  /// measure better than the automatic three-second pieces, so this wins.
  /// The sample says nothing about closeness, so the measured one stays.
  void learn(String key, OutputEstimate estimate) {
    final learned = OutputEstimate(
      bytes: estimate.bytes,
      time: estimate.time,
      measured: estimate.measured,
      quality: estimate.quality ?? state.estimates[key]?.quality,
    );
    state = state.copyWith(estimates: {...state.estimates, key: learned});
  }

  /// Stops measuring, so converting gets the whole processor. Completes once
  /// FFmpeg has exited.
  Future<void> stopMeasuring() async {
    if (state.measuring.isEmpty) return;
    _generation++;
    await _env.estimator.cancelAll();
  }
}
