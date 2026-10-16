import 'package:flutter/material.dart';

import '../../core/ffmpeg/capabilities.dart';
import '../../core/media/media_info.dart';
import '../../core/scenarios/scenario.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';

/// Technical detail shown beside a plain-language label: smaller and quieter
/// (and, in the professional look, in the fixed-width font), so it informs
/// people who want it without being in the way of those who do not.
/// Technical terms on the main screen appear only through this widget; a
/// test holds the UI to that.
class TechnicalText extends StatelessWidget {
  const TechnicalText(
    this.text, {
    super.key,
    this.align,
    this.color,
    this.caption = false,
  });

  final String text;
  final TextAlign? align;

  /// Null for the usual quiet colour. Given where that would not show, such
  /// as on a chosen segment.
  final Color? color;

  /// Under a choice's label (`AV1` under "Smallest file"), where the
  /// technical name is what tells the choices apart: a little larger.
  final bool caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = color ?? theme.colorScheme.onSurfaceVariant;
    final small = theme.textTheme.labelSmall;
    // The line is as tall in the fixed-width font as in the interface font,
    // so rows are the same height in both looks.
    final lineHeight = caption ? captionLineHeight : 16.0;
    final monoSize = caption ? 11.5 : 10.0;
    return Text(
      text,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppLook.of(context).monoCaptions
          ? small?.copyWith(
              fontFamily: monoFontFamily,
              fontSize: monoSize,
              fontWeight: FontWeight.w400,
              height: lineHeight / monoSize,
              letterSpacing: 0,
              color: quiet,
            )
          : small?.copyWith(
              color: quiet,
              letterSpacing: 0.2,
              fontSize: caption ? captionFontSize : null,
              height: caption ? lineHeight / captionFontSize : null,
            ),
    );
  }
}

/// The size of a caption under a choice's label, technical or not.
const captionFontSize = 12.5;
const captionLineHeight = 17.0;

/// A typical camera file: what presets are described with before (or
/// without) any real file in the list.
const _typicalInput = MediaInfo(
  path: 'typical.mp4',
  formatName: 'mov,mp4,m4a,3gp,3g2,mj2',
  duration: Duration(minutes: 1),
  sizeBytes: 750000000,
  video: VideoStream(
    index: 0,
    codec: 'h264',
    width: 3840,
    height: 2160,
    pixFmt: 'yuv420p',
    averageFrameRate: 25,
    nominalFrameRate: 25,
  ),
  audio: [AudioStream(index: 1, codec: 'aac', channels: 2, sampleRate: 48000)],
);

ConversionPlan typicalPlan(
  Preset preset,
  OptionValues values,
  Capabilities capabilities,
) => preset.plan(_typicalInput, values, capabilities);

/// The name a format is known by: `HEVC`, `AV1`, `ProRes 422 HQ`, and the
/// graphics card maker for hardware encoders.
String? codecName(VideoAction video) {
  if (video is! VideoEncode) return null;
  final encoder = video.encoder;
  String arg(String name) {
    final index = video.args.indexOf(name);
    return index >= 0 && index + 1 < video.args.length
        ? video.args[index + 1]
        : '';
  }

  final family = switch (encoder) {
    'prores_ks' => switch (arg('-profile:v')) {
      '0' => 'ProRes Proxy',
      '1' => 'ProRes LT',
      '3' => 'ProRes 422 HQ',
      _ => 'ProRes 422',
    },
    'dnxhd' =>
      'DNxHR ${arg('-profile:v').replaceFirst('dnxhr_', '').toUpperCase()}',
    _ when encoder.contains('265') || encoder.startsWith('hevc') => 'HEVC',
    _ when encoder.contains('av1') => 'AV1',
    _ when encoder.contains('264') => 'H.264',
    _ => encoder,
  };
  final hardware = switch (encoder.split('_').last) {
    'nvenc' => 'NVIDIA',
    'qsv' => 'Intel',
    'amf' => 'AMD',
    'videotoolbox' => 'Apple',
    'vaapi' => 'VAAPI',
    _ => null,
  };
  return hardware == null ? family : '$family · $hardware';
}

/// The quality setting as encoders name it: `CRF 20`, `CQ 28`.
String? qualitySetting(VideoAction video) {
  if (video is! VideoEncode) return null;
  const names = {
    '-crf': 'CRF',
    '-cq': 'CQ',
    '-global_quality': 'ICQ',
    '-qvbr_quality_level': 'QVBR',
    '-q:v': 'Q',
  };
  for (final entry in names.entries) {
    final index = video.args.indexOf(entry.key);
    if (index >= 0 && index + 1 < video.args.length) {
      return '${entry.value} ${video.args[index + 1]}';
    }
  }
  return null;
}

/// One line saying technically what a plan does, e.g.
/// `HEVC 10-bit, CRF 20 · sound copied · MP4`.
String technicalSummary(AppLocalizations l10n, ConversionPlan plan) {
  final video = plan.video;
  final parts = <String>[];
  if (video is VideoEncode) {
    final depth = '${bitDepthOfPixFmt(video.pixFmt)}-bit';
    final quality = qualitySetting(video);
    final scale = video.filters
        .map(RegExp(r'^scale=(\d+):').firstMatch)
        .nonNulls
        .firstOrNull;
    parts.add(
      [
        '${codecName(video)} $depth',
        ?quality,
        if (scale != null) l10n.techUpTo(_lines(int.parse(scale.group(1)!))),
        if (video.filters.any((f) => f.startsWith('tonemap'))) 'HDR → SDR',
      ].join(', '),
    );
  } else if (video is VideoCopy) {
    parts.add(l10n.techPictureCopied);
  }
  final audio = plan.audio;
  parts.add(switch (audio) {
    AudioNone() => l10n.techNoSound,
    AudioCopy() => l10n.techSoundCopied,
    AudioEncode() => _audioName(audio),
  });
  parts.add(plan.extension.toUpperCase());
  return parts.join(' · ');
}

/// `1920` (a long side) as the line count people know: `1080p`.
String _lines(int longSide) => switch (longSide) {
  >= 3840 => '2160p',
  >= 1920 => '1080p',
  >= 1280 => '720p',
  _ => '${longSide}px',
};

String _audioName(AudioEncode audio) {
  final codec = audio.codec;
  if (codec.startsWith('pcm_')) {
    return 'PCM ${RegExp(r'\d+').stringMatch(codec) ?? ''}-bit';
  }
  final index = audio.args.indexOf('-b:a');
  final rate = index >= 0 ? ' ${audio.args[index + 1]}' : '';
  return switch (codec) {
    'libmp3lame' => 'MP3 VBR',
    'flac' => 'FLAC',
    _ => '${codec.toUpperCase()}$rate',
  };
}

/// What a source file is, technically: `H.265 10-bit`.
String sourceFormat(VideoStream video) {
  final name = switch (video.codec) {
    'h264' => 'H.264',
    'hevc' => 'H.265',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'prores' => 'ProRes',
    'dnxhd' => 'DNxHR',
    'mpeg4' => 'MPEG-4',
    'mpeg2video' => 'MPEG-2',
    'mjpeg' => 'MJPEG',
    'cfhd' => 'CineForm',
    _ => video.codec.toUpperCase(),
  };
  return video.bitDepth > 8 ? '$name ${video.bitDepth}-bit' : name;
}

/// The short technical name under a preset's plain label, e.g. `AV1`.
String presetCaption(
  AppLocalizations l10n,
  Preset preset,
  OptionValues values,
  Capabilities capabilities,
) {
  final plan = typicalPlan(preset, values, capabilities);
  final audio = plan.audio;
  // A kept picture can still come with its sound converted, as in Resolve
  // Studio. Which format the sound takes depends on the file, so the
  // summary under the panel names it, not this caption.
  return codecName(plan.video) ??
      (audio is AudioEncode ? l10n.techOnlySound : l10n.techNoReencode);
}

/// The short technical name under an option's plain label: the quality
/// setting (`CRF 25`), the format a size choice uses (`ProRes LT`), or the
/// resolution (`720p`). Null where the label already says it.
String? choiceCaption(
  AppLocalizations l10n,
  Preset preset,
  String optionId,
  String choice,
  OptionValues values,
  Capabilities capabilities,
) {
  final plan = typicalPlan(preset, {...values, optionId: choice}, capabilities);
  final video = plan.video;
  switch (optionId) {
    case 'quality':
      final name = codecName(video);
      final named =
          name != null &&
          (name.startsWith('ProRes') ||
              name.startsWith('DNxHR') ||
              preset.id.startsWith('resolve'));
      return named ? name : qualitySetting(video);
    case 'size':
      if (video is! VideoEncode) return null;
      final scale = video.filters
          .map(RegExp(r'^scale=(\d+):').firstMatch)
          .nonNulls
          .firstOrNull;
      return scale == null ? null : _lines(int.parse(scale.group(1)!));
    case 'mode':
      return codecName(video) ?? l10n.techNoReencode;
    // The sound format inside a file type whose name does not say it.
    case 'format' when preset.id.startsWith('audio'):
      return switch (choice) {
        'm4a' => 'AAC',
        'wav' => 'PCM',
        _ => null,
      };
    // The format alone, whatever does the encoding.
    case 'codec' when preset.id.startsWith('archive'):
      return codecName(video)?.split(' · ').first;
    // What does the encoding: the encoder library, or the graphics card's
    // maker.
    case 'speed':
      if (video is! VideoEncode) return null;
      return switch (video.encoder) {
        'libsvtav1' => 'SVT-AV1',
        'libx265' => 'x265',
        _ => codecName(video)!.split(' · ').last,
      };
    default:
      return null;
  }
}

/// What a sound track is, technically: `PCM 24-bit`, `AAC`.
String audioFormat(AudioStream audio) {
  final codec = audio.codec;
  if (codec.startsWith('pcm_')) {
    return 'PCM ${RegExp(r'\d+').stringMatch(codec) ?? ''}-bit';
  }
  return switch (codec) {
    'aac' => 'AAC',
    'mp3' => 'MP3',
    'opus' => 'Opus',
    'flac' => 'FLAC',
    'ac3' => 'AC-3',
    'eac3' => 'E-AC-3',
    'alac' => 'ALAC',
    'vorbis' => 'Vorbis',
    _ => codec.toUpperCase(),
  };
}
