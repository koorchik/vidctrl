import '../media/ffprobe.dart';
import '../scenarios/scenario.dart';

/// A short piece of the input to convert instead of the whole file, so the
/// user can check the result before committing to a long conversion.
class SampleRange {
  const SampleRange({this.start = Duration.zero, required this.length});

  final Duration start;
  final Duration length;
}

/// Turns a plan into FFmpeg arguments. Always a list, never a shell string,
/// so file names need no quoting.
///
/// A sample run uses the same arguments as the full run plus a time range,
/// which is what guarantees the sample shows the real result.
List<String> buildFfmpegArgs({
  required String input,
  required String output,
  required ConversionPlan plan,
  SampleRange? sample,
  bool forDisplay = false,
}) {
  assert(plan.producesOutput, 'nothing to run for a ${plan.kind} plan');
  final video = plan.video;
  final audio = plan.audio;
  final url = forDisplay ? _readablePath : inputUrl;
  return [
    '-hide_banner',
    // What the app adds for itself: overwrite its own temporary file, stay
    // quiet, and report progress in a machine-readable form. Someone running
    // the command by hand wants FFmpeg's normal output instead.
    if (!forDisplay) ...[
      '-y',
      '-loglevel',
      'error',
      '-nostats',
      '-progress',
      'pipe:1',
    ],
    // Before the input, so FFmpeg seeks instead of decoding up to the start.
    if (sample != null && sample.start > Duration.zero) ...[
      '-ss',
      ffmpegSeconds(sample.start),
    ],
    '-i', url(input),
    if (sample != null) ...['-t', ffmpegSeconds(sample.length)],

    // Only the main picture and the audio tracks are carried over. Data
    // tracks are dropped; FFmpeg rebuilds the timecode track from metadata.
    if (video is VideoNone) '-vn' else ...['-map', '0:v:0'],
    if (audio is AudioNone)
      '-an'
    else ...[
      '-map',
      plan.firstAudioOnly ? '0:a:0' : '0:a?',
    ],
    '-map_metadata', plan.keepMetadata ? '0' : '-1',

    ...switch (video) {
      VideoCopy() => ['-c:v', 'copy'],
      VideoNone() => const <String>[],
      VideoEncode() => [
        '-c:v',
        video.encoder,
        ...video.args,
        if (video.filters.isNotEmpty) ...['-vf', video.filters.join(',')],
        '-pix_fmt',
        video.pixFmt,
      ],
    },
    ...switch (audio) {
      AudioCopy() => ['-c:a', 'copy'],
      AudioNone() => const <String>[],
      AudioEncode() => ['-c:a', audio.codec, ...audio.args],
    },

    ...plan.outputArgs,
    '-f', plan.muxer,
    url(output),
  ];
}

/// [d] as FFmpeg takes a time: seconds, to the millisecond. Cutting a piece,
/// comparing it and grabbing its frame all seek with this, so they land on
/// the same frame.
String ffmpegSeconds(Duration d) => (d.inMicroseconds / 1e6).toStringAsFixed(3);

/// A path as a person would type it. The `file:` prefix is kept only where
/// FFmpeg would otherwise misread the name as an option or a protocol.
String _readablePath(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final risky = name.startsWith('-') || name.contains(':');
  return risky ? inputUrl(path) : path;
}
