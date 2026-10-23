/// Chooses, for one video, the quality that makes it look the same as its
/// original, judged on short pieces of it (`size_estimator.dart`).
///
/// The archive's standard quality is the poorest it gives anyone; a video
/// whose poorest piece falls short of looking the same gets a better one,
/// up to a best worth its size. The judge is the poorest piece, not the
/// average: an archive is meant to take the original's place, and the one
/// scene that shows a difference is the one a person would notice. A result
/// that would keep most of the original's size is not worth converting.
library;

import '../scenarios/scenario.dart';
import 'quality_meter.dart';

/// Converting is not worth it when the result would keep more than this
/// share of the original's size: the original stays as it is.
const worthItShare = 0.8;

/// The most quality numbers tried for one video, the standard and the best
/// ones included. Each try encodes and compares every piece again.
const maxQualityTrials = 6;

/// A frame of the poorest piece where it differs most from the original, to
/// show a person what to look at.
class HardestFrame {
  const HardestFrame({
    required this.pieceStart,
    required this.pieceLength,
    required this.frame,
    this.encodedPiece,
  });

  /// Where the piece starts in the original.
  final Duration pieceStart;
  final Duration pieceLength;

  /// The frame, counted from the piece's first.
  final int frame;

  /// The piece encoded at the quality tried, kept to be shown before the
  /// whole video is converted. Null once it is no longer kept.
  final String? encodedPiece;
}

/// What converting at one quality number showed on the pieces.
class QualityTrial {
  const QualityTrial({
    required this.value,
    required this.score,
    required this.bytes,
    this.time,
    this.pieces = 0,
    this.hardest,
  });

  /// The quality number; null where the plan has none to change.
  final int? value;

  /// The poorest piece's score.
  final QualityScore score;

  /// The expected size of the whole converted video.
  final int bytes;

  /// The expected conversion time of the whole video.
  final Duration? time;

  /// How many pieces were compared.
  final int pieces;
  final HardestFrame? hardest;

  bool get looksTheSame => score.closeness == Closeness.same;
}

enum QualityOutcome {
  /// The standard quality already looks the same.
  standard,

  /// A better quality than the standard one was needed, and found.
  raised,

  /// Even the best quality tried falls short: converted, but worth a look
  /// before the original is deleted.
  belowTarget,

  /// The result would keep most of the original's size: left as it is.
  notWorthIt,
}

/// The quality chosen for one video, and what led to it.
class QualityChoice {
  const QualityChoice({
    required this.outcome,
    required this.trials,
    required this.chosen,
    required this.sourceBytes,
  });

  final QualityOutcome outcome;

  /// Every quality tried, in order; the standard one first.
  final List<QualityTrial> trials;

  /// What converting uses.
  final QualityTrial chosen;

  /// The original's size.
  final int sourceBytes;

  /// The quality number converting uses; null where there is none to change.
  int? get value => chosen.value;

  /// The plan's own number.
  int? get standardValue => trials.first.value;

  /// The result's expected size as a share of the original's.
  double get share => sourceBytes > 0 ? chosen.bytes / sourceBytes : 1;

  /// Whether the video gets converted.
  bool get converts => outcome != QualityOutcome.notWorthIt;

  /// The choice when the size limit is set aside, as when a person asks to
  /// convert a video that was left as it is.
  QualityChoice anyway() => QualityChoice(
    outcome: _outcomeOf(chosen, trials, sourceBytes, sizeLimit: false),
    trials: trials,
    chosen: chosen,
    sourceBytes: sourceBytes,
  );
}

QualityOutcome _outcomeOf(
  QualityTrial chosen,
  List<QualityTrial> trials,
  int sourceBytes, {
  required bool sizeLimit,
}) {
  // An unknown size (0) says nothing against converting.
  if (sizeLimit &&
      sourceBytes > 0 &&
      chosen.bytes > sourceBytes * worthItShare) {
    return QualityOutcome.notWorthIt;
  }
  if (!chosen.looksTheSame) return QualityOutcome.belowTarget;
  return identical(chosen, trials.first)
      ? QualityOutcome.standard
      : QualityOutcome.raised;
}

/// [plan] as converting with [choice] runs it: at the chosen quality, its
/// name marked when the result needs a look.
ConversionPlan planWithChoice(
  RaisesQuality preset,
  ConversionPlan plan,
  QualityChoice choice,
) => preset.withQuality(
  plan,
  choice.value,
  belowTarget: !choice.chosen.looksTheSame,
);

/// Tries quality numbers from [range]'s standard one down to its best, with
/// [measure], and settles on the poorest (smallest) that looks the same.
/// Without a [range] only the plan's own quality is measured. Null when a
/// measurement failed or was stopped.
///
/// After the standard number, the best one is tried: if even it falls short
/// there is nothing to search. Otherwise the numbers between are narrowed
/// down, each guess placed where the scores of the two nearest tries say
/// the target lies, so two or three more tries usually do.
/// [onAttempt] is told the number of each try before it starts, from 1.
Future<QualityChoice?> chooseQuality({
  required QualityRange? range,
  required int sourceBytes,
  required Future<QualityTrial?> Function(int? value) measure,
  void Function(int attempt)? onAttempt,
}) async {
  final trials = <QualityTrial>[];
  Future<QualityTrial?> attempt(int? value) async {
    onAttempt?.call(trials.length + 1);
    final trial = await measure(value);
    if (trial != null) trials.add(trial);
    return trial;
  }

  QualityChoice decide(QualityTrial chosen) => QualityChoice(
    outcome: _outcomeOf(chosen, trials, sourceBytes, sizeLimit: true),
    trials: List.unmodifiable(trials),
    chosen: chosen,
    sourceBytes: sourceBytes,
  );

  final standard = await attempt(range?.standard);
  if (standard == null) return null;
  // A better quality only makes the file larger: past the limit already,
  // there is nothing to search.
  final pastLimit =
      sourceBytes > 0 && standard.bytes > sourceBytes * worthItShare;
  if (standard.looksTheSame ||
      pastLimit ||
      range == null ||
      range.best >= range.standard) {
    return decide(standard);
  }
  final best = await attempt(range.best);
  if (best == null) return null;
  if (!best.looksTheSame) return decide(best);

  var passing = best;
  var failing = standard;
  while (failing.value! - passing.value! > 1 &&
      trials.length < maxQualityTrials) {
    final trial = await attempt(_between(passing, failing));
    if (trial == null) return null;
    if (trial.looksTheSame) {
      passing = trial;
    } else {
      failing = trial;
    }
  }
  return decide(passing);
}

/// The next number to try between a [passing] and a [failing] one: where
/// the line through their scores meets the target, rounded towards the
/// passing side, and always strictly between the two.
int _between(QualityTrial passing, QualityTrial failing) {
  final low = passing.value!;
  final high = failing.value!;
  final byVmaf = passing.score.vmaf != null && failing.score.vmaf != null;
  double score(QualityTrial t) => byVmaf ? t.score.vmaf! : t.score.lumaDb;
  final target = byVmaf ? sameAsOriginalVmaf : sameAsOriginalDb;
  final atLow = score(passing);
  final atHigh = score(failing);
  // Identical pictures score XPSNR infinity, which gives no line.
  final guess = atLow > atHigh && atLow.isFinite && atHigh.isFinite
      ? low + (high - low) * (atLow - target) / (atLow - atHigh)
      : (low + high) / 2;
  return guess.floor().clamp(low + 1, high - 1);
}
