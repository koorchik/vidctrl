import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/estimates/estimate_cache.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/quality/quality_controller.dart';
import 'package:vidctrl/app/queue/queue_controller.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/app/recipe/recipe_controller.dart';
import 'package:vidctrl/app/settings.dart';
import 'package:vidctrl/app/sources/preview_controller.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/settings/settings_store.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';

void main() {
  late FakeEnvironment env;
  late ProviderContainer container;

  SourcesController sources() => container.read(sourcesProvider.notifier);
  RecipeController recipe() => container.read(recipeProvider.notifier);
  QueueController queue() => container.read(queueProvider.notifier);
  SourcesState sourceState() => container.read(sourcesProvider);
  QueueState queueState() => container.read(queueProvider);
  List<QueueJob> jobs() => queueState().jobs;
  SourceVideo video(String name) =>
      sourceState().videos.firstWhere((v) => v.path.endsWith('/$name'));
  String converted(String name) => p.join('/videos', 'Converted', name);

  /// Lets queued-up asynchronous work run.
  Future<void> settle() => pumpEventQueue();

  Future<ProviderContainer> start({SettingsStore? settings}) async {
    final next = ProviderContainer(
      overrides: [
        ...env.overrides,
        if (settings != null) settingsStoreProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(next.dispose);
    await next.read(environmentProvider.future);
    // The video list keeps previews alive, as the screen does.
    next.listen(previewProvider, (_, _) {});
    return next;
  }

  setUp(() async {
    env = FakeEnvironment();
    for (final name in ['a.mp4', 'b.mp4', 'c.mp4']) {
      env.ffprobe.add('/videos/$name');
    }
    container = await start();
  });

  group('videos', () {
    test('a file is listed once, however often it is added', () async {
      await sources().addPaths(['/videos/a.mp4']);
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);

      expect(sourceState().videos.map((v) => v.path), [
        '/videos/a.mp4',
        '/videos/b.mp4',
      ]);
    });

    test('newly added videos become the selection', () async {
      await sources().addPaths(['/videos/a.mp4']);
      await sources().addPaths(['/videos/b.mp4', '/videos/c.mp4']);

      expect(sourceState().selectedIds, {video('b.mp4').id, video('c.mp4').id});
    });

    test(
      'a file that is not a video is listed but cannot be selected',
      () async {
        await sources().addPaths(['/videos/notes.txt']);

        expect(video('notes.txt').status, SourceStatus.unreadable);
        expect(sourceState().selectedIds, isEmpty);
        sources().select(video('notes.txt').id);
        expect(sourceState().selectedIds, isEmpty);
      },
    );

    test('clicking selects one; the checkbox adds and removes', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);

      sources().select(video('a.mp4').id);
      expect(sourceState().selectedIds, {video('a.mp4').id});
      sources().toggle(video('b.mp4').id);
      expect(sourceState().selectedIds, hasLength(2));
      sources().toggle(video('a.mp4').id);
      expect(sourceState().selectedIds, {video('b.mp4').id});
      sources().clearSelection();
      expect(sourceState().selectedIds, isEmpty);
      sources().selectAll();
      expect(sourceState().selectedIds, hasLength(2));
    });
  });

  group('adding to the queue', () {
    test('each selected video becomes a job, and the queue starts', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);

      queue().addSelected();
      await settle();

      expect(jobs().map((j) => j.outputPath), [
        converted('a_av1-crf35.mp4'),
        converted('b_av1-crf35.mp4'),
      ]);
      expect(jobs().first.status, JobStatus.running);
      expect(env.executor.started, hasLength(1));
    });

    test('Add all takes every readable video, whatever is selected', () async {
      await sources().addPaths([
        '/videos/a.mp4',
        '/videos/b.mp4',
        '/videos/notes.txt',
      ]);
      sources().select(video('a.mp4').id);

      queue().addAll();

      expect(jobs().map((j) => p.basename(j.path)), ['a.mp4', 'b.mp4']);
    });

    test('a job keeps its settings when the panel changes later', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().addSelected();

      recipe().selectPreset('space.small');

      expect(jobs().single.recipe.presetId, 'archive.master');
      expect(jobs().single.plan.nameSuffix, '_av1-crf35');
    });

    test(
      'changed settings and Add again give a second, differently named job',
      () async {
        await sources().addPaths(['/videos/a.mp4']);
        queue().addSelected();

        recipe().setOption('codec', 'hevc');
        queue().addSelected();

        expect(jobs().map((j) => p.basename(j.outputPath)), [
          'a_av1-crf35.mp4',
          'a_hevc-crf24.mp4',
        ]);
      },
    );

    test('an identical job waiting or under way is not added twice', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
      queue().addSelected();

      expect(queue().addable(sourceState().selectedReady), 0);
      queue().addSelected();

      expect(jobs(), hasLength(2));
    });

    test('a finished job can be queued again, under a new name', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().addSelected();
      await settle();
      env.executor.last.finish();
      await settle();

      queue().addSelected();

      expect(jobs().last.outputPath, converted('a_av1-crf35 (2).mp4'));
    });

    test('a video that is already right is skipped, not converted', () async {
      env.ffprobe.add(
        '/videos/nikon.mov',
        like: clip(video: 'hevc', audio: [track('pcm_s24le')]),
      );
      await sources().addPaths(['/videos/nikon.mov']);
      recipe().selectPreset('resolve.studio');

      queue().addSelected();
      await settle();

      expect(jobs().single.status, JobStatus.skipped);
      expect(env.executor.started, isEmpty);
    });
  });

  group('running', () {
    test('jobs run one after another, in order', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
      queue().addSelected();
      await settle();

      env.executor.last.finish();
      await settle();
      expect(jobs().map((j) => j.status), [JobStatus.done, JobStatus.running]);
      env.executor.last.finish();
      await settle();

      expect(queueState().busy, isFalse);
      expect(env.executor.startedNames, ['a.mp4', 'b.mp4']);
    });

    test('the computer is kept awake only while the queue runs', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().addSelected();
      await settle();
      expect(env.inhibitor.isActive, isTrue);

      env.executor.last.finish();
      await settle();

      expect(env.inhibitor.isActive, isFalse);
    });

    test('pause holds the queue; continue goes on', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
      queue().addSelected();
      await settle();

      queue().togglePause();
      expect(jobs().first.status, JobStatus.paused);
      expect(env.executor.last.paused, isTrue);

      queue().togglePause();
      expect(jobs().first.status, JobStatus.running);
      env.executor.last.finish();
      await settle();
      expect(jobs().last.status, JobStatus.running);
    });

    test('a job added while paused waits for continue', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().togglePause();

      queue().addSelected();
      await settle();

      expect(jobs().single.status, JobStatus.waiting);
      expect(env.executor.started, isEmpty);
    });

    test('cancelling the running job moves on to the next', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
      queue().addSelected();
      await settle();

      await queue().cancelActive();
      await settle();

      expect(jobs().map((j) => j.status), [
        JobStatus.cancelled,
        JobStatus.running,
      ]);
    });

    test('shutting down cancels the running job and starts no other', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
      queue().addSelected();
      await settle();

      await queue().shutDown();

      expect(jobs().map((j) => j.status), [
        JobStatus.cancelled,
        JobStatus.waiting,
      ]);
      expect(env.executor.started, hasLength(1));
      expect(queueState().busy, isFalse);
    });

    test('waiting jobs can be removed and reordered', () async {
      await sources().addPaths([
        '/videos/a.mp4',
        '/videos/b.mp4',
        '/videos/c.mp4',
      ]);
      queue().addSelected();
      await settle();

      queue().reorder(2, 1);
      await queue().remove(jobs().last.id);
      for (var i = 0; i < 2; i++) {
        env.executor.last.finish();
        await settle();
      }

      expect(env.executor.startedNames, ['a.mp4', 'c.mp4']);
    });

    test('a failed job can be tried again', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().addSelected();
      await settle();
      env.executor.last.fail();
      await settle();
      expect(jobs().single.status, JobStatus.failed);

      queue().retry(jobs().single.id);
      await settle();

      expect(jobs().single.status, JobStatus.running);
      expect(env.executor.started, hasLength(2));
    });

    test('removing a video keeps the jobs made from it', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().addSelected();

      sources().remove(video('a.mp4').id);

      expect(jobs(), hasLength(1));
    });
  });

  group('comparing with the original', () {
    QualityController quality() => container.read(qualityProvider.notifier);
    QualityCheck? check(QueueJob job) =>
        container.read(qualityProvider)[job.id];

    /// The given videos, converted with the panel's settings.
    Future<List<QueueJob>> convertedJobs(
      List<String> names, {
      SampleChoice? sample,
    }) async {
      await sources().addPaths([for (final name in names) '/videos/$name']);
      if (sample != null) recipe().setSample(sample);
      queue().addSelected();
      await settle();
      for (var i = 0; i < names.length; i++) {
        env.executor.started[i].finish();
        await settle();
      }
      return jobs();
    }

    test('a finished job is compared with its original', () async {
      final job = (await convertedJobs(['a.mp4'])).single;

      final comparing = quality().compare(job);
      await settle();
      final comparison = env.qualityMeter.last;
      expect(comparison.original.path, '/videos/a.mp4');
      expect(
        comparison.resultPath,
        p.join('/videos', 'Converted', 'a_av1-crf35.mp4'),
      );
      expect(comparison.range, isNull);

      comparison.report(0.5);
      await settle();
      expect(
        check(job),
        isA<QualityComparing>().having((c) => c.fraction, 'fraction', 0.5),
      );

      comparison.finish(40.6);
      await comparing;
      expect(
        check(job),
        isA<QualityMeasured>().having(
          (c) => c.closeness,
          'closeness',
          Closeness.veryClose,
        ),
      );
    });

    test('a sample is compared with the same piece of the original', () async {
      final job = (await convertedJobs([
        'a.mp4',
      ], sample: SampleChoice.middle)).single;

      unawaited(quality().compare(job));
      await settle();

      expect(env.qualityMeter.last.range!.start, const Duration(seconds: 25));
      expect(env.qualityMeter.last.range!.length, sampleLength);
    });

    test('a job still converting cannot be compared yet', () async {
      await sources().addPaths(['/videos/a.mp4']);
      queue().addSelected();
      await settle();

      expect(quality().canCompare(jobs().single), isFalse);
    });

    test('one comparison runs at a time', () async {
      final [first, second] = await convertedJobs(['a.mp4', 'b.mp4']);

      unawaited(quality().compare(first));
      await settle();
      unawaited(quality().compare(second));
      await settle();

      expect(env.qualityMeter.started, hasLength(1));
      expect(quality().busy, isTrue);
    });

    test('a stopped comparison leaves no result', () async {
      final job = (await convertedJobs(['a.mp4'])).single;
      unawaited(quality().compare(job));
      await settle();

      await quality().cancel();

      expect(env.qualityMeter.last.cancelRequested, isTrue);
      expect(check(job), isNull);
      expect(quality().busy, isFalse);
    });

    test('a comparison that fails says so', () async {
      final job = (await convertedJobs(['a.mp4'])).single;
      final comparing = quality().compare(job);
      await settle();

      env.qualityMeter.last.fail();
      await comparing;

      expect(check(job), isA<QualityFailed>());
    });

    test('VMAF is measured where the FFmpeg can', () async {
      final job = (await convertedJobs(['a.mp4'])).single;
      unawaited(quality().compare(job));
      await settle();
      expect(env.qualityMeter.last.vmaf, isFalse);
      await quality().cancel();

      env = FakeEnvironment(
        capabilities: Capabilities(
          ffmpegVersion: 'test',
          encoders: softwareOnly.encoders,
          filters: {'xpsnr', 'libvmaf'},
          svtAv1Params: 'tune=0',
        ),
      );
      env.ffprobe.add('/videos/a.mp4');
      container = await start();
      final withVmaf = (await convertedJobs(['a.mp4'])).single;
      unawaited(quality().compare(withVmaf));
      await settle();

      expect(env.qualityMeter.last.vmaf, isTrue);
    });

    test('nothing is compared without the filter that compares', () async {
      env = FakeEnvironment(
        capabilities: Capabilities(
          ffmpegVersion: 'test',
          encoders: softwareOnly.encoders,
          svtAv1Params: 'tune=0',
        ),
      );
      env.ffprobe.add('/videos/a.mp4');
      container = await start();
      final job = (await convertedJobs(['a.mp4'])).single;

      expect(quality().canCompare(job), isFalse);
    });
  });

  group('samples', () {
    test('a sample goes to Samples with a marked name', () async {
      await sources().addPaths(['/videos/a.mp4']);
      recipe().setSample(SampleChoice.start);

      queue().addSelected();
      await settle();

      final job = jobs().single;
      expect(
        job.outputPath,
        p.join('/videos', 'Converted', 'Samples', 'a_av1-crf35_sample10s.mp4'),
      );
      expect(job.sample!.length, sampleLength);
      expect(env.executor.last.job.sample!.start, Duration.zero);
    });

    test('a sample from the middle is taken from the middle', () async {
      await sources().addPaths(['/videos/a.mp4']);
      recipe().setSample(SampleChoice.middle);

      queue().addSelected();

      // The default clip is a minute long.
      expect(jobs().single.sample!.start, const Duration(seconds: 25));
      expect(jobs().single.outputPath, endsWith('_sample10s-mid.mp4'));
    });

    test('several samples of one video with different settings', () async {
      await sources().addPaths(['/videos/a.mp4']);
      recipe().setSample(SampleChoice.start);

      queue().addSelected();
      recipe().setOption('codec', 'hevc');
      queue().addSelected();

      expect(jobs().map((j) => p.basename(j.outputPath)), [
        'a_av1-crf35_sample10s.mp4',
        'a_hevc-crf24_sample10s.mp4',
      ]);
    });

    test(
      'a finished sample tells the expected size of the whole video',
      () async {
        await sources().addPaths(['/videos/a.mp4']);
        recipe().setSample(SampleChoice.start);
        queue().addSelected();
        await settle();

        env.executor.last.finish(
          bytes: 5000000,
          elapsed: const Duration(seconds: 4),
        );
        await settle();

        final job = jobs().single;
        final whole = wholeVideoEstimate(job, job.result!)!;
        expect(whole.bytes, 30000000);
        expect(whole.time, const Duration(seconds: 24));
        // ...and the same settings for the whole video now know it too.
        final key = estimateKey(job.path, job.recipe.withoutSample());
        expect(
          container.read(estimateCacheProvider).estimates[key]!.bytes,
          30000000,
        );
      },
    );

    test(
      'Convert whole video queues the same settings without the sample',
      () async {
        await sources().addPaths(['/videos/a.mp4']);
        recipe().setSample(SampleChoice.start);
        queue().addSelected();
        await settle();
        env.executor.last.finish();
        await settle();

        queue().convertWhole(jobs().single.id);

        expect(jobs().last.isSample, isFalse);
        expect(jobs().last.outputPath, converted('a_av1-crf35.mp4'));
        expect(jobs().last.recipe.presetId, 'archive.master');
      },
    );

    test('Use these settings restores the panel and the selection', () async {
      await sources().addPaths(['/videos/a.mp4', '/videos/b.mp4']);
      recipe().selectPreset('space.small');
      sources().select(video('a.mp4').id);
      queue().addSelected();
      recipe().selectPreset('archive.master');
      sources().select(video('b.mp4').id);

      queue().useSettings(jobs().single.id);

      expect(container.read(recipeProvider).recipe.presetId, 'space.small');
      expect(sourceState().selectedIds, {video('a.mp4').id});
    });
  });

  group('expected sizes', () {
    test('selected videos are measured while nothing converts', () async {
      await sources().addPaths(['/videos/a.mp4']);
      await settle();

      final preview = container.read(previewProvider)[video('a.mp4').id]!;
      expect(preview.estimate!.bytes, 150000000);
      expect(env.estimator.measured, ['/videos/a.mp4']);
    });

    test('measuring waits while the queue converts', () async {
      env.estimator.hold = true;
      await sources().addPaths(['/videos/a.mp4']);
      await settle();
      queue().addSelected();
      await settle();
      expect(env.estimator.cancels, 1);

      await sources().addPaths(['/videos/b.mp4']);
      await settle();

      expect(env.estimator.measured, ['/videos/a.mp4']);
    });

    test('the measurement says how close the result will look', () async {
      env.estimator.quality = const QualityScore(39.2, vmaf: 92.6);
      await sources().addPaths(['/videos/a.mp4']);
      await settle();

      final preview = container.read(previewProvider)[video('a.mp4').id]!;
      expect(preview.estimate!.quality!.closeness, Closeness.differs);
    });

    test(
      'a finished sample corrects the size and keeps the closeness',
      () async {
        env.estimator.quality = const QualityScore(41.4, vmaf: 96.0);
        await sources().addPaths(['/videos/a.mp4']);
        await settle();
        recipe().setSample(SampleChoice.start);
        queue().addSelected();
        await settle();

        env.executor.last.finish(bytes: 5000000);
        await settle();

        final key = estimateKey('/videos/a.mp4', jobs().single.recipe);
        final estimate = container.read(estimateCacheProvider).estimates[key]!;
        expect(estimate.bytes, 30000000);
        expect(estimate.quality!.vmaf, 96.0);
      },
    );

    test('going back to the default finds what was measured for it', () async {
      await sources().addPaths(['/videos/a.mp4']);
      await settle();
      env.estimator.hold = true;
      recipe().setOption('codec', 'hevc');
      await settle();

      recipe().setOption('codec', 'av1');
      await settle();

      final preview = container.read(previewProvider)[video('a.mp4').id]!;
      expect(preview.estimate, isNotNull);
      // AV1 once, HEVC once: the default chosen again is not measured anew.
      expect(env.estimator.measured, ['/videos/a.mp4', '/videos/a.mp4']);
    });

    test('a video waiting for its turn says it is being measured', () async {
      env.estimator.hold = true;
      final many = [for (var i = 0; i < 5; i++) '/videos/m$i.mp4'];
      for (final path in many) {
        env.ffprobe.add(path);
      }

      await sources().addPaths(many);
      await settle();

      final previews = container.read(previewProvider).values;
      expect(env.estimator.measured.length, lessThan(many.length));
      expect(previews.every((p) => p.measuring), isTrue);
    });

    test('a quick fix is calculated, not measured', () async {
      recipe().selectPreset('resolve.studio');
      await sources().addPaths(['/videos/a.mp4']);
      await settle();

      final preview = container.read(previewProvider)[video('a.mp4').id]!;
      expect(preview.estimate!.measured, isFalse);
      expect(env.estimator.measured, isEmpty);
    });
  });

  group('remembered between runs', () {
    test('the goal and folder are, the sample choice is not', () async {
      final settings = MemorySettingsStore();
      container = await start(settings: settings);
      recipe().selectPreset('resolve.free');
      recipe().setOption('quality', 'best');
      recipe().setSample(SampleChoice.middle);
      recipe().setOutput(
        const OutputSettings(
          mode: OutputMode.customFolder,
          customDir: '/exports',
        ),
      );

      container = await start(settings: settings);

      final restored = container.read(recipeProvider);
      expect(restored.recipe.presetId, 'resolve.free');
      expect(restored.recipe.values, {'quality': 'best'});
      expect(restored.recipe.sample, SampleChoice.none);
      expect(restored.output.customDir, '/exports');
    });

    test('a goal the app no longer has gives way to the default', () async {
      final settings = MemorySettingsStore()
        ..values['goal'] = {'preset': 'compress.hevc', 'values': {}};

      container = await start(settings: settings);

      expect(container.read(recipeProvider).recipe.presetId, 'archive.master');
    });
  });

  test('choosing the goal already chosen keeps its options', () {
    recipe().setOption('codec', 'hevc');

    recipe().selectPreset('archive.master');

    expect(container.read(recipeProvider).recipe.values, {'codec': 'hevc'});
  });
}
