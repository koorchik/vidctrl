/// Predicts how large a converted file will be, and how long it will take,
/// before converting it.
///
/// Copies and fixed-rate formats can be worked out from the source. A
/// quality-targeted encode cannot: its size depends on the footage (grain,
/// motion, detail). For those a few short pieces of the video are encoded
/// with the exact settings and the result is scaled up to the whole length.
/// Each piece is also compared with the same piece of the original, so how
/// close the result will look is known before converting too.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../ffmpeg/command_builder.dart';
import '../ffmpeg/runner.dart';
import '../media/media_info.dart';
import '../quality/quality_meter.dart';
import '../quality/quality_search.dart';
import '../scenarios/blocks.dart';
import '../scenarios/scenario.dart';

class OutputEstimate {
  const OutputEstimate({
    required this.bytes,
    this.time,
    this.measured = false,
    this.quality,
    this.choice,
  });

  final int bytes;

  /// Expected conversion time. Null where it is negligible or unknown.
  final Duration? time;

  /// Measured by encoding samples, as opposed to calculated.
  final bool measured;

  /// How close the picture will come to the original: the poorest of the
  /// samples. Null where it was not measured.
  final QualityScore? quality;

  /// The quality chosen for this video, where the goal raises it when needed.
  final QualityChoice? choice;
}

/// The size of the output when it can be calculated without encoding
/// anything: copied streams, fixed-rate formats, sound. Null for a
/// quality-targeted picture encode.
OutputEstimate? estimateWithoutEncoding(MediaInfo info, ConversionPlan plan) {
  if (!plan.producesOutput) return null;
  final fixed = plan.estimatedBytes;
  if (fixed != null) return OutputEstimate(bytes: fixed);
  final videoBytes = switch (plan.video) {
    VideoCopy() => sourceVideoBytes(info),
    VideoNone() => 0,
    VideoEncode() => null,
  };
  if (videoBytes == null) return null;
  return OutputEstimate(bytes: videoBytes + audioOutputBytes(info, plan));
}

/// Bytes the sound will take in the output. Sound is predictable: copied
/// tracks keep their size, encoders are given a bitrate.
int audioOutputBytes(MediaInfo info, ConversionPlan plan) {
  final tracks = plan.firstAudioOnly ? info.audio.take(1) : info.audio;
  final seconds = info.duration.inMicroseconds / 1e6;
  final audio = plan.audio;
  var bitsPerSecond = 0;
  for (final track in tracks) {
    bitsPerSecond += switch (audio) {
      AudioNone() => 0,
      AudioCopy() => track.bitRate ?? 0,
      AudioEncode() => _encodedBitRate(audio, track),
    };
  }
  return (bitsPerSecond * seconds / 8).round();
}

int _encodedBitRate(AudioEncode audio, AudioStream track) {
  final codec = audio.codec;
  if (codec.startsWith('pcm_')) {
    final bits = int.tryParse(RegExp(r'\d+').stringMatch(codec) ?? '') ?? 16;
    return track.sampleRate * track.channels * bits;
  }
  // FLAC typically halves 24-bit PCM.
  if (codec == 'flac') return track.sampleRate * track.channels * 12;
  final index = audio.args.indexOf('-b:a');
  if (index >= 0 && index + 1 < audio.args.length) {
    final value = audio.args[index + 1];
    final number = int.tryParse(value.replaceAll(RegExp(r'[kK]$'), ''));
    if (number != null) {
      return value.toLowerCase().endsWith('k') ? number * 1000 : number;
    }
  }
  // Variable-bitrate MP3 at quality 2 averages about 190 kbit/s.
  if (codec == 'libmp3lame') return 190000;
  return 160000;
}

/// Where to take the pieces that are encoded to measure a video.
///
/// Pieces are spread over the whole length, because the opening seconds are
/// often unrepresentative (a static title, a black frame). A short video is
/// encoded completely, which makes its estimate exact.
List<SampleRange> estimationSamples(Duration duration) {
  const length = Duration(seconds: 3);
  if (duration <= Duration.zero) return const [];
  if (duration <= length * 2) return [SampleRange(length: duration)];
  final count = duration < const Duration(seconds: 30)
      ? 1
      : duration < const Duration(minutes: 2)
      ? 2
      : (3 + duration.inMinutes ~/ 15).clamp(3, 6);
  final latestStart = duration - length;
  return [
    for (var i = 0; i < count; i++)
      SampleRange(
        start: _clamp(
          duration * ((i + 0.5) / count) - length * 0.5,
          latestStart,
        ),
        length: length,
      ),
  ];
}

Duration _clamp(Duration value, Duration max) =>
    value < Duration.zero ? Duration.zero : (value > max ? max : value);

/// Scales what the samples produced up to the whole video.
OutputEstimate extrapolateSamples({
  required MediaInfo info,
  required ConversionPlan plan,
  required int sampleBytes,
  required Duration sampled,
  required Duration spent,
  QualityScore? quality,
}) {
  final scale = info.duration.inMicroseconds / sampled.inMicroseconds;
  return OutputEstimate(
    bytes: (sampleBytes * scale).round() + audioOutputBytes(info, plan),
    time: spent * scale,
    measured: true,
    quality: quality,
  );
}

abstract interface class OutputEstimator {
  /// Null when the estimate could not be made or was cancelled.
  ///
  /// With [raise], a plan whose standard quality falls short of looking the
  /// same is measured again at better ones (`quality_search.dart`), and the
  /// estimate carries the choice. [onAttempt] is told each try, from 1 (the
  /// standard quality) on.
  Future<OutputEstimate?> estimate(
    MediaInfo info,
    ConversionPlan plan, {
    RaisesQuality? raise,
    void Function(int attempt)? onAttempt,
  });

  /// Stops every estimate in progress. Completes once they have ended: FFmpeg
  /// has exited and nothing it wrote is left.
  Future<void> cancelAll();

  /// Deletes the pieces kept to show the hardest frames, as the app leaves.
  Future<void> discardKept();
}

/// Measures quality-targeted encodes by encoding samples with FFmpeg, and
/// with [compare], how close each comes to the original (with [vmaf], VMAF
/// too; the FFmpeg needs the `xpsnr` and `libvmaf` filters).
class SampleEstimator implements OutputEstimator {
  SampleEstimator(
    this._runner, {
    Directory? workDir,
    this.compare = false,
    this.vmaf = false,
  }) : _workDir =
           workDir ??
           Directory(
             p.join(Directory.systemTemp.path, 'vidctrl_estimates_$pid'),
           );

  final FfmpegRunner _runner;
  final Directory _workDir;
  final bool compare;
  final bool vmaf;
  final _running = <FfmpegRun>{};

  /// Estimates under way, so that [cancelAll] can wait for them to end.
  final _measuring = <Future<OutputEstimate?>>{};

  /// Encoded pieces kept to show a video's hardest frame.
  final _kept = <String>{};
  var _generation = 0;
  var _counter = 0;

  @override
  Future<OutputEstimate?> estimate(
    MediaInfo info,
    ConversionPlan plan, {
    RaisesQuality? raise,
    void Function(int attempt)? onAttempt,
  }) async {
    final measuring = _measure(info, plan, raise, onAttempt);
    _measuring.add(measuring);
    try {
      return await measuring;
    } finally {
      _measuring.remove(measuring);
    }
  }

  Future<OutputEstimate?> _measure(
    MediaInfo info,
    ConversionPlan plan,
    RaisesQuality? raise,
    void Function(int attempt)? onAttempt,
  ) async {
    final calculated = estimateWithoutEncoding(info, plan);
    if (calculated != null) return calculated;
    if (plan.video is! VideoEncode) return null;
    final samples = estimationSamples(info.duration);
    if (samples.isEmpty) return null;

    final generation = _generation;
    await _workDir.create(recursive: true);
    final comparable = compare && canComparePlan(plan);

    if (raise == null || !comparable) {
      final trial = await _trial(info, plan, samples, generation, comparable);
      if (trial == null) return null;
      return OutputEstimate(
        bytes: trial.bytes,
        time: trial.time,
        measured: true,
        quality: trial.score,
      );
    }

    // The first try, kept in case its pieces could not be compared: the
    // size is known all the same.
    _Trial? first;
    // The pieces each try kept; estimates run side by side, so each deletes
    // only its own.
    final pieces = <String>[];
    QualityChoice? choice;
    // The piece kept to show the hardest frame, if any.
    String? shown;
    try {
      choice = await chooseQuality(
        range: raise.qualityRange(plan),
        sourceBytes: info.sizeBytes,
        onAttempt: onAttempt,
        measure: (value) async {
          final trial = await _trial(
            info,
            raise.withQuality(plan, value),
            samples,
            generation,
            true,
            keepHardest: true,
          );
          first ??= trial;
          if (trial?.hardest?.encodedPiece case final piece?) pieces.add(piece);
          final score = trial?.score;
          if (trial == null || score == null) return null;
          return QualityTrial(
            value: value,
            score: score,
            bytes: trial.bytes,
            time: trial.time,
            pieces: samples.length,
            hardest: trial.hardest,
          );
        },
      );
    } finally {
      // Only a result that falls short has its frame shown, from the
      // chosen quality's piece, and only while this estimate still counts.
      shown =
          choice?.outcome == QualityOutcome.belowTarget &&
              generation == _generation
          ? choice?.chosen.hardest?.encodedPiece
          : null;
      for (final path in pieces) {
        if (path != shown) await _delete(path);
      }
    }
    if (choice == null || generation != _generation) {
      final measured = first;
      if (generation != _generation || measured == null) return null;
      return OutputEstimate(
        bytes: measured.bytes,
        time: measured.time,
        measured: true,
      );
    }
    return OutputEstimate(
      bytes: choice.chosen.bytes,
      time: choice.chosen.time,
      measured: true,
      quality: choice.chosen.score,
      choice: shown == null ? _withoutPieces(choice) : choice,
    );
  }

  /// [choice] without the pieces it named, which are deleted.
  QualityChoice _withoutPieces(QualityChoice choice) {
    QualityTrial strip(QualityTrial trial) {
      final hardest = trial.hardest;
      return QualityTrial(
        value: trial.value,
        score: trial.score,
        bytes: trial.bytes,
        time: trial.time,
        pieces: trial.pieces,
        hardest: hardest == null
            ? null
            : HardestFrame(
                pieceStart: hardest.pieceStart,
                pieceLength: hardest.pieceLength,
                frame: hardest.frame,
              ),
      );
    }

    final trials = [for (final trial in choice.trials) strip(trial)];
    return QualityChoice(
      outcome: choice.outcome,
      trials: trials,
      chosen: trials[choice.trials.indexOf(choice.chosen)],
      sourceBytes: choice.sourceBytes,
    );
  }

  /// Encodes [samples] with [plan] and, when [comparable], compares each with
  /// the same piece of the original. With [keepHardest], the encoded piece
  /// that came out poorest is kept, to show its hardest frame. Null when an
  /// encode failed or was stopped.
  Future<_Trial?> _trial(
    MediaInfo info,
    ConversionPlan plan,
    List<SampleRange> samples,
    int generation,
    bool comparable, {
    bool keepHardest = false,
  }) async {
    // The sound is calculated, so only the picture is encoded.
    final pictureOnly = plan.withAudio(const AudioNone());
    var bytes = 0;
    var sampled = Duration.zero;
    final scores = <QualityScore?>[];
    ({double score, HardestFrame frame})? poorest;
    final stopwatch = Stopwatch()..start();
    var finished = false;
    try {
      for (final sample in samples) {
        final output = File(
          p.join(_workDir.path, 'sample_${_counter++}.${plan.extension}'),
        );
        final run = await _runner.start(
          buildFfmpegArgs(
            input: info.path,
            output: output.path,
            plan: pictureOnly,
            sample: sample,
          ),
        );
        _running.add(run);
        // Stopped while this sample was starting.
        if (generation != _generation) unawaited(run.cancel());
        final result = await run.result;
        _running.remove(run);
        var kept = false;
        try {
          if (generation != _generation) return null;
          if (result.status != RunStatus.completed) return null;
          if (!await output.exists()) return null;
          bytes += await output.length();
          if (comparable) {
            // Comparing is not part of converting: kept out of the time.
            stopwatch.stop();
            final compared = await _compare(
              info,
              output.path,
              sample,
              generation,
            );
            stopwatch.start();
            if (generation != _generation) return null;
            scores.add(compared?.score);
            final frame = compared?.hardest;
            if (keepHardest &&
                frame != null &&
                (poorest == null || frame.score < poorest.score)) {
              if (poorest?.frame.encodedPiece case final previous?) {
                await _delete(previous);
              }
              poorest = (
                score: frame.score,
                frame: HardestFrame(
                  pieceStart: sample.start,
                  pieceLength: sample.length,
                  frame: frame.index,
                  encodedPiece: output.path,
                ),
              );
              _kept.add(output.path);
              kept = true;
            }
          }
        } finally {
          if (!kept && await output.exists()) await output.delete();
        }
        final end = sample.start + sample.length;
        sampled += (end > info.duration ? info.duration : end) - sample.start;
      }
      finished = sampled > Duration.zero;
    } finally {
      // A trial that failed or was stopped keeps nothing.
      if (!finished || generation != _generation) {
        if (poorest?.frame.encodedPiece case final path?) await _delete(path);
      }
    }
    if (!finished || generation != _generation) return null;
    final estimate = extrapolateSamples(
      info: info,
      plan: plan,
      sampleBytes: bytes,
      sampled: sampled,
      spent: stopwatch.elapsed,
    );
    return _Trial(
      bytes: estimate.bytes,
      time: estimate.time,
      score: scores.isEmpty || scores.contains(null)
          ? null
          : QualityScore.worstOf(scores.cast<QualityScore>()),
      hardest: poorest?.frame,
    );
  }

  /// How close [output], an encoded [sample], comes to the same piece of the
  /// original, and its frame that differs most. Null when it could not be
  /// compared.
  Future<({QualityScore score, ({int index, double score})? hardest})?>
  _compare(
    MediaInfo info,
    String output,
    SampleRange sample,
    int generation,
  ) async {
    final video = info.video;
    final useVmaf = vmaf && video != null;
    final log = File(p.join(_workDir.path, 'frames_${_counter++}.log'));
    final run = await _runner.start(
      comparisonArgs(
        original: info.path,
        result: output,
        range: sample,
        vmafModel: useVmaf ? vmafModelFor(video.width, video.height) : null,
        threads: Platform.numberOfProcessors,
        frameLog: log.path,
      ),
    );
    _running.add(run);
    if (generation != _generation) unawaited(run.cancel());
    final result = await run.result;
    _running.remove(run);
    try {
      if (result.status != RunStatus.completed) return null;
      final lumaDb = parseXpsnr(result.errorLines);
      if (lumaDb == null) return null;
      final frames = await log.exists()
          ? frameScores(await log.readAsString())
          : const <double>[];
      ({int index, double score})? hardest;
      for (var i = 0; i < frames.length; i++) {
        if (hardest == null || frames[i] < hardest.score) {
          hardest = (index: i, score: frames[i]);
        }
      }
      return (
        score: QualityScore(lumaDb, vmaf: parseVmaf(result.errorLines)),
        hardest: hardest,
      );
    } finally {
      if (await log.exists()) await log.delete();
    }
  }

  Future<void> _delete(String path) async {
    _kept.remove(path);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> cancelAll() async {
    _generation++;
    final measuring = _measuring.toList();
    await Future.wait([for (final run in _running.toList()) run.cancel()]);
    // Each ends when its FFmpeg has exited and its sample is deleted.
    await Future.wait([
      for (final estimate in measuring) estimate.catchError((_) => null),
    ]);
  }

  @override
  Future<void> discardKept() async {
    for (final path in _kept.toList()) {
      await _delete(path);
    }
  }
}

/// What encoding the pieces at one quality showed.
class _Trial {
  const _Trial({
    required this.bytes,
    required this.time,
    this.score,
    this.hardest,
  });

  final int bytes;
  final Duration? time;

  /// The poorest piece's score; null where the pieces were not compared.
  final QualityScore? score;
  final HardestFrame? hardest;
}
