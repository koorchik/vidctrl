/// Building blocks shared by presets: frame rates, audio targets and size
/// estimates.
///
/// Colour tags need no block, but for where the colour samples sit. FFmpeg 8
/// carries primaries, transfer, matrix and range from the decoded frames to
/// the encoder by itself, and ignores the `-color_primaries` family of
/// output options for encodes. The conversion tests check that tags
/// survive, so a build that behaves differently fails them.
library;

import '../media/media_info.dart';
import 'scenario.dart';

const _standardFrameRates = {
  '24000/1001': 24000 / 1001,
  '24': 24.0,
  '25': 25.0,
  '30000/1001': 30000 / 1001,
  '30': 30.0,
  '50': 50.0,
  '60000/1001': 60000 / 1001,
  '60': 60.0,
  '120': 120.0,
};

/// The standard frame rate closest to [fps], in FFmpeg's `-r` notation.
String nearestStandardFrameRate(double fps) {
  var best = _standardFrameRates.entries.first;
  for (final entry in _standardFrameRates.entries) {
    if ((entry.value - fps).abs() < (best.value - fps).abs()) best = entry;
  }
  return best.key;
}

/// Filters that make a 4:2:2 or 4:4:4 picture 4:2:0 in [pixFmt]; none for
/// one that is 4:2:0 already, whose colour samples stay as they are. A
/// plain `-pix_fmt` would subsample with the default bilinear scaler, and
/// put each colour sample elsewhere than MPEG does; Lanczos keeps colour
/// edges cleaner, and "left" is the place players assume and the one
/// [av1ChromaPositionArgs] then names.
List<String> to420Filters(VideoStream video, String pixFmt) {
  if (video.chroma == ChromaSubsampling.yuv420) return const [];
  return [
    'scale=flags=lanczos+accurate_rnd:out_chroma_loc=left',
    'format=$pixFmt',
  ];
}

/// Output arguments that name, in an AV1 stream, where its colour samples
/// sit: as in [video], or "left" after [to420Filters]. Without them AV1
/// says "unknown" and a player may draw the colour half a sample off. FFmpeg
/// loses the place when it changes the bit depth and gives it to no
/// hardware encoder, so the stream is marked after encoding. AV1 can name
/// only MPEG's "left" and "top left".
List<String> av1ChromaPositionArgs(VideoStream video) {
  final location = video.chroma == ChromaSubsampling.yuv420
      ? video.chromaLocation
      : 'left';
  final position = switch (location) {
    'left' => 'vertical',
    'topleft' => 'colocated',
    _ => null,
  };
  if (position == null) return const [];
  return ['-bsf:v', 'av1_metadata=chroma_sample_position=$position'];
}

/// Arguments that turn irregular frame timing into a constant rate.
///
/// A phone that records "30 fps" with dropped frames averages a little under
/// 30, so the declared rate is the better target. Some recorders declare a
/// timebase-like rate far above the real one; then the average is used.
List<String> constantFrameRateArgs(VideoStream video) {
  final average = video.averageFrameRate ?? 30;
  final nominal = video.nominalFrameRate;
  final target = nominal != null && nominal <= average * 1.5
      ? nominal
      : average;
  return ['-fps_mode', 'cfr', '-r', nearestStandardFrameRate(target)];
}

/// Lossless 24-bit PCM: the audio every Resolve edition on Linux decodes.
const pcmAudio = AudioEncode(codec: 'pcm_s24le');

/// Lossless audio for containers that cannot hold PCM.
const flacAudio = AudioEncode(codec: 'flac');

int pcmBytes(MediaInfo info, {int bitsPerSample = 24}) {
  final seconds = info.duration.inMicroseconds / 1e6;
  var bitsPerSecond = 0;
  for (final track in info.audio) {
    bitsPerSecond += track.sampleRate * track.channels * bitsPerSample;
  }
  return (bitsPerSecond * seconds / 8).round();
}

/// Bytes the audio tracks occupy in the source, from their bitrates.
int sourceAudioBytes(MediaInfo info) {
  final seconds = info.duration.inMicroseconds / 1e6;
  var bitsPerSecond = 0;
  for (final track in info.audio) {
    bitsPerSecond += track.bitRate ?? 0;
  }
  return (bitsPerSecond * seconds / 8).round();
}

/// Bytes the video stream occupies in the source.
int sourceVideoBytes(MediaInfo info) {
  final video = info.video;
  if (video == null) return 0;
  final bitRate = video.bitRate;
  if (bitRate != null) {
    // Seconds first: bits per second times microseconds overflows.
    final seconds = info.duration.inMicroseconds / 1e6;
    return (bitRate * seconds / 8).round();
  }
  final rest = info.sizeBytes - sourceAudioBytes(info);
  return rest > 0 ? rest : info.sizeBytes;
}

/// Size of an intermediate codec whose bitrate is fixed by resolution and
/// frame rate. [megabitsAtUhd30] is the published rate at 3840x2160, 30 fps.
int fixedRateVideoBytes(MediaInfo info, double megabitsAtUhd30) {
  final video = info.video;
  if (video == null) return 0;
  const uhdPixelsPerSecond = 3840 * 2160 * 30;
  final scale = video.pixels * (video.frameRate ?? 30) / uhdPixelsPerSecond;
  final seconds = info.duration.inMicroseconds / 1e6;
  return (megabitsAtUhd30 * 1e6 * scale * seconds / 8).round();
}

/// A short file-name tag for an encode, from the settings that matter:
/// `hevc-crf20`, `av1-nvenc-cq28`. Lets results made with different settings
/// be told apart by name.
String encoderTag(VideoEncode video) {
  final encoder = video.encoder;
  final family = encoder.contains('265') || encoder.startsWith('hevc')
      ? 'hevc'
      : encoder.contains('av1')
      ? 'av1'
      : encoder.contains('264')
      ? 'h264'
      : encoder.replaceAll('_', '-');
  final hardware = encoder.startsWith('lib') ? null : encoder.split('_').last;
  const qualityFlags = {
    '-crf': 'crf',
    '-cq': 'cq',
    '-global_quality': 'icq',
    '-qvbr_quality_level': 'qvbr',
    '-q:v': 'q',
  };
  String? quality;
  for (final entry in qualityFlags.entries) {
    final index = video.args.indexOf(entry.key);
    if (index >= 0 && index + 1 < video.args.length) {
      quality = '${entry.value}${video.args[index + 1]}';
      break;
    }
  }
  return [family, ?hardware, ?quality].join('-');
}

/// AAC for results meant to be kept: 320 kbit/s for stereo, which is
/// transparent and still a small part of a video file. Used wherever lossless
/// or unusual sound (the FLAC or PCM of an editor export) is turned into
/// something every player reads.
AudioEncode highQualityAac(MediaInfo input) {
  final channels = input.audio.fold(
    0,
    (most, track) => track.channels > most ? track.channels : most,
  );
  final bitRate = switch (channels) {
    <= 1 => '192k',
    2 => '320k',
    _ => '512k',
  };
  return AudioEncode(codec: 'aac', args: ['-b:a', bitRate]);
}

/// AAC at or below this is kept as it is: re-encoding lossy sound only loses
/// quality.
const keepAacUpTo = 320000;
