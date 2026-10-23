@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/build_info.dart';
import 'package:vidctrl/app/theme.dart';
import 'package:vidctrl/app/window.dart';
import 'package:vidctrl/core/ffmpeg/locator.dart';
import 'package:vidctrl/core/media/ffprobe.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/quality/quality_search.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';

/// Renders the main screen in its typical states, in each look, to
/// `build/screenshots/`, for looking at the design without starting the app:
///
///   flutter test --tags screenshots
void main() {
  // A frame to stand in for a video's thumbnail; none without FFmpeg.
  Uint8List? frame;

  setUpAll(() async {
    await loadRealFonts();
    final ffmpeg = FfmpegLocator().locate()?.ffmpeg;
    if (ffmpeg == null) return;
    final result = await Process.run(ffmpeg, [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=s=640x360',
      '-frames:v',
      '1',
      '-c:v',
      'mjpeg',
      '-f',
      'image2pipe',
      'pipe:1',
    ], stdoutEncoding: null);
    if (result.exitCode == 0) {
      frame = Uint8List.fromList(result.stdout as List<int>);
    }
  });

  FakeEnvironment environment() {
    final env = FakeEnvironment(
      capabilities: withGpu({'av1_nvenc'}),
      thumbnail: frame,
      // A released build, as people get it: its menu has the version.
      build: const BuildInfo(version: '0.3.0', repository: 'owner/vidctrl'),
      releases: FakeReleaseSource(),
    );
    // What a camera's file measures: nothing to see.
    env.estimator.quality = const QualityScore(41.4, vmaf: 96.0);
    env.frames.picture = frame;
    env.ffprobe.add('/videos/DSC_0412.MOV');
    env.ffprobe.add(
      '/videos/DSC_0413.MOV',
      like: clip(duration: const Duration(minutes: 4, seconds: 12)),
    );
    env.ffprobe.add(
      '/videos/Z5_0007.MOV',
      like: clip(video: 'hevc', audio: [track('pcm_s24le')]),
    );
    final report = jsonDecode(
      File('test/fixtures/hlg_clip_ffprobe.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    env.ffprobe.add(
      '/videos/birthday final export.mov',
      like: parseFfprobeJson('/videos/birthday final export.mov', report),
    );
    return env;
  }

  const files = [
    '/videos/DSC_0412.MOV',
    '/videos/DSC_0413.MOV',
    '/videos/Z5_0007.MOV',
    '/videos/birthday final export.mov',
  ];

  Future<void> addToQueue(WidgetTester tester) async {
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    await tester.pump();
  }

  /// Opens the details of the last video in the list and waits for its
  /// thumbnail, which is decoded outside the test's simulated clock.
  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video details'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
  }

  for (final look in Look.values) {
    // Each image is named after its look: `1_empty_cozy`, `1_empty_pro`.
    Future<void> save(WidgetTester tester, String name) =>
        saveScreenshot(tester, '${name}_${look.name}');

    group(look.name, () {
      testWidgets('empty', (tester) async {
        await pumpApp(tester, environment(), look: look);
        await save(tester, '1_empty');
      });

      testWidgets('videos added', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files);
        await tester.pump();
        await save(tester, '2_videos_added');
      });

      testWidgets('a newer version out', (tester) async {
        final env = environment();
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, files.take(2));
        (env.releases! as FakeReleaseSource).answer('0.4.0');
        await tester.pump();
        await tester.pump();
        await save(tester, '2b_new_version');
      });

      testWidgets('queue with a finished sample', (tester) async {
        final env = environment();
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, files);
        await tester.tap(find.text('DSC_0412.MOV'));
        await tester.pump();
        await tester.tap(find.text('first 10 s'));
        await tester.pump();
        await addToQueue(tester);
        env.executor.last.finish(
          bytes: 2600000,
          elapsed: const Duration(seconds: 6),
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Whole video'));
        await tester.pump();
        await tester.tap(find.text('DSC_0413.MOV'));
        await tester.pump();
        await addToQueue(tester);
        env.executor.last.report(0.42);
        await tester.pump();
        await tester.tap(find.text('Z5_0007.MOV'));
        await tester.pump();
        await addToQueue(tester);
        await save(tester, '3_queue');
      });

      testWidgets('results compared with their originals', (tester) async {
        final env = environment();
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, files.take(3));
        await addToQueue(tester);
        for (final (i, score, vmaf) in [
          (0, 38.7, 92.5),
          (1, 40.6, 96.0),
          (2, 43.2, 98.1),
        ]) {
          env.executor.started[i].finish(
            bytes: 61000000,
            elapsed: const Duration(minutes: 2),
          );
          await tester.pump();
          await tester.pump();
          await tester.tap(find.byTooltip('More').at(3 + i));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Compare with the original'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          env.qualityMeter.last.finish(score, vmaf: vmaf);
          await tester.pump();
        }
        await save(tester, '3b_compared');
      });

      testWidgets('the quality chosen for each video', (tester) async {
        final env = environment();
        for (final (path, outcome) in [
          (files[0], QualityOutcome.standard),
          (files[1], QualityOutcome.raised),
          (files[2], QualityOutcome.belowTarget),
          (files[3], QualityOutcome.notWorthIt),
        ]) {
          env.estimator.choices[path] = fakeChoice(outcome);
        }
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, files);
        await tester.pump();
        await save(tester, '12_quality_list');
      });

      testWidgets('the quality in the queue', (tester) async {
        final env = environment();
        for (final (path, outcome) in [
          (files[0], QualityOutcome.belowTarget),
          (files[1], QualityOutcome.notWorthIt),
          (files[2], QualityOutcome.raised),
        ]) {
          env.estimator.choices[path] = fakeChoice(outcome);
        }
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, files.take(3));
        await tester.pump();
        await addToQueue(tester);
        env.executor.last.finish(
          bytes: 450000000,
          elapsed: const Duration(minutes: 4),
        );
        await tester.pump();
        await tester.pump();
        env.executor.last.report(0.3);
        await tester.pump();
        await save(tester, '12b_quality_queue');
      });

      testWidgets('checking the quality before converting', (tester) async {
        final env = environment();
        env.estimator
          ..choices[files[2]] = fakeChoice(QualityOutcome.raised)
          ..hold = true;
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, [files[2]]);
        await tester.pump();
        await save(tester, '12c_quality_choosing_list');
        await addToQueue(tester);
        await save(tester, '12d_quality_choosing_queue');
      });

      testWidgets('a video to check by eye', (tester) async {
        final env = environment();
        env.estimator.choices[files[2]] = fakeChoice(
          QualityOutcome.belowTarget,
        );
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, [files[2]]);
        await tester.pump();
        await tester.tap(find.byTooltip("About this video's quality"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        // The frames are decoded outside the test's simulated clock.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.pump();
        await save(tester, '12e_quality_dialog');
      });

      testWidgets('why a video stays as it is', (tester) async {
        final env = environment();
        env.estimator.choices[files[3]] = fakeChoice(QualityOutcome.notWorthIt);
        final sources = await pumpApp(tester, env, look: look);
        await addVideos(tester, sources, [files[3]]);
        await tester.pump();
        await tester.tap(find.byTooltip("About this video's quality"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await save(tester, '12f_quality_kept');
      });

      testWidgets('details', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files);
        await openDetails(tester);
        await save(tester, '4_details');
      });

      testWidgets('details, all metadata', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files);
        await openDetails(tester);
        await tester.tap(find.text('All metadata'));
        await tester.pumpAndSettle();
        await save(tester, '4b_details_metadata');
      });

      testWidgets('Ukrainian', (tester) async {
        final env = environment();
        final sources = await pumpApp(
          tester,
          env,
          locale: const Locale('uk'),
          look: look,
        );
        await addVideos(tester, sources, files);
        await tester.tap(find.text('Додати в чергу'));
        await tester.pump();
        await tester.pump();
        env.executor.last.report(0.6);
        await tester.pump();
        await save(tester, '5_ukrainian');
      });

      testWidgets('the sound', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files);
        await tester.tap(find.byIcon(Icons.music_note_rounded));
        await tester.pump();
        await save(tester, '7_sound');
      });

      testWidgets('smallest window, the tallest settings', (tester) async {
        final env = environment();
        final sources = await pumpApp(
          tester,
          env,
          look: look,
          size: minimumWindowSize,
        );
        await addVideos(tester, sources, files.take(2));
        await tester.tap(find.byIcon(Icons.movie_edit));
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();
        await save(tester, '6_smallest_window');
      });

      testWidgets('Resolve, with CamCtrl offered', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files.take(2));
        await tester.tap(find.byIcon(Icons.movie_edit));
        await tester.pump();
        await save(tester, '9_resolve');
      });

      testWidgets('how the archive quality was measured', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files.take(2));
        await tester.tap(find.byIcon(Icons.help_outline_rounded));
        await tester.pumpAndSettle();
        await save(tester, '11_archive_measured');
      });

      testWidgets('how the archive keeps the quality, in Ukrainian', (
        tester,
      ) async {
        final sources = await pumpApp(
          tester,
          environment(),
          look: look,
          locale: const Locale('uk'),
        );
        await addVideos(tester, sources, files.take(2));
        await tester.tap(find.byIcon(Icons.help_outline_rounded));
        await tester.pumpAndSettle();
        await save(tester, '11b_archive_measured_uk');
      });

      testWidgets('Save space, with the limits it sets', (tester) async {
        final sources = await pumpApp(tester, environment(), look: look);
        await addVideos(tester, sources, files.take(2));
        await tester.tap(find.byIcon(Icons.compress_rounded));
        await tester.pump();
        await save(tester, '10_save_space');
      });

      testWidgets('use with an AI agent', (tester) async {
        await pumpApp(tester, environment(), look: look);
        await tester.tap(find.byTooltip('Use with an AI agent'));
        await tester.pumpAndSettle();
        await save(tester, '6_agent');
      });

      testWidgets('use with an AI agent, smallest window, in Ukrainian', (
        tester,
      ) async {
        await pumpApp(
          tester,
          environment(),
          look: look,
          locale: const Locale('uk'),
          size: minimumWindowSize,
        );
        await tester.tap(find.byTooltip('Робота з ШІ-агентом'));
        await tester.pumpAndSettle();
        await save(tester, '6b_agent_smallest_uk');
      });

      testWidgets('use with an AI agent, in a build without the program', (
        tester,
      ) async {
        await pumpApp(tester, environment()..clientPath = null, look: look);
        await tester.tap(find.byTooltip('Use with an AI agent'));
        await tester.pumpAndSettle();
        await save(tester, '6c_agent_missing');
      });

      testWidgets('the about menu', (tester) async {
        await pumpApp(tester, environment(), look: look);
        await tester.tap(find.byTooltip('About VidCtrl'));
        await tester.pumpAndSettle();
        await save(tester, '8_about_menu');
      });
    });
  }
}
