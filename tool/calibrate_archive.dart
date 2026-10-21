// Measures how close each way of encoding in "For the archive" comes to the
// original, to set the quality numbers at the top of
// `lib/core/scenarios/archive.dart`.
//
// A piece of each clip is encoded by every encoder this machine has, at
// several quality numbers, with the arguments the app itself would use, and
// compared with the piece by FFmpeg's `xpsnr` filter (luma). For each
// encoder it prints the number that gives the smallest file while every
// clip still reaches the target, and what each clip then weighs and takes.
// Use clips of different kinds; the hardest one decides.
//
//   dart run tool/calibrate_archive.dart [--target 42] [--start 10]
//       [--seconds 10] clip...
//
// The footage is only read. Pieces and encodes go to a temporary folder that
// is removed at the end.

import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/locator.dart';
import 'package:vidctrl/core/media/ffprobe.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/scenarios/archive.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

/// The quality options encoders take, whichever this one uses.
const _qualityFlags = [
  '-crf',
  '-cq',
  '-global_quality',
  '-qvbr_quality_level',
  '-q:v',
];

typedef _Point = ({double value, int bytes, double seconds, double xpsnr});

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final target = double.parse(_takeValue(args, '--target') ?? '42');
  final start = _takeValue(args, '--start') ?? '10';
  final seconds = _takeValue(args, '--seconds') ?? '10';
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/calibrate_archive.dart '
      '[--target 42] [--start 10] [--seconds 10] clip...',
    );
    exit(64);
  }
  final paths = FfmpegLocator().locate();
  if (paths == null) {
    stderr.writeln('FFmpeg and ffprobe were not found.');
    exit(2);
  }
  final capabilities = await CapabilityProbe(paths.ffmpeg).detect();
  final ffprobe = Ffprobe(paths.ffprobe);
  const preset = ArchivePreset();

  // Each way of encoding the goal offers here, and the numbers to try.
  final ways = <(String, OptionValues, List<num>)>[
    if (ArchivePreset.encodesAv1(capabilities))
      ('svt-av1', {'codec': 'av1'}, [23, 27, 31, 35, 39]),
    ('x265', {'codec': 'hevc'}, [16, 19, 22, 25, 28]),
    if (ArchivePreset.gpuEncoder(capabilities, 'av1') case final encoder?)
      (encoder, {'codec': 'av1', 'speed': 'gpu'}, [20, 24, 28, 32, 36]),
    if (ArchivePreset.gpuEncoder(capabilities, 'hevc') case final encoder?)
      (
        encoder,
        {'codec': 'hevc', 'speed': 'gpu'},
        // Apple's scale runs 0-100, higher being better.
        encoder.endsWith('videotoolbox')
            ? [55, 65, 75, 85, 95]
            : [16, 20, 24, 28, 32],
      ),
  ];

  final work = await Directory.systemTemp.createTemp('calibrate_archive');
  final points = <(String, String), List<_Point>>{};
  try {
    for (final (index, clip) in args.indexed) {
      final name = p.basename(clip);
      final piece = p.join(work.path, 'piece$index.mkv');
      await _ffmpeg(paths.ffmpeg, [
        '-ss', start, '-i', clip, '-t', seconds, //
        '-map', '0:v:0', '-c', 'copy', piece,
      ]);
      final info = await ffprobe.probe(piece);
      for (final (way, values, numbers) in ways) {
        final video = preset.plan(info, values, capabilities).video;
        if (video is! VideoEncode) continue;
        for (final number in numbers.map((n) => n.toDouble())) {
          final out = p.join(work.path, 'out.mp4');
          final settings = [...video.args];
          final at = settings.indexWhere(_qualityFlags.contains);
          settings[at + 1] = number.round().toString();
          final clock = Stopwatch()..start();
          // Every frame of the piece, none added or dropped, so that the
          // comparison can pair them by order.
          await _ffmpeg(paths.ffmpeg, [
            '-i', piece, '-an', '-fps_mode', 'passthrough', //
            '-c:v', video.encoder, ...settings,
            if (video.filters.isNotEmpty) ...['-vf', video.filters.join(',')],
            '-pix_fmt', video.pixFmt, out,
          ]);
          final point = (
            value: number,
            bytes: File(out).lengthSync(),
            seconds: clock.elapsedMilliseconds / 1000,
            xpsnr: await _xpsnr(paths.ffmpeg, out, piece),
          );
          (points[(way, name)] ??= []).add(point);
          stdout.writeln(
            '$name  $way ${settings[at]} ${number.round()}  '
            '${_mb(point.bytes)}  ${point.seconds.toStringAsFixed(1)} s  '
            '${point.xpsnr.toStringAsFixed(2)} dB',
          );
        }
      }
    }
  } finally {
    await work.delete(recursive: true);
  }

  stdout.writeln('\nAt least $target dB on every clip:');
  for (final (way, _, _) in ways) {
    final clips = [
      for (final (w, clip) in points.keys)
        if (w == way) clip,
    ];
    if (clips.isEmpty) continue;
    // Quality falls as the number rises for every encoder but Apple's.
    final rising =
        points[(way, clips.first)]!.first.xpsnr <
        points[(way, clips.first)]!.last.xpsnr;
    final needed = [
      for (final clip in clips) _crossing(points[(way, clip)]!, target),
    ];
    if (needed.contains(null)) {
      stdout.writeln('  $way: some clip never reaches the target');
      continue;
    }
    final choice = rising
        ? needed.cast<double>().reduce(max).ceilToDouble()
        : needed.cast<double>().reduce(min).floorToDouble();
    final tried = ways.firstWhere((w) => w.$1 == way).$3;
    final atEnd = choice == (rising ? tried.first : tried.last);
    stdout.writeln(
      '  $way: ${choice.round()}'
      '${atEnd ? ' (every number tried reaches it; try further ones)' : ''}',
    );
    for (final clip in clips) {
      final at = _interpolate(points[(way, clip)]!, choice);
      stdout.writeln(
        at == null
            ? '      $clip: outside the measured numbers'
            : '      $clip: ${_mb(at.bytes)}  '
                  '${at.seconds.toStringAsFixed(1)} s  '
                  '${at.xpsnr.toStringAsFixed(2)} dB',
      );
    }
  }
}

/// The number at which the score crosses [target]: past the last number
/// measured when every point reaches it, null when none does.
double? _crossing(List<_Point> points, double target) {
  for (final (a, b) in _pairs(points)) {
    if ((a.xpsnr - target) * (b.xpsnr - target) <= 0 && a.xpsnr != b.xpsnr) {
      return a.value +
          (b.value - a.value) * (a.xpsnr - target) / (a.xpsnr - b.xpsnr);
    }
  }
  if (points.every((pt) => pt.xpsnr >= target)) {
    return points.first.xpsnr < points.last.xpsnr
        ? points.first.value
        : points.last.value;
  }
  return null;
}

/// Size (on a log scale), time and score at a number between two measured.
_Point? _interpolate(List<_Point> points, double value) {
  for (final (a, b) in _pairs(points)) {
    if (a.value <= value && value <= b.value) {
      final t = (value - a.value) / (b.value - a.value);
      return (
        value: value,
        bytes: exp(log(a.bytes) * (1 - t) + log(b.bytes) * t).round(),
        seconds: a.seconds * (1 - t) + b.seconds * t,
        xpsnr: a.xpsnr * (1 - t) + b.xpsnr * t,
      );
    }
  }
  return null;
}

Iterable<(_Point, _Point)> _pairs(List<_Point> points) sync* {
  for (var i = 0; i + 1 < points.length; i++) {
    yield (points[i], points[i + 1]);
  }
}

/// Compared as the app's "Compare with the original" compares, frames
/// paired by order (`comparisonArgs`).
Future<double> _xpsnr(String ffmpeg, String encoded, String original) async {
  final result = await Process.run(
    ffmpeg,
    comparisonArgs(original: original, result: encoded),
  );
  final score = parseXpsnr((result.stderr as String).split('\n'));
  if (score == null) throw StateError('no XPSNR for $encoded');
  return score;
}

Future<void> _ffmpeg(String ffmpeg, List<String> args) async {
  final result = await Process.run(ffmpeg, ['-v', 'error', '-y', ...args]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg ${args.join(' ')}\n${result.stderr}');
  }
}

String _mb(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

String? _takeValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0 || i + 1 >= args.length) return null;
  final value = args[i + 1];
  args.removeRange(i, i + 2);
  return value;
}
