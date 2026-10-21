import 'dart:convert';
import 'dart:io';

import 'media_info.dart';

class FfprobeException implements Exception {
  FfprobeException(this.message);

  final String message;

  @override
  String toString() => 'FfprobeException: $message';
}

/// Runs ffprobe on a file and turns its JSON report into a [MediaInfo].
class Ffprobe {
  Ffprobe(this.executable);

  final String executable;

  Future<MediaInfo> probe(String path) async {
    final result = await Process.run(
      executable,
      [
        '-v',
        'error',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        '-show_chapters',
        '-i',
        inputUrl(path),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw FfprobeException((result.stderr as String).trim());
    }
    final Object? json;
    try {
      json = jsonDecode(result.stdout as String);
    } on FormatException catch (e) {
      throw FfprobeException('unreadable ffprobe output: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw FfprobeException('unexpected ffprobe output');
    }
    return parseFfprobeJson(path, json);
  }
}

/// FFmpeg treats `name:rest` as a protocol and a leading `-` as an option.
/// The explicit `file:` protocol makes any file name safe to pass.
String inputUrl(String path) => 'file:$path';

MediaInfo parseFfprobeJson(String path, Map<String, dynamic> json) {
  final format = json['format'];
  if (format is! Map<String, dynamic>) {
    throw FfprobeException('no container information');
  }
  final streams = (json['streams'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();

  VideoStream? video;
  final audio = <AudioStream>[];
  for (final stream in streams) {
    switch (stream['codec_type']) {
      case 'video':
        if (video == null && !_isAttachedPicture(stream)) {
          video = _parseVideo(stream);
        }
      case 'audio':
        audio.add(_parseAudio(stream));
    }
  }

  return MediaInfo(
    path: path,
    formatName: format['format_name'] as String? ?? '',
    duration: _seconds(format['duration']) ?? Duration.zero,
    sizeBytes: _int(format['size']) ?? 0,
    bitRate: _int(format['bit_rate']),
    video: video,
    audio: audio,
    tags: _tags(format['tags']),
    raw: json,
  );
}

bool _isAttachedPicture(Map<String, dynamic> stream) {
  final disposition = stream['disposition'];
  return disposition is Map && disposition['attached_pic'] == 1;
}

VideoStream _parseVideo(Map<String, dynamic> s) {
  return VideoStream(
    index: _int(s['index']) ?? 0,
    codec: s['codec_name'] as String? ?? 'unknown',
    profile: s['profile'] as String?,
    width: _int(s['width']) ?? 0,
    height: _int(s['height']) ?? 0,
    pixFmt: s['pix_fmt'] as String? ?? 'yuv420p',
    averageFrameRate: _fraction(s['avg_frame_rate']),
    nominalFrameRate: _fraction(s['r_frame_rate']),
    bitRate: _int(s['bit_rate']),
    color: ColorInfo(
      primaries: _known(s['color_primaries']),
      transfer: _known(s['color_transfer']),
      space: _known(s['color_space']),
      range: _known(s['color_range']),
    ),
    chromaLocation: switch (_known(s['chroma_location'])) {
      'unspecified' => null,
      final location => location,
    },
    rotation: _rotation(s),
  );
}

AudioStream _parseAudio(Map<String, dynamic> s) {
  return AudioStream(
    index: _int(s['index']) ?? 0,
    codec: s['codec_name'] as String? ?? 'unknown',
    channels: _int(s['channels']) ?? 0,
    sampleRate: _int(s['sample_rate']) ?? 0,
    bitRate: _int(s['bit_rate']),
    language: _tags(s['tags'])['language'],
  );
}

int _rotation(Map<String, dynamic> stream) {
  final sideData = stream['side_data_list'];
  if (sideData is List) {
    for (final entry in sideData) {
      if (entry is Map && entry['rotation'] != null) {
        return (_num(entry['rotation'])?.round() ?? 0) % 360;
      }
    }
  }
  final legacy = _tags(stream['tags'])['rotate'];
  return (int.tryParse(legacy ?? '') ?? 0) % 360;
}

Map<String, String> _tags(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString().toLowerCase(): entry.value.toString(),
  };
}

String? _known(Object? value) {
  if (value is! String || value.isEmpty || value == 'unknown') return null;
  return value;
}

num? _num(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

int? _int(Object? value) => _num(value)?.toInt();

Duration? _seconds(Object? value) {
  final seconds = _num(value);
  if (seconds == null || seconds < 0) return null;
  return Duration(microseconds: (seconds * 1e6).round());
}

/// Parses ffprobe's `num/den` rates. `0/0` means "not known".
double? _fraction(Object? value) {
  if (value is! String) return null;
  final parts = value.split('/');
  final numerator = double.tryParse(parts[0]);
  final denominator = parts.length > 1 ? double.tryParse(parts[1]) : 1.0;
  if (numerator == null || denominator == null) return null;
  if (numerator <= 0 || denominator <= 0) return null;
  return numerator / denominator;
}
