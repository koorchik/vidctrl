/// Predicts how large a converted file will be, and how long it will take,
/// before converting it.
///
/// Copies and fixed-rate formats can be worked out from the source. A
/// quality-targeted encode cannot: its size depends on the footage (grain,
/// motion, detail). For those a few short pieces of the video are encoded
/// with the exact settings and the result is scaled up to the whole length.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../ffmpeg/command_builder.dart';
import '../ffmpeg/runner.dart';
import '../media/media_info.dart';
import '../scenarios/blocks.dart';
import '../scenarios/scenario.dart';

class OutputEstimate {
  const OutputEstimate({required this.bytes, this.time, this.measured = false});

  final int bytes;

  /// Expected conversion time. Null where it is negligible or unknown.
  final Duration? time;

  /// Measured by encoding samples, as opposed to calculated.
  final bool measured;
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
}) {
  final scale = info.duration.inMicroseconds / sampled.inMicroseconds;
  return OutputEstimate(
    bytes: (sampleBytes * scale).round() + audioOutputBytes(info, plan),
    time: spent * scale,
    measured: true,
  );
}

abstract interface class OutputEstimator {
  /// Null when the estimate could not be made or was cancelled.
  Future<OutputEstimate?> estimate(MediaInfo info, ConversionPlan plan);

  /// Stops every estimate in progress. Completes once they have ended: FFmpeg
  /// has exited and nothing it wrote is left.
  Future<void> cancelAll();
}

/// Measures quality-targeted encodes by encoding samples with FFmpeg.
class SampleEstimator implements OutputEstimator {
  SampleEstimator(this._runner, {Directory? workDir})
    : _workDir =
          workDir ??
          Directory(
            p.join(Directory.systemTemp.path, 'vidctrl_estimates_$pid'),
          );

  final FfmpegRunner _runner;
  final Directory _workDir;
  final _running = <FfmpegRun>{};

  /// Estimates under way, so that [cancelAll] can wait for them to end.
  final _measuring = <Future<OutputEstimate?>>{};
  var _generation = 0;
  var _counter = 0;

  @override
  Future<OutputEstimate?> estimate(MediaInfo info, ConversionPlan plan) async {
    final measuring = _measure(info, plan);
    _measuring.add(measuring);
    try {
      return await measuring;
    } finally {
      _measuring.remove(measuring);
    }
  }

  Future<OutputEstimate?> _measure(MediaInfo info, ConversionPlan plan) async {
    final calculated = estimateWithoutEncoding(info, plan);
    if (calculated != null) return calculated;
    if (plan.video is! VideoEncode) return null;
    final samples = estimationSamples(info.duration);
    if (samples.isEmpty) return null;

    final generation = _generation;
    // The sound is calculated, so only the picture is encoded.
    final pictureOnly = plan.withAudio(const AudioNone());
    await _workDir.create(recursive: true);

    var bytes = 0;
    var sampled = Duration.zero;
    final stopwatch = Stopwatch()..start();
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
      try {
        if (generation != _generation) return null;
        if (result.status != RunStatus.completed) return null;
        if (!await output.exists()) return null;
        bytes += await output.length();
      } finally {
        if (await output.exists()) await output.delete();
      }
      final end = sample.start + sample.length;
      sampled += (end > info.duration ? info.duration : end) - sample.start;
    }
    if (sampled <= Duration.zero) return null;
    return extrapolateSamples(
      info: info,
      plan: plan,
      sampleBytes: bytes,
      sampled: sampled,
      spent: stopwatch.elapsed,
    );
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
}
