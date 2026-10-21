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

      testWidgets('the about menu', (tester) async {
        await pumpApp(tester, environment(), look: look);
        await tester.tap(find.byTooltip('About VidCtrl'));
        await tester.pumpAndSettle();
        await save(tester, '8_about_menu');
      });
    });
  }
}
