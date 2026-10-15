import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvv_videoconvertor/app/app.dart';
import 'package:tvv_videoconvertor/app/home/size_change_text.dart';
import 'package:tvv_videoconvertor/app/home/technical_text.dart';
import 'package:tvv_videoconvertor/app/providers.dart';
import 'package:tvv_videoconvertor/app/window.dart';
import 'package:tvv_videoconvertor/core/ffmpeg/capabilities.dart';
import 'package:tvv_videoconvertor/core/media/ffprobe.dart';
import 'package:tvv_videoconvertor/core/settings/settings_store.dart';

import '../support/fake_media.dart';
import '../support/fakes.dart';
import '../support/pump_app.dart';

/// Words a non-technical person should never have to read as a main label.
/// They may appear as secondary technical notes (`TechnicalText`).
const jargon = [
  'H.264',
  'H.265',
  'HEVC',
  'AV1',
  'AAC',
  'PCM',
  'ProRes',
  'DNxHR',
  'CRF',
  'codec',
  'bitrate',
  '10-bit',
  'FFmpeg',
  'remux',
  'MOV',
  'MP4',
];

/// Fails when any of [seen] uses one of the [jargon] words.
void expectNoJargon(List<String> seen) {
  for (final term in jargon) {
    final word = RegExp(
      '(?<![A-Za-z0-9])${RegExp.escape(term)}(?![A-Za-z0-9])',
      caseSensitive: false,
    );
    expect(
      seen.where(word.hasMatch),
      isEmpty,
      reason: '"$term" should not be a main label',
    );
  }
}

void main() {
  late FakeEnvironment env;

  setUp(() {
    env = FakeEnvironment();
    env.ffprobe.add('/videos/holiday.mp4');
    env.ffprobe.add('/videos/second.mp4');
    env.ffprobe.add(
      '/videos/nikon.mov',
      like: clip(video: 'hevc', audio: [track('pcm_s24le')]),
    );
  });

  ButtonStyleButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );

  Future<void> addToQueue(WidgetTester tester) async {
    await tester.tap(find.text('Add to queue'));
    await tester.pump();
    await tester.pump();
  }

  group('the simple path', () {
    testWidgets('an empty window invites dropping videos', (tester) async {
      await pumpApp(tester, env);

      expect(find.text('Drop videos or folders here'), findsOneWidget);
      expect(
        find.textContaining('Converting starts by itself'),
        findsOneWidget,
      );
      expect(button(tester, 'Add to queue').onPressed, isNull);
    });

    testWidgets('drop, then Add to queue: converting starts by itself', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);

      expect(find.text('1 selected'), findsOneWidget);
      await addToQueue(tester);

      expect(env.executor.started, hasLength(1));
      expect(find.textContaining('Starting…'), findsOneWidget);
      expect(find.textContaining('→ holiday_av1-crf24.mp4'), findsOneWidget);
    });

    testWidgets('each selected video previews what will happen to it', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, [
        '/videos/holiday.mp4',
        '/videos/nikon.mov',
      ]);

      await tester.tap(find.text('Edit in DaVinci Resolve'));
      await tester.pump();

      expect(
        find.textContaining('Quick, the picture stays untouched'),
        findsOneWidget,
      );
      expect(find.textContaining('Ready as is'), findsOneWidget);
    });

    testWidgets('warnings about a video are shown under it', (tester) async {
      env.ffprobe.add(
        '/videos/phone.mp4',
        like: clip(fps: 27.4, nominalFps: 30),
      );
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/phone.mp4']);

      await tester.tap(find.text('Edit in DaVinci Resolve'));
      await tester.pump();

      expect(find.text('Uneven frame timing will be fixed.'), findsOneWidget);
    });

    testWidgets('the expected size is shown per video and for the selection', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await tester.pump();

      expect(
        find.textContaining('Will be converted  → about 150 MB'),
        findsOneWidget,
      );
      expect(
        find.text(
          '1 video  ·  750 MB → about 150 MB  ·  80% smaller  ·  '
          'takes about 1 min',
        ),
        findsOneWidget,
      );
    });
  });

  group('the queue', () {
    testWidgets('Add all appears only while some videos are unselected', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, [
        '/videos/holiday.mp4',
        '/videos/second.mp4',
      ]);
      expect(find.text('Add all (2)'), findsNothing);

      await tester.tap(find.text('second.mp4'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('Add all (2)'));
      await tester.pump();

      expect(find.textContaining('holiday_av1-crf24.mp4'), findsOneWidget);
      expect(find.textContaining('second_av1-crf24.mp4'), findsOneWidget);
    });

    testWidgets('one video, two settings: two jobs with different names', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await addToQueue(tester);

      await tester.tap(find.text('Works everywhere'));
      await tester.pump();
      await addToQueue(tester);

      expect(find.textContaining('holiday_av1-crf24.mp4'), findsOneWidget);
      expect(find.textContaining('holiday_hevc-crf21.mp4'), findsOneWidget);
      // Each job says what was changed, in the words of the panel.
      expect(
        find.text('For the archive · Format: Works everywhere'),
        findsOneWidget,
      );
    });

    testWidgets('a job lists every option that was chosen for it', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await tester.tap(find.text('Edit in DaVinci Resolve'));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Smaller'));
      await tester.pump();

      await addToQueue(tester);

      expect(
        find.text(
          'Edit in DaVinci Resolve · Resolve Studio · '
          'Also convert the picture · File size: Smaller',
        ),
        findsOneWidget,
      );
    });

    testWidgets('pressing Add again with the same settings changes nothing', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await addToQueue(tester);

      expect(find.text('Already in the queue'), findsOneWidget);
      expect(button(tester, 'Add to queue').onPressed, isNull);
    });

    testWidgets('a sample shows its own size and the whole video\'s', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await tester.tap(find.text('first 10 s'));
      await tester.pump();
      expect(find.text('1 sample of 10 seconds'), findsOneWidget);

      await addToQueue(tester);
      env.executor.last.finish(
        bytes: 5000000,
        elapsed: const Duration(seconds: 4),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Sample 5.0 MB · whole video about 30.0 MB, about 24 s'),
        findsOneWidget,
      );
      expect(find.text('Convert whole video'), findsOneWidget);
    });

    testWidgets('a finished job reports the saving', (tester) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await addToQueue(tester);

      env.executor.last.finish(bytes: 150000000);
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('750 MB → 150 MB  ·  80% smaller'),
        findsOneWidget,
      );
      expect(find.textContaining('All done'), findsOneWidget);
    });
  });

  group('details', () {
    testWidgets('video details: encoding, all metadata and the full report', (
      tester,
    ) async {
      final report = jsonDecode(
        File('test/fixtures/hlg_clip_ffprobe.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      env.ffprobe.add(
        '/videos/hlg.mov',
        like: parseFfprobeJson('/videos/hlg.mov', report),
      );
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/hlg.mov']);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Video details'));
      await tester.pumpAndSettle();

      expect(find.text('Video track 1'), findsOneWidget);
      // Among the key facts at the top, and in the picture track's card.
      expect(find.text('HLG'), findsNWidgets(2));
      expect(find.text('Timecode'), findsWidgets);

      await tester.tap(find.text('All metadata'));
      await tester.pumpAndSettle();
      expect(find.text('Example Camera Co'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, contains('make: Example Camera Co'));

      await tester.tap(find.text('Full report'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"codec_name": "hevc"'), findsOneWidget);
    });

    testWidgets('details of the result are offered once a job is done', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await addToQueue(tester);

      // A running job's progress bar animates forever, so the menu is
      // given a fixed time to open and close instead of "until settled".
      Future<void> wait() => tester.pump(const Duration(milliseconds: 500));
      Future<bool> offered() async {
        await tester.tap(find.byTooltip('More').last);
        await tester.pump();
        await wait();
        final found = find.text('Details of the result').evaluate().isNotEmpty;
        await tester.tapAt(Offset.zero);
        await tester.pump();
        await wait();
        return found;
      }

      expect(await offered(), isFalse);
      env.executor.last.finish();
      await tester.pump();
      expect(await offered(), isTrue);
    });

    testWidgets('extra options open in a small window of their own', (
      tester,
    ) async {
      await pumpApp(tester, env);
      await tester.tap(find.text('Edit in DaVinci Resolve'));
      await tester.pump();
      await tester.tap(find.text('Free Resolve'));
      await tester.pump();
      expect(find.text('DNxHR'), findsNothing);

      await tester.tap(find.text('More options…'));
      await tester.pumpAndSettle();

      expect(find.text('DNxHR'), findsOneWidget);
    });

    group('the archive', () {
      testWidgets('says on the panel what each format trades away', (
        tester,
      ) async {
        await pumpApp(tester, env);
        expect(find.text('More options…'), findsNothing);
        expect(find.textContaining('iPhone 15 Pro'), findsOneWidget);

        await tester.tap(find.text('Works everywhere'));
        await tester.pump();

        expect(find.textContaining('iPhone 15 Pro'), findsNothing);
        expect(find.textContaining('up to a third larger'), findsOneWidget);
      });

      testWidgets('offers the graphics card only where one works', (
        tester,
      ) async {
        await pumpApp(tester, env);
        expect(find.text('Fast'), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await pumpApp(
          tester,
          FakeEnvironment(capabilities: withGpu({'av1_nvenc'})),
        );
        expect(find.text('Fast'), findsOneWidget);
        expect(find.widgetWithText(TechnicalText, 'NVIDIA'), findsOneWidget);

        // This card makes no HEVC, so with HEVC there is no choice left.
        await tester.tap(find.text('Works everywhere'));
        await tester.pump();
        expect(find.text('Fast'), findsNothing);
      });

      testWidgets('without AV1 in this FFmpeg, there is nothing to choose', (
        tester,
      ) async {
        await pumpApp(
          tester,
          FakeEnvironment(
            capabilities: const Capabilities(
              ffmpegVersion: 'test',
              encoders: {'libx265', 'libx264', 'aac'},
            ),
          ),
        );

        expect(find.text('Smallest file'), findsNothing);
        expect(
          find.widgetWithText(
            TechnicalText,
            'HEVC 10-bit, CRF 21 · sound copied as is · MP4',
          ),
          findsOneWidget,
        );
      });

      for (final locale in const [Locale('en'), Locale('uk')]) {
        testWidgets('its choices name no technical terms '
            '(${locale.languageCode})', (tester) async {
          await pumpApp(
            tester,
            FakeEnvironment(capabilities: withGpu({'av1_nvenc'})),
            locale: locale,
          );

          expectNoJargon(plainTexts(tester));
        });
      }
    });

    testWidgets('the technical line tells what happens to the sound', (
      tester,
    ) async {
      env.ffprobe.add(
        '/videos/export.mov',
        like: clip(audio: [track('flac', bitRate: 1400000)]),
      );
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/export.mov']);

      expect(
        find.widgetWithText(
          TechnicalText,
          'AV1 10-bit, CRF 24 · AAC 320k · MP4',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the format is named beside each plain choice', (tester) async {
      await pumpApp(tester, env);
      expect(
        find.widgetWithText(
          TechnicalText,
          'AV1 10-bit, CRF 24 · sound copied as is · MP4',
        ),
        findsOneWidget,
      );

      expect(find.widgetWithText(TechnicalText, 'AV1'), findsOneWidget);
      expect(find.widgetWithText(TechnicalText, 'HEVC'), findsOneWidget);
    });

    testWidgets('the sound file types name the sound they hold', (
      tester,
    ) async {
      await pumpApp(tester, env);
      await tester.tap(find.text('Get the sound'));
      await tester.pump();

      expect(find.widgetWithText(TechnicalText, 'AAC'), findsOneWidget);
      expect(find.widgetWithText(TechnicalText, 'PCM'), findsOneWidget);
    });

    testWidgets('a result larger than its original says so in another colour', (
      tester,
    ) async {
      final sources = await pumpApp(tester, env);
      await addVideos(tester, sources, ['/videos/holiday.mp4']);
      await addToQueue(tester);
      // The original is 750 MB.
      env.executor.last.finish(bytes: 900000000);
      await tester.pump();
      await tester.pump();

      // In the job's line and in the queue's headline.
      final lines = tester.widgetList<RichText>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is SizeChangeText && w.larger == '20% larger',
          ),
          matching: find.byType(RichText),
        ),
      );
      expect(lines, hasLength(2));
      for (final line in lines) {
        TextSpan? phrase;
        line.text.visitChildren((span) {
          if (span is TextSpan && span.text == '20% larger') phrase = span;
          return phrase == null;
        });
        expect(phrase?.style?.color, isNotNull);
        expect(phrase?.style?.color, isNot(line.text.style?.color));
      }
    });
  });

  for (final locale in const [Locale('en'), Locale('uk')]) {
    testWidgets(
      'technical terms appear only as secondary detail (${locale.languageCode})',
      (tester) async {
        final sources = await pumpApp(tester, env, locale: locale);
        await addVideos(tester, sources, [
          '/videos/holiday.mp4',
          '/videos/nikon.mov',
        ]);
        await tester.tap(find.byIcon(Icons.movie_edit));
        await tester.pump();
        await tester.tap(find.byType(FilledButton).last);
        await tester.pump();

        expectNoJargon(
          plainTexts(tester)
            // File names are the user's own and may look like anything.
            ..removeWhere((t) => t.startsWith(RegExp(r'(holiday|nikon)\.'))),
        );
      },
    );
  }

  testWidgets('the two buttons of the empty screen are the same height', (
    tester,
  ) async {
    await pumpApp(tester, env);
    double height(String label) => tester
        .getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .height;

    expect(height('Add videos'), height('Add folder'));
  });

  testWidgets('the language can be switched and is remembered', (tester) async {
    final settings = MemorySettingsStore();
    await pumpApp(tester, env, locale: null, settings: settings);
    expect(find.text('Add to queue'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.translate_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Українська'));
    await tester.pumpAndSettle();
    expect(find.text('Додати в чергу'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, FakeEnvironment(), locale: null, settings: settings);
    expect(find.text('Додати в чергу'), findsOneWidget);
  });

  testWidgets('the menus in the corner of the window open inside it', (
    tester,
  ) async {
    await pumpApp(tester, env, size: minimumWindowSize);
    final window = Offset.zero & minimumWindowSize;

    Future<void> expectInside(Finder button, String choice) async {
      await tester.tap(button);
      await tester.pumpAndSettle();
      final item = tester.getRect(
        find.ancestor(
          of: find.text(choice),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      // Clear of the edge, not merely on screen: a menu touching the edge
      // has its side and shadow cut off.
      expect(window.deflate(8).contains(item.topLeft), isTrue);
      expect(window.deflate(8).contains(item.bottomRight), isTrue);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }

    await expectInside(
      find.byIcon(Icons.translate_rounded),
      'Same as the computer',
    );
    await expectInside(find.byTooltip('Look'), 'Professional');
  });

  testWidgets('the look can be switched and is remembered', (tester) async {
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;

    final settings = MemorySettingsStore();
    await pumpApp(tester, env, settings: settings);
    expect(brightness(), Brightness.light);
    expect(find.text('What to do'), findsOneWidget);

    await tester.tap(find.byTooltip('Look'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professional'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    // Pane titles are in capitals in the professional look.
    expect(find.text('WHAT TO DO'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, FakeEnvironment(), settings: settings);
    expect(brightness(), Brightness.dark);
  });

  testWidgets('a missing video engine is explained', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentProvider.overrideWith(
            (ref) async => throw const FfmpegMissing(),
          ),
        ],
        child: const VideoConverterApp(locale: Locale('en')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The video engine is missing'), findsOneWidget);
  });
}
