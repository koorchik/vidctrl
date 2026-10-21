import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/media/media_info.dart';

const movContainer = 'mov,mp4,m4a,3gp,3g2,mj2';
const mkvContainer = 'matroska,webm';

/// A made-up input file for preset tests. Defaults describe a one-minute UHD
/// H.264 clip with stereo AAC in an MP4, the commonest thing cameras produce.
MediaInfo clip({
  String path = '/videos/clip.mp4',
  String container = movContainer,
  String? video = 'h264',
  String pixFmt = 'yuv420p',
  int width = 3840,
  int height = 2160,
  double fps = 25,
  double? nominalFps,
  int? videoBitRate = 100000000,
  ColorInfo color = const ColorInfo(),
  List<AudioStream>? audio,
  Duration duration = const Duration(minutes: 1),
}) {
  return MediaInfo(
    path: path,
    formatName: container,
    duration: duration,
    sizeBytes: 750000000,
    video: video == null
        ? null
        : VideoStream(
            index: 0,
            codec: video,
            width: width,
            height: height,
            pixFmt: pixFmt,
            averageFrameRate: fps,
            nominalFrameRate: nominalFps ?? fps,
            bitRate: videoBitRate,
            color: color,
          ),
    audio: audio ?? [track('aac')],
  );
}

AudioStream track(String codec, {int channels = 2, int? bitRate = 160000}) {
  return AudioStream(
    index: 1,
    codec: codec,
    channels: channels,
    sampleRate: 48000,
    bitRate: bitRate,
  );
}

/// An FFmpeg build with the usual software encoders and no usable GPU.
const softwareOnly = Capabilities(
  ffmpegVersion: 'test',
  encoders: {'libsvtav1', 'libx265', 'libx264', 'prores_ks', 'dnxhd', 'aac'},
  filters: {'xpsnr'},
  svtAv1Params: 'tune=0',
);

Capabilities withGpu(Set<String> hardwareEncoders) => Capabilities(
  ffmpegVersion: 'test',
  encoders: {...softwareOnly.encoders, ...hardwareEncoders},
  filters: softwareOnly.filters,
  hardwareEncoders: hardwareEncoders,
  svtAv1Params: 'tune=0',
);

/// A build that can also tone-map HDR.
const withToneMapping = Capabilities(
  ffmpegVersion: 'test',
  encoders: {'libx264', 'libx265', 'aac'},
  filters: {'zscale', 'tonemap', 'scale'},
);
