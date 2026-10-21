/// What ffprobe reported about one input file, reduced to the facts presets
/// need in order to decide what to do with it.
class MediaInfo {
  const MediaInfo({
    required this.path,
    required this.formatName,
    required this.duration,
    required this.sizeBytes,
    this.bitRate,
    this.video,
    this.audio = const [],
    this.tags = const {},
    this.raw = const {},
  });

  final String path;

  /// ffprobe's comma-separated demuxer name, e.g. `mov,mp4,m4a,3gp,3g2,mj2`.
  final String formatName;
  final Duration duration;
  final int sizeBytes;
  final int? bitRate;

  /// The main picture stream. Cover art (attached pictures) is not counted.
  final VideoStream? video;
  final List<AudioStream> audio;
  final Map<String, String> tags;

  /// ffprobe's complete report, for showing every detail of the file.
  final Map<String, Object?> raw;

  bool get isMovFamily => _formats.contains('mov');
  bool get isMatroska => _formats.contains('matroska');
  bool get isMxf => _formats.contains('mxf');
  bool get isAvi => _formats.contains('avi');

  List<String> get _formats => formatName.split(',');
}

enum ChromaSubsampling { yuv420, yuv422, yuv444 }

class VideoStream {
  const VideoStream({
    required this.index,
    required this.codec,
    required this.width,
    required this.height,
    required this.pixFmt,
    this.profile,
    this.averageFrameRate,
    this.nominalFrameRate,
    this.bitRate,
    this.color = const ColorInfo(),
    this.chromaLocation,
    this.rotation = 0,
  });

  final int index;
  final String codec;
  final String? profile;
  final int width;
  final int height;
  final String pixFmt;

  /// Frames divided by duration (`avg_frame_rate`).
  final double? averageFrameRate;

  /// The rate the stream is declared to tick at (`r_frame_rate`).
  final double? nominalFrameRate;
  final int? bitRate;
  final ColorInfo color;

  /// Where each colour sample sits among the picture's (`left`, `topleft`,
  /// `center`, …), as ffprobe names it; null when the file does not say.
  final String? chromaLocation;

  /// Display rotation in degrees, as stored by phones.
  final int rotation;

  int get pixels => width * height;
  int get bitDepth => bitDepthOfPixFmt(pixFmt);
  ChromaSubsampling get chroma => chromaOfPixFmt(pixFmt);

  double? get frameRate => averageFrameRate ?? nominalFrameRate;

  /// Phones and screen recorders often write frames at irregular intervals.
  /// Editors handle that badly, so presets convert such files to a constant
  /// rate. A nominal rate of exactly twice the average is field-rate
  /// signalling, not variable frame rate.
  bool get isVariableFrameRate {
    final avg = averageFrameRate;
    final nominal = nominalFrameRate;
    if (avg == null || nominal == null || avg <= 0 || nominal <= 0) {
      return false;
    }
    final ratio = nominal / avg;
    if ((ratio - 1).abs() <= 0.01) return false;
    if ((ratio - 2).abs() <= 0.02) return false;
    return true;
  }
}

class AudioStream {
  const AudioStream({
    required this.index,
    required this.codec,
    required this.channels,
    required this.sampleRate,
    this.bitRate,
    this.language,
  });

  final int index;
  final String codec;
  final int channels;
  final int sampleRate;
  final int? bitRate;
  final String? language;

  bool get isPcm => codec.startsWith('pcm_');
}

/// Colour tags as ffprobe names them. A null field means the file does not
/// say, which is common and must be passed on as "does not say".
class ColorInfo {
  const ColorInfo({this.primaries, this.transfer, this.space, this.range});

  final String? primaries;
  final String? transfer;
  final String? space;
  final String? range;

  /// PQ or HLG transfer: the picture is HDR and needs tone mapping before it
  /// can be shown as ordinary SDR video.
  bool get isHdr => transfer == 'smpte2084' || transfer == 'arib-std-b67';
}

final _planarDepth = RegExp(r'p(\d{2})(le|be)?$');
final _semiPlanarDepth = RegExp(r'^p[024](\d{2})');

/// Bits per colour sample for an FFmpeg pixel format name.
int bitDepthOfPixFmt(String pixFmt) {
  final semiPlanar = _semiPlanarDepth.firstMatch(pixFmt);
  if (semiPlanar != null) return int.parse(semiPlanar.group(1)!);
  final planar = _planarDepth.firstMatch(pixFmt);
  if (planar != null) return int.parse(planar.group(1)!);
  return 8;
}

ChromaSubsampling chromaOfPixFmt(String pixFmt) {
  if (pixFmt.contains('444') ||
      pixFmt.startsWith('gbr') ||
      pixFmt.startsWith('rgb') ||
      pixFmt.startsWith('bgr') ||
      pixFmt.startsWith('p4')) {
    return ChromaSubsampling.yuv444;
  }
  if (pixFmt.contains('422') ||
      pixFmt.startsWith('p2') ||
      pixFmt.startsWith('yuyv') ||
      pixFmt.startsWith('uyvy')) {
    return ChromaSubsampling.yuv422;
  }
  return ChromaSubsampling.yuv420;
}
