import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/quality/quality_search.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

void main() {
  const archive = QualityRange(standard: 35, best: 20);
  const original = 1000;

  /// A video whose poorest piece scores [vmafAt] and weighs [bytesAt] at each
  /// quality number; records the numbers tried.
  ({Future<QualityChoice?> choice, List<int?> tried}) search({
    required double Function(int crf) vmafAt,
    int Function(int crf)? bytesAt,
    QualityRange? range = archive,
  }) {
    final tried = <int?>[];
    final choice = chooseQuality(
      range: range,
      sourceBytes: original,
      measure: (value) async {
        tried.add(value);
        final crf = value ?? 35;
        return QualityTrial(
          value: value,
          score: QualityScore(40, vmaf: vmafAt(crf)),
          bytes: bytesAt?.call(crf) ?? 200,
        );
      },
    );
    return (choice: choice, tried: tried);
  }

  test(
    'a video that looks the same at the standard quality keeps it',
    () async {
      final (:choice, :tried) = search(vmafAt: (_) => 96.0);

      final chosen = (await choice)!;
      expect(chosen.outcome, QualityOutcome.standard);
      expect(chosen.value, 35);
      expect(tried, [35]);
    },
  );

  test(
    'one that falls short gets the poorest quality that looks the same',
    () async {
      // Two points of VMAF for every three steps of crf: 95 at crf 26.
      final (:choice, :tried) = search(
        vmafAt: (crf) => 101 - (crf - 17) * 2 / 3,
      );

      final chosen = (await choice)!;
      expect(chosen.outcome, QualityOutcome.raised);
      expect(chosen.value, 26);
      expect(chosen.standardValue, 35);
      expect(tried.first, 35);
      expect(tried[1], 20);
      expect(tried.length, lessThanOrEqualTo(maxQualityTrials));
    },
  );

  test('the search never goes below the best quality', () async {
    final (:choice, :tried) = search(vmafAt: (crf) => 92.0 + (35 - crf) / 15);

    final chosen = (await choice)!;
    expect(chosen.outcome, QualityOutcome.belowTarget);
    expect(chosen.value, 20);
    expect(tried, [35, 20]);
  });

  test(
    'a result keeping most of the original is not worth converting',
    () async {
      // A phone video in an efficient format: it looks the same, but would
      // keep nine tenths of its size.
      final (:choice, tried: _) = search(
        vmafAt: (_) => 99.0,
        bytesAt: (_) => 900,
      );

      final chosen = (await choice)!;
      expect(chosen.outcome, QualityOutcome.notWorthIt);
      expect(chosen.converts, isFalse);
      expect(chosen.share, closeTo(0.9, 0.001));
    },
  );

  test('past the limit at the standard quality, nothing is searched', () async {
    // A better quality would only grow a file already too large.
    final (:choice, :tried) = search(
      vmafAt: (crf) => crf < 30 ? 96.0 : 93.0,
      bytesAt: (_) => 850,
    );

    expect((await choice)!.outcome, QualityOutcome.notWorthIt);
    expect(tried, [35]);
  });

  test('an unknown original size never means not worth it', () async {
    final choice = await chooseQuality(
      range: archive,
      sourceBytes: 0,
      measure: (value) async => QualityTrial(
        value: value,
        score: const QualityScore(40, vmaf: 96),
        bytes: 200,
      ),
    );

    expect(choice!.outcome, QualityOutcome.standard);
  });

  test('identical pictures (XPSNR infinity) still narrow the search', () async {
    final choice = await chooseQuality(
      range: archive,
      sourceBytes: original,
      measure: (value) async => QualityTrial(
        value: value,
        score: QualityScore(value! <= 22 ? double.infinity : 41.0),
        bytes: 200,
      ),
    );

    expect(choice!.outcome, QualityOutcome.raised);
    expect(choice.value, 22);
  });

  test('the size limit applies to the quality the search settles on', () async {
    final (:choice, tried: _) = search(
      vmafAt: (crf) => 92.0 + (35 - crf) / 15,
      bytesAt: (crf) => crf <= 20 ? 850 : 200,
    );

    expect((await choice)!.outcome, QualityOutcome.notWorthIt);
  });

  test('up to the limit itself, converting is worth it', () async {
    final (:choice, tried: _) = search(
      vmafAt: (_) => 96.0,
      bytesAt: (_) => 800,
    );

    expect((await choice)!.outcome, QualityOutcome.standard);
  });

  test(
    'converting anyway keeps the quality found and drops the limit',
    () async {
      // Short of the target at crf 35 and too large already: nothing
      // better was tried, so anyway means 35, marked for a look.
      final (:choice, tried: _) = search(
        vmafAt: (crf) => 92.0 + (35 - crf) / 15,
        bytesAt: (_) => 900,
      );

      final anyway = (await choice)!.anyway();
      expect(anyway.outcome, QualityOutcome.belowTarget);
      expect(anyway.value, 35);
    },
  );

  test('without a quality to change, only the verdict is given', () async {
    // A graphics card's encoder.
    final (:choice, :tried) = search(vmafAt: (_) => 92.0, range: null);

    final chosen = (await choice)!;
    expect(chosen.outcome, QualityOutcome.belowTarget);
    expect(chosen.value, isNull);
    expect(tried, [null]);
  });

  test('XPSNR decides where VMAF is not measured', () async {
    final tried = <int?>[];
    final choice = await chooseQuality(
      range: archive,
      sourceBytes: original,
      measure: (value) async {
        tried.add(value);
        // 42 dB, the level of looking the same, at crf 28.
        return QualityTrial(
          value: value,
          score: QualityScore(42 + (28 - value!) * 0.25),
          bytes: 200,
        );
      },
    );

    expect(choice!.outcome, QualityOutcome.raised);
    expect(choice.value, 28);
  });

  test('a failed or stopped measurement chooses nothing', () async {
    var calls = 0;
    final choice = await chooseQuality(
      range: archive,
      sourceBytes: original,
      measure: (value) async => calls++ == 0
          ? QualityTrial(
              value: value,
              score: const QualityScore(38, vmaf: 90),
              bytes: 200,
            )
          : null,
    );

    expect(choice, isNull);
  });

  test('each try is announced before it starts', () async {
    final attempts = <int>[];
    await chooseQuality(
      range: archive,
      sourceBytes: original,
      onAttempt: attempts.add,
      measure: (value) async => QualityTrial(
        value: value,
        score: QualityScore(40, vmaf: value! <= 25 ? 96 : 93),
        bytes: 200,
      ),
    );

    expect(attempts, [for (var i = 1; i <= attempts.length; i++) i]);
    expect(attempts.length, greaterThan(2));
  });

  test('the chosen plan is marked when it falls short', () async {
    final (:choice, tried: _) = search(vmafAt: (_) => 92.0);
    final chosen = (await choice)!;

    final plan = planWithChoice(
      _FakeRaiser(),
      const ConversionPlan(kind: PlanKind.encode, nameSuffix: '_x'),
      chosen,
    );

    expect(plan.nameSuffix, '_x@20$belowTargetMarker');
  });
}

class _FakeRaiser implements RaisesQuality {
  @override
  QualityRange? qualityRange(ConversionPlan plan) =>
      const QualityRange(standard: 35, best: 20);

  @override
  ConversionPlan withQuality(
    ConversionPlan plan,
    int? value, {
    bool belowTarget = false,
  }) => plan.withVideo(
    plan.video,
    nameSuffix:
        '${plan.nameSuffix}@$value${belowTarget ? belowTargetMarker : ''}',
  );
}
