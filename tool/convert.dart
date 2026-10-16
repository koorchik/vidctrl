// Developer command-line front end for the conversion engine: runs any preset
// on a file without the UI.
//
//   dart run tool/convert.dart --list
//   dart run tool/convert.dart --caps
//   dart run tool/convert.dart <preset> <file> [--opt key=value]...
//       [--out <folder>] [--sample <start seconds>:<length seconds>] [--dry-run]

import 'dart:io';

import 'package:vidctrl/core/estimate/progress_estimator.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/command_builder.dart';
import 'package:vidctrl/core/ffmpeg/command_text.dart';
import 'package:vidctrl/core/ffmpeg/locator.dart';
import 'package:vidctrl/core/ffmpeg/runner.dart';
import 'package:vidctrl/core/media/ffprobe.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/queue/job_executor.dart';
import 'package:vidctrl/core/scenarios/registry.dart';

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final paths = FfmpegLocator().locate();
  if (paths == null) {
    stderr.writeln('FFmpeg and ffprobe were not found.');
    exit(2);
  }

  if (args.contains('--list')) {
    for (final scenario in scenarios) {
      for (final preset in scenario.presets) {
        final options = preset.options
            .map((o) => '${o.id}=${o.choices.join('|')}')
            .join('  ');
        stdout.writeln('${preset.id.padRight(18)} $options');
      }
    }
    return;
  }

  final capabilities = await CapabilityProbe(paths.ffmpeg).detect();
  if (args.contains('--caps')) {
    stdout
      ..writeln('FFmpeg ${capabilities.ffmpegVersion} (${paths.ffmpeg})')
      ..writeln('Encoders compiled in: ${capabilities.encoders.length}')
      ..writeln(
        'Working hardware encoders: '
        '${capabilities.hardwareEncoders.join(', ')}',
      )
      ..writeln('SVT-AV1 parameters: ${capabilities.svtAv1Params}');
    return;
  }

  final dryRun = args.remove('--dry-run');
  final outDir = _takeValue(args, '--out');
  final sample = _parseSample(_takeValue(args, '--sample'));
  final values = <String, String>{};
  for (String? opt; (opt = _takeValue(args, '--opt')) != null;) {
    final parts = opt!.split('=');
    if (parts.length == 2) values[parts[0]] = parts[1];
  }
  if (args.length != 2) {
    stderr.writeln('usage: convert.dart <preset> <file> [options]');
    exit(2);
  }

  final preset = findPreset(args[0]);
  if (preset == null) {
    stderr.writeln('Unknown preset "${args[0]}". Try --list.');
    exit(2);
  }
  final info = await Ffprobe(paths.ffprobe).probe(File(args[1]).absolute.path);
  final plan = preset.plan(info, values, capabilities);
  stdout.writeln('Plan: ${plan.kind.name}  ${plan.notes.map((n) => n.name)}');
  if (!plan.producesOutput) return;
  if (plan.estimatedBytes != null) {
    stdout.writeln('Estimated size: ${_megabytes(plan.estimatedBytes!)}');
  }

  final outputPath = planOutputPath(
    sourcePath: info.path,
    settings: outDir == null
        ? const OutputSettings()
        : OutputSettings(mode: OutputMode.customFolder, customDir: outDir),
    suffix: sample == null ? plan.nameSuffix : '${plan.nameSuffix}_sample',
    extension: plan.extension,
    exists: (path) => File(path).existsSync(),
  );
  final job = ConversionJob(
    input: info,
    plan: plan,
    outputPath: outputPath,
    sample: sample,
  );
  stdout.writeln(
    singleLineCommand(
      'ffmpeg',
      buildFfmpegArgs(
        input: info.path,
        output: temporaryPathFor(outputPath),
        plan: plan,
        sample: sample,
      ),
    ),
  );
  if (dryRun) return;

  final handle = await JobExecutor(FfmpegRunner(paths.ffmpeg)).start(job);
  ProcessSignal.sigint.watch().listen((_) => handle.cancel());
  handle.progress.listen(_printProgress);
  final result = await handle.result;
  stdout.writeln();
  switch (result.status) {
    case ConversionStatus.done:
      final change = result.outputBytes! * 100 / info.sizeBytes - 100;
      final comparison = change <= 0
          ? '${(-change).toStringAsFixed(0)}% smaller'
          : '${change.toStringAsFixed(0)}% larger';
      stdout.writeln(
        'Done in ${result.elapsed.inSeconds}s: ${result.outputPath} '
        '(${_megabytes(result.outputBytes!)}, '
        '${sample == null ? comparison : 'sample'})',
      );
    case ConversionStatus.cancelled:
      stdout.writeln('Cancelled.');
    case ConversionStatus.failed:
      stderr.writeln('Failed:\n${result.errorLines.join('\n')}');
      exitCode = 1;
  }
  // The SIGINT subscription would otherwise keep the process alive.
  exit(exitCode);
}

void _printProgress(JobProgress progress) {
  final percent = (progress.fraction * 100).toStringAsFixed(1);
  final speed = progress.speed == null
      ? ''
      : '  ${progress.speed!.toStringAsFixed(2)}x';
  final left = progress.remaining == null
      ? ''
      : '  ${progress.remaining!.inSeconds}s left';
  final size = progress.predictedBytes == null
      ? ''
      : '  ~${_megabytes(progress.predictedBytes!)}';
  stdout.write('\r$percent%$speed$left$size      ');
}

String _megabytes(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';

String? _takeValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  final value = args[index + 1];
  args.removeRange(index, index + 2);
  return value;
}

SampleRange? _parseSample(String? spec) {
  if (spec == null) return null;
  final parts = spec.split(':').map(double.tryParse).toList();
  if (parts.length != 2 || parts.contains(null)) return null;
  Duration seconds(double s) => Duration(microseconds: (s * 1e6).round());
  return SampleRange(start: seconds(parts[0]!), length: seconds(parts[1]!));
}
