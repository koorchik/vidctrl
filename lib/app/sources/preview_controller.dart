import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/estimate/size_estimator.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';
import '../estimates/estimate_cache.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../recipe/recipe_controller.dart';
import 'sources_controller.dart';

/// What the panel's current settings would do to one selected video.
class Preview {
  const Preview({
    required this.plan,
    this.estimate,
    this.measuring = false,
    this.choosing = false,
  });

  /// The plan for the whole video, at the goal's standard quality.
  final ConversionPlan plan;

  /// Expected output of the whole video; null while unknown.
  final OutputEstimate? estimate;
  final bool measuring;

  /// The standard quality fell short, and a better one is being looked for.
  final bool choosing;

  /// Whether converting leaves the video as it is, being hardly smaller.
  bool get keptAsIs => estimate?.choice?.converts == false;
}

/// Previews by video id, for the selected videos only.
final previewProvider = NotifierProvider<PreviewController, Map<int, Preview>>(
  PreviewController.new,
);

/// Plans each selected video with the current settings and makes sure their
/// expected sizes get measured, while nothing is being converted.
class PreviewController extends Notifier<Map<int, Preview>> {
  @override
  Map<int, Preview> build() {
    final env = ref.watch(environmentProvider).requireValue;
    final videos = ref.watch(sourcesProvider).selectedReady;
    final recipe = ref.watch(recipeProvider.select((s) => s.recipe));
    final cache = ref.watch(estimateCacheProvider);
    final queueBusy = ref.watch(queueProvider.select((q) => q.busy));
    final preset = findPreset(recipe.presetId)!;

    final previews = <int, Preview>{};
    final raise = switch (preset) {
      final RaisesQuality raises => raises,
      _ => null,
    };
    final toMeasure = <(String, SourceVideo, ConversionPlan)>[];
    for (final video in videos) {
      final info = video.info!;
      final plan = preset.plan(info, recipe.values, env.capabilities);
      final key = estimateKey(video.path, recipe);
      final estimate =
          estimateWithoutEncoding(info, plan) ?? cache.estimates[key];
      final pending =
          estimate == null &&
          plan.producesOutput &&
          plan.video is VideoEncode &&
          !cache.measuring.contains(key) &&
          !cache.failed.contains(key);
      previews[video.id] = Preview(
        plan: plan,
        estimate: estimate,
        // One waiting for its turn is measured as soon as another is done.
        measuring: cache.measuring.contains(key) || (pending && !queueBusy),
        choosing: cache.choosing(key),
      );
      if (pending) toMeasure.add((key, video, plan));
    }

    if (!queueBusy && toMeasure.isNotEmpty) {
      // Started after this build: measuring updates the cache, which
      // rebuilds the previews with the result.
      Future.microtask(() {
        if (!ref.mounted) return;
        final estimates = ref.read(estimateCacheProvider.notifier);
        for (final (key, video, plan) in toMeasure) {
          if (estimates.room(plan) <= 0) break;
          unawaited(estimates.measure(key, video.info!, plan, raise: raise));
        }
      });
    }
    return previews;
  }
}
