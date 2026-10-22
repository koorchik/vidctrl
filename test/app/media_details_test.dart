import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/media/ffprobe.dart';

import '../support/fakes.dart';
import '../support/pump_app.dart';

/// The tags mkvmerge gives every track: long names, as in most MKV files.
const mkvTags = {
  'language': 'ukr',
  'title': 'Dubbed',
  'BPS': '192000',
  'DURATION': '02:36:22.336000000',
  'NUMBER_OF_FRAMES': '293198',
  'NUMBER_OF_BYTES': '225176064',
  '_STATISTICS_WRITING_APP': "mkvmerge v87.0 ('Black as the Sky') 64-bit",
  '_STATISTICS_WRITING_DATE_UTC': '2026-05-10 08:13:58',
  '_STATISTICS_TAGS': 'BPS DURATION NUMBER_OF_FRAMES NUMBER_OF_BYTES',
};

void main() {
  setUpAll(loadRealFonts);

  testWidgets('long tag names leave their values room to read', (tester) async {
    final report = jsonDecode(
      File('test/fixtures/hlg_clip_ffprobe.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final stream in report['streams'] as List) {
      (stream as Map<String, dynamic>)['tags'] = {...mkvTags};
    }
    final env = FakeEnvironment();
    env.ffprobe.add(
      '/videos/film.mkv',
      like: parseFfprobeJson('/videos/film.mkv', report),
    );
    final sources = await pumpApp(tester, env);
    await addVideos(tester, sources, ['/videos/film.mkv']);

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All metadata'));
    await tester.pumpAndSettle();

    // A line of a value is about 20 pixels high.
    const lineHeight = 22.0;
    for (final MapEntry(:key, :value) in mkvTags.entries) {
      for (final element in find.text(key).evaluate()) {
        final name = element.renderObject! as RenderParagraph;
        expect(name.didExceedMaxLines, isFalse, reason: '$key is cut off');
      }
      // Broken between words if at all, never inside one.
      final words = value.split(' ').length;
      for (final size in find.text(value).evaluate().map((e) => e.size!)) {
        expect(size.height, lessThan(lineHeight * words), reason: value);
      }
    }
  });
}
