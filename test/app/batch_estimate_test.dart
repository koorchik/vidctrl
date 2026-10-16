import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/home/widgets/recipe_pane.dart';
import 'package:vidctrl/app/sources/preview_controller.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/estimate/size_estimator.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import '../support/fake_media.dart';

void main() {
  SourceVideo video(int id, {Duration length = const Duration(minutes: 1)}) =>
      SourceVideo(
        id: id,
        path: '/videos/$id.mp4',
        status: SourceStatus.ready,
        info: clip(duration: length),
      );

  Preview preview(int bytes, {Duration? time}) => Preview(
    plan: const ConversionPlan(
      kind: PlanKind.encode,
      video: VideoEncode(encoder: 'prores_ks', pixFmt: 'yuv422p10le'),
    ),
    estimate: OutputEstimate(bytes: bytes, time: time),
  );

  test('sizes are added up', () {
    final batch = batchEstimate(
      [video(1), video(2)],
      {1: preview(100000000), 2: preview(200000000)},
    )!;

    expect(batch.before, 1500000000);
    expect(batch.after, 300000000);
  });

  test('editing formats many times larger than the source add up too', () {
    // ProRes of two 4K clips: tens of gigabytes. Multiplying byte counts
    // together would overflow.
    final batch = batchEstimate(
      [video(1), video(2)],
      {1: preview(3700000000), 2: preview(15500000000)},
    )!;

    expect(batch.after, 19200000000);
  });

  test('videos not measured yet are assumed to shrink like the others', () {
    final batch = batchEstimate([video(1), video(2)], {1: preview(150000000)})!;

    // One of two equal videos is known to come out at a fifth.
    expect(batch.after, 300000000);
  });

  test('time scales with the length still unmeasured', () {
    final batch = batchEstimate(
      [video(1), video(2, length: const Duration(minutes: 3))],
      {
        1: preview(1, time: const Duration(minutes: 2)),
        2: const Preview(
          plan: ConversionPlan(
            kind: PlanKind.encode,
            video: VideoEncode(encoder: 'libx265', pixFmt: 'yuv420p10le'),
          ),
        ),
      },
    )!;

    // One minute of video took two; four minutes take eight.
    expect(batch.time, const Duration(minutes: 8));
  });

  test('nothing is claimed before anything is known', () {
    expect(batchEstimate([video(1)], const {}), isNull);
  });
}
