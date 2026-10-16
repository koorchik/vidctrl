import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the FFmpeg build in use, and the hardware it runs on, can actually do.
/// Presets consult this so they never plan an encode that would fail.
class Capabilities {
  const Capabilities({
    required this.ffmpegVersion,
    required this.encoders,
    this.hardwareEncoders = const {},
    this.svtAv1Params = '',
    this.filters = const {},
  });

  final String ffmpegVersion;

  /// Encoders compiled into the build.
  final Set<String> encoders;

  /// Hardware encoders that produced output in a real test encode. Being
  /// compiled in is not enough: it also takes a matching GPU and driver.
  final Set<String> hardwareEncoders;

  /// The richest `-svtav1-params` string this SVT-AV1 version accepts.
  final String svtAv1Params;

  /// Video and audio filters compiled into the build.
  final Set<String> filters;

  bool hasEncoder(String name) => encoders.contains(name);
  bool hasFilter(String name) => filters.contains(name);
  bool hasHardwareEncoder(String name) => hardwareEncoders.contains(name);
}

/// `-svtav1-params` candidates, best first. Parameter names changed between
/// SVT-AV1 releases, so the first one the library accepts is used.
const svtAv1ParamCandidates = [
  'tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0:keyint=10s:scd=1',
  'tune=0:enable-variance-boost=1:keyint=10s',
  'tune=0',
  '',
];

/// Hardware encoders worth probing, with the pixel format used for the test.
/// AV1 and HEVC are tested in 10-bit because an encoder can pass in 8-bit and
/// still fail in 10-bit.
const _hardwareCandidates = {
  'av1_nvenc': 'p010le',
  'hevc_nvenc': 'p010le',
  'h264_nvenc': 'yuv420p',
  'av1_qsv': 'p010le',
  'hevc_qsv': 'p010le',
  'h264_qsv': 'nv12',
  'av1_amf': 'p010le',
  'hevc_amf': 'p010le',
  'h264_amf': 'nv12',
  'hevc_videotoolbox': 'p010le',
  'h264_videotoolbox': 'nv12',
};

class CapabilityProbe {
  CapabilityProbe(this.ffmpeg, {this.timeout = const Duration(seconds: 15)});

  final String ffmpeg;
  final Duration timeout;

  Future<Capabilities> detect() async {
    final version = await _version();
    final encoders = await _encoders();
    final candidates = _hardwareCandidates.entries
        .where((e) => encoders.contains(e.key))
        .toList();
    final working = await Future.wait(
      candidates.map((e) => _testEncode(e.key, e.value)),
    );
    return Capabilities(
      ffmpegVersion: version,
      encoders: encoders,
      hardwareEncoders: {
        for (var i = 0; i < candidates.length; i++)
          if (working[i]) candidates[i].key,
      },
      svtAv1Params: encoders.contains('libsvtav1') ? await _svtAv1Params() : '',
      filters: await _filters(),
    );
  }

  Future<String> _version() async {
    final result = await Process.run(ffmpeg, ['-version']);
    final firstLine = (result.stdout as String).split('\n').first;
    return parseFfmpegVersion(firstLine);
  }

  Future<Set<String>> _encoders() async {
    final result = await Process.run(ffmpeg, ['-hide_banner', '-encoders']);
    return parseEncoderList(result.stdout as String);
  }

  Future<Set<String>> _filters() async {
    final result = await Process.run(ffmpeg, ['-hide_banner', '-filters']);
    return parseFilterList(result.stdout as String);
  }

  Future<bool> _testEncode(String encoder, String pixFmt) async {
    final result = await _run([
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=black:s=1280x720:r=30',
      '-frames:v',
      '8',
      '-pix_fmt',
      pixFmt,
      '-c:v',
      encoder,
      '-f',
      'null',
      '-',
    ]);
    return result != null && result.exitCode == 0;
  }

  Future<String> _svtAv1Params() async {
    for (final params in svtAv1ParamCandidates) {
      if (params.isEmpty) break;
      final result = await _run([
        '-v',
        'warning',
        '-f',
        'lavfi',
        '-i',
        'color=black:s=640x360:r=30',
        '-frames:v',
        '8',
        '-pix_fmt',
        'yuv420p10le',
        '-c:v',
        'libsvtav1',
        '-preset',
        '12',
        '-svtav1-params',
        params,
        '-f',
        'null',
        '-',
      ]);
      if (result == null || result.exitCode != 0) continue;
      // FFmpeg only warns about a parameter the library rejects, and encodes
      // without it, so the exit code alone would hide the problem.
      if ((result.stderr as String).contains('Error parsing option')) continue;
      return params;
    }
    return '';
  }

  Future<ProcessResult?> _run(List<String> args) async {
    final process = await Process.start(ffmpeg, [
      '-hide_banner',
      '-nostdin',
      ...args,
    ], environment: ffmpegEnvironment);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return null;
    }
  }
}

/// SVT-AV1 prints a banner on stderr regardless of FFmpeg's log level.
/// `SVT_LOG=1` limits it to errors.
const ffmpegEnvironment = {'SVT_LOG': '1'};

/// Extracts `8.0.1` from `ffmpeg version 8.0.1-3ubuntu2 Copyright ...`.
String parseFfmpegVersion(String firstLine) {
  final match = RegExp(r'ffmpeg version (\S+)').firstMatch(firstLine);
  return match?.group(1) ?? 'unknown';
}

/// The release number in a version as builders write it ("8.1.3" from
/// "n8.1.3-9-g29e619e767-20260930"), or the whole of it when there is none,
/// as in a build of the development branch.
String shortFfmpegVersion(String version) =>
    RegExp(r'\d+(\.\d+)+').firstMatch(version)?.group(0) ?? version;

final _encoderLine = RegExp(r'^\s[VAS][A-Z.]{5}\s+(\S+)');

/// Parses `ffmpeg -encoders` into the set of encoder names.
Set<String> parseEncoderList(String output) {
  final names = <String>{};
  for (final line in const LineSplitter().convert(output)) {
    final match = _encoderLine.firstMatch(line);
    if (match != null && match.group(1) != '=') names.add(match.group(1)!);
  }
  return names;
}

final _filterLine = RegExp(r'^\s[T.][S.][C.]?\s+(\S+)\s+\S+->\S+');

/// Parses `ffmpeg -filters` into the set of filter names.
Set<String> parseFilterList(String output) => {
  for (final line in const LineSplitter().convert(output))
    if (_filterLine.firstMatch(line) case final match?) match.group(1)!,
};
