/// Turns ffprobe's report into the rows of the "Video details" window.
///
/// Labels are returned as [DetailField] codes and the few plain words as
/// [DetailNote] codes, so the UI can translate them; technical values
/// (codec names, numbers, pixel formats) are the same in every language.
library;

import 'dart:convert';

import 'media_info.dart';

enum DetailGroup {
  file,
  video,
  audio,
  subtitle,
  timecode,
  data,
  attachment,
  chapters,
}

enum DetailField {
  container,
  size,
  duration,
  bitrate,
  tracks,
  codec,
  resolution,
  aspectRatio,
  frameRate,
  bitDepth,
  chroma,
  pixelFormat,
  colorPrimaries,
  colorTransfer,
  colorMatrix,
  colorRange,
  hdr,
  masteringDisplay,
  lightLevel,
  scanType,
  rotation,
  frames,
  channels,
  sampleRate,
  sampleFormat,
  language,
  title,
  defaultTrack,
  timecode,
  fileName,
  chapter,
}

/// Words that appear as values and need translating.
enum DetailNote { variable, progressive, interlaced, notStated, yes, no }

class DetailRow {
  const DetailRow(this.field, this.value, {this.note});

  final DetailField field;

  /// Technical text, shown as is. May be empty when [note] says it all.
  final String value;
  final DetailNote? note;
}

class DetailSection {
  const DetailSection(this.group, this.number, this.rows);

  final DetailGroup group;

  /// 1-based position among sections of the same group ("Audio track 2").
  final int number;
  final List<DetailRow> rows;
}

class TagSection {
  const TagSection(this.group, this.number, this.tags);

  final DetailGroup group;
  final int number;
  final Map<String, String> tags;
}

/// Everything that describes how the file is encoded, grouped by file and
/// track.
List<DetailSection> encodingDetails(Map<String, Object?> raw) {
  final format = _map(raw['format']);
  final streams = _list(raw['streams']).map(_map).toList();
  final chapters = _list(raw['chapters']).map(_map).toList();
  final counts = <DetailGroup, int>{};
  int next(DetailGroup group) => counts[group] = (counts[group] ?? 0) + 1;

  final sections = <DetailSection>[
    DetailSection(DetailGroup.file, 1, [
      if (_str(format['format_long_name'] ?? format['format_name'])
          case final name?)
        DetailRow(DetailField.container, name),
      if (_int(format['size']) case final size?)
        DetailRow(DetailField.size, formatBytes(size)),
      if (_seconds(format['duration']) case final duration?)
        DetailRow(DetailField.duration, formatDuration(duration)),
      if (_int(format['bit_rate']) case final rate?)
        DetailRow(DetailField.bitrate, formatBitrate(rate)),
      DetailRow(DetailField.tracks, '${streams.length}'),
    ]),
  ];

  for (final stream in streams) {
    final tags = _map(stream['tags']);
    final group = _groupOf(stream);
    final rows = <DetailRow>[
      ...switch (group) {
        DetailGroup.video => _videoRows(stream),
        DetailGroup.audio => _audioRows(stream),
        DetailGroup.attachment => [
          if (_str(tags['filename']) case final name?)
            DetailRow(DetailField.fileName, name),
          DetailRow(DetailField.codec, _codec(stream)),
        ],
        DetailGroup.timecode => [
          DetailRow(
            DetailField.timecode,
            _str(tags['timecode']) ??
                _str(_map(format['tags'])['timecode']) ??
                '',
          ),
        ],
        _ => [DetailRow(DetailField.codec, _codec(stream))],
      },
    ];
    if (_str(tags['language']) case final language? when language != 'und') {
      rows.add(DetailRow(DetailField.language, language));
    }
    if (_str(tags['title']) case final title?) {
      rows.add(DetailRow(DetailField.title, title));
    }
    sections.add(DetailSection(group, next(group), rows));
  }

  if (chapters.isNotEmpty) {
    sections.add(
      DetailSection(DetailGroup.chapters, 1, [
        for (final chapter in chapters)
          DetailRow(
            DetailField.chapter,
            [
              '${formatDuration(_seconds(chapter['start_time']) ?? 0)}'
                  ' – ${formatDuration(_seconds(chapter['end_time']) ?? 0)}',
              ?_str(_map(chapter['tags'])['title']),
            ].join('  '),
          ),
      ]),
    );
  }
  return sections;
}

List<DetailRow> _videoRows(Map<String, Object?> s) {
  final pixFmt = _str(s['pix_fmt']);
  final average = _fraction(s['avg_frame_rate']);
  final nominal = _fraction(s['r_frame_rate']);
  final width = _int(s['width']);
  final height = _int(s['height']);
  final sideData = _list(s['side_data_list']).map(_map).toList();
  final transfer = _str(s['color_transfer']);

  Map<String, Object?>? side(String type) {
    for (final entry in sideData) {
      if (entry['side_data_type'] == type) return entry;
    }
    return null;
  }

  final variable =
      average != null &&
      nominal != null &&
      VideoStream(
        index: 0,
        codec: '',
        width: 0,
        height: 0,
        pixFmt: '',
        averageFrameRate: average.value,
        nominalFrameRate: nominal.value,
      ).isVariableFrameRate;
  final mastering = side('Mastering display metadata');
  final light = side('Content light level metadata');
  final dolby = side('DOVI configuration record');
  final rotation = sideData
      .map((e) => e['rotation'])
      .whereType<num>()
      .firstOrNull;
  final fieldOrder = _str(s['field_order']);
  final sar = _str(s['sample_aspect_ratio']);

  String color(Object? value) => _str(value) ?? '';
  DetailNote? stated(Object? value) =>
      _str(value) == null || value == 'unknown' ? DetailNote.notStated : null;

  return [
    DetailRow(DetailField.codec, _codec(s)),
    if (width != null && height != null)
      DetailRow(DetailField.resolution, '$width×$height'),
    if (_str(s['display_aspect_ratio']) case final dar?)
      DetailRow(
        DetailField.aspectRatio,
        sar != null && sar != '1:1' && sar != '0:1' ? '$dar (SAR $sar)' : dar,
      ),
    if (average != null || nominal != null)
      variable
          ? DetailRow(
              DetailField.frameRate,
              '${average.value.toStringAsFixed(2)} fps avg, '
              '${nominal.text} nominal',
              note: DetailNote.variable,
            )
          : DetailRow(
              DetailField.frameRate,
              '${(average ?? nominal)!.value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} fps'
              ' (${(average ?? nominal)!.text})',
            ),
    if (pixFmt != null) ...[
      DetailRow(DetailField.bitDepth, '${bitDepthOfPixFmt(pixFmt)}-bit'),
      DetailRow(DetailField.chroma, switch (chromaOfPixFmt(pixFmt)) {
        ChromaSubsampling.yuv420 => '4:2:0',
        ChromaSubsampling.yuv422 => '4:2:2',
        ChromaSubsampling.yuv444 => '4:4:4',
      }),
      DetailRow(DetailField.pixelFormat, pixFmt),
    ],
    DetailRow(
      DetailField.colorPrimaries,
      color(s['color_primaries']),
      note: stated(s['color_primaries']),
    ),
    DetailRow(
      DetailField.colorTransfer,
      color(s['color_transfer']),
      note: stated(s['color_transfer']),
    ),
    DetailRow(
      DetailField.colorMatrix,
      color(s['color_space']),
      note: stated(s['color_space']),
    ),
    DetailRow(
      DetailField.colorRange,
      color(s['color_range']),
      note: stated(s['color_range']),
    ),
    if (dolby != null)
      DetailRow(DetailField.hdr, 'Dolby Vision profile ${dolby['dv_profile']}')
    else if (transfer == 'smpte2084')
      const DetailRow(DetailField.hdr, 'HDR10 (PQ)')
    else if (transfer == 'arib-std-b67')
      const DetailRow(DetailField.hdr, 'HLG'),
    if (mastering != null)
      DetailRow(
        DetailField.masteringDisplay,
        '${_ratio(mastering['min_luminance'])}–'
        '${_ratio(mastering['max_luminance'])} cd/m²',
      ),
    if (light != null)
      DetailRow(
        DetailField.lightLevel,
        'MaxCLL ${light['max_content']} · MaxFALL ${light['max_average']}',
      ),
    if (fieldOrder != null)
      DetailRow(
        DetailField.scanType,
        fieldOrder == 'progressive' ? '' : fieldOrder.toUpperCase(),
        note: fieldOrder == 'progressive'
            ? DetailNote.progressive
            : DetailNote.interlaced,
      ),
    if (rotation != null && rotation != 0)
      DetailRow(DetailField.rotation, '${rotation.round()}°'),
    if (_int(s['bit_rate']) case final rate?)
      DetailRow(DetailField.bitrate, formatBitrate(rate)),
    if (_int(s['nb_frames']) case final frames?)
      DetailRow(DetailField.frames, '$frames'),
    _defaultRow(s),
  ];
}

List<DetailRow> _audioRows(Map<String, Object?> s) {
  final bits = _int(s['bits_per_raw_sample']) ?? _int(s['bits_per_sample']);
  return [
    DetailRow(DetailField.codec, _codec(s)),
    if (_int(s['channels']) case final channels?)
      DetailRow(
        DetailField.channels,
        [
          '$channels',
          if (_str(s['channel_layout']) case final layout?) '($layout)',
        ].join(' '),
      ),
    if (_int(s['sample_rate']) case final rate?)
      DetailRow(
        DetailField.sampleRate,
        '${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1)} kHz',
      ),
    if (_str(s['sample_fmt']) case final format?)
      DetailRow(
        DetailField.sampleFormat,
        bits != null && bits > 0 ? '$format, $bits-bit' : format,
      ),
    if (_int(s['bit_rate']) case final rate?)
      DetailRow(DetailField.bitrate, formatBitrate(rate)),
    _defaultRow(s),
  ];
}

DetailRow _defaultRow(Map<String, Object?> stream) {
  final isDefault = _map(stream['disposition'])['default'] == 1;
  return DetailRow(
    DetailField.defaultTrack,
    '',
    note: isDefault ? DetailNote.yes : DetailNote.no,
  );
}

/// `H.265 / HEVC (High Efficiency Video Coding) · Main 10 · level 5.1`.
String _codec(Map<String, Object?> s) {
  final name = _str(s['codec_long_name']) ?? _str(s['codec_name']) ?? 'unknown';
  final profile = _str(s['profile']);
  final level = _level(_str(s['codec_name']), _int(s['level']));
  return [
    name,
    if (profile != null && profile != 'unknown') profile,
    ?level,
  ].join(' · ');
}

String? _level(String? codec, int? level) {
  if (level == null || level <= 0) return null;
  final value = switch (codec) {
    'h264' => level / 10,
    'hevc' => level / 30,
    _ => null,
  };
  if (value == null) return null;
  return 'level ${value.toStringAsFixed(1)}';
}

/// Every tag of the file, of each track and of each chapter.
List<TagSection> metadataDetails(Map<String, Object?> raw) {
  final counts = <DetailGroup, int>{};
  int next(DetailGroup group) => counts[group] = (counts[group] ?? 0) + 1;
  Map<String, String> tags(Object? value) => {
    for (final entry in _map(_map(value)['tags']).entries)
      entry.key: '${entry.value}',
  };

  final sections = <TagSection>[
    TagSection(DetailGroup.file, 1, tags(raw['format'])),
  ];
  for (final stream in _list(raw['streams']).map(_map)) {
    final group = _groupOf(stream);
    sections.add(TagSection(group, next(group), tags(stream)));
  }
  final chapters = _list(raw['chapters']);
  for (var i = 0; i < chapters.length; i++) {
    sections.add(TagSection(DetailGroup.chapters, i + 1, tags(chapters[i])));
  }
  return sections;
}

/// What kind of track [stream] is, the same in both views. A picture
/// attached to the file (a cover) is an attachment, not the video.
DetailGroup _groupOf(Map<String, Object?> stream) =>
    switch (stream['codec_type']) {
      'video' when _map(stream['disposition'])['attached_pic'] != 1 =>
        DetailGroup.video,
      'audio' => DetailGroup.audio,
      'subtitle' => DetailGroup.subtitle,
      'attachment' || 'video' => DetailGroup.attachment,
      _
          when stream['codec_tag_string'] == 'tmcd' ||
              _map(stream['tags']).containsKey('timecode') =>
        DetailGroup.timecode,
      _ => DetailGroup.data,
    };

/// The whole report, as indented JSON.
String fullReport(Map<String, Object?> raw) =>
    const JsonEncoder.withIndent('  ').convert(raw);

String formatBytes(int bytes) {
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
  return '${(bytes / 1e3).toStringAsFixed(0)} KB';
}

String formatBitrate(int bitsPerSecond) => bitsPerSecond >= 1e6
    ? '${(bitsPerSecond / 1e6).toStringAsFixed(1)} Mbit/s'
    : '${(bitsPerSecond / 1e3).round()} kbit/s';

/// `0:02:31.251`.
String formatDuration(double seconds) {
  final whole = seconds.floor();
  final millis = ((seconds - whole) * 1000).round().toString().padLeft(3, '0');
  final h = whole ~/ 3600;
  final m = (whole % 3600 ~/ 60).toString().padLeft(2, '0');
  final s = (whole % 60).toString().padLeft(2, '0');
  return '$h:$m:$s.$millis';
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

String? _str(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}

int? _int(Object? value) => value is num
    ? value.toInt()
    : value is String
    ? num.tryParse(value)?.toInt()
    : null;

double? _seconds(Object? value) => value is num
    ? value.toDouble()
    : value is String
    ? double.tryParse(value)
    : null;

/// ffprobe writes luminance as `"10000000/10000"`.
String _ratio(Object? value) {
  final parts = '$value'.split('/');
  final top = double.tryParse(parts.first);
  final bottom = parts.length > 1 ? double.tryParse(parts[1]) : 1.0;
  if (top == null || bottom == null || bottom == 0) return '$value';
  final result = top / bottom;
  return result >= 10
      ? result.toStringAsFixed(0)
      : result.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
}

({double value, String text})? _fraction(Object? value) {
  final text = _str(value);
  if (text == null) return null;
  final parts = text.split('/');
  final top = double.tryParse(parts.first);
  final bottom = parts.length > 1 ? double.tryParse(parts[1]) : 1.0;
  if (top == null || bottom == null || top <= 0 || bottom <= 0) return null;
  return (value: top / bottom, text: text);
}

/// Fields whose values are long and get a full row to themselves.
const wideFields = {
  DetailField.codec,
  DetailField.masteringDisplay,
  DetailField.lightLevel,
  DetailField.title,
  DetailField.fileName,
  DetailField.chapter,
};

const _personalTags = {
  'title',
  'artist',
  'author',
  'album_artist',
  'composer',
  'comment',
  'description',
  'synopsis',
  'copyright',
  'date',
  'creation_time',
  'location',
  'make',
  'model',
  'software',
  'keywords',
  'publisher',
  'encoded_by',
  'timecode',
};

/// Whether a metadata tag can tell something about the person who made the
/// video: who, where, when, with what. "Remove personal data" removes every
/// tag; this is for pointing out the ones that matter.
bool isPersonalTag(String key) {
  final name = key.toLowerCase();
  final last = name.split('.').last.split('-').first;
  return _personalTags.contains(last) ||
      name.contains('location') ||
      name.contains('gps') ||
      name.contains('serial');
}

/// Picture first, then sound, then the file as a whole.
List<DetailSection> orderedDetails(List<DetailSection> sections) {
  const order = [
    DetailGroup.video,
    DetailGroup.audio,
    DetailGroup.file,
    DetailGroup.timecode,
    DetailGroup.subtitle,
    DetailGroup.data,
    DetailGroup.attachment,
    DetailGroup.chapters,
  ];
  return [
    for (final group in order) ...sections.where((s) => s.group == group),
  ];
}
