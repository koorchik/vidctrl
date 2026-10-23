/// Makes a master copy of camera videos for keeping: a fraction of the
/// camera's file size, and meant to look the same as the original.
///
/// There is one quality, the highest this goal offers. The formats are set to
/// reach the same look and differ only in file size, encoding time and where
/// they play. Output is always 10-bit 4:2:0 in MP4: 10-bit avoids banding even
/// for 8-bit sources, at a size cost of a few percent. Dates, place, timecode
/// and the camera's make and model are kept.
library;

import '../ffmpeg/capabilities.dart';
import '../media/media_info.dart';
import 'blocks.dart';
import 'scenario.dart';

const archiveScenario = Scenario(id: 'archive', presets: [ArchivePreset()]);

/// Hardware encoders for the fast choice, best first. Only those of the chosen
/// format are considered.
const gpuEncoderPreference = [
  'av1_nvenc',
  'av1_qsv',
  'av1_amf',
  'hevc_nvenc',
  'hevc_qsv',
  'hevc_amf',
  'hevc_videotoolbox',
];

/// The quality numbers, set so that each way of encoding comes as close to
/// the original: an XPSNR (luma) of at least 42 dB, the level reported as
/// visually lossless, on the hardest of the clips measured, and more on the
/// others. Measured in October 2026 on 10-second 4K pieces: two of handheld
/// footage from a Nikon camera (the hardest), a phone video of a moving car
/// and a photo slideshow. On the hardest piece all four give 42.0 to 42.1 dB.
/// Those scores were taken with the copy as `xpsnr`'s first input, which
/// reads 0.3 to 0.8 dB low (`quality_meter.dart`); in the right order the
/// same files score higher, so every piece clears 42 dB.
///
/// One number cannot give the same closeness on every kind of footage. On
/// the hardest piece HEVC on the processor came out 15% larger than AV1, and
/// the graphics card's files 1.7 (AV1) and 2 (HEVC) times larger; on calm
/// footage those were 1.5, 2.4 and 3 times.
const svtAv1Crf = '35';
const x265Crf = '24';

/// The best quality the archive gives a video whose standard one falls short
/// of looking the same (`quality_search.dart`), lower being better. Below
/// this the file grows a lot for little: on a grainy film download that no
/// quality brought to the target, crf 20 gave 60% of the original's size
/// and crf 18 72%, for 0.4 more VMAF on its poorest piece. HEVC's number is
/// set by the same proportion to its standard one; it is not measured.
const svtAv1BestCrf = 20;
const x265BestCrf = 16;
const nvencAv1Cq = '32';
const nvencHevcCq = '26';

/// Apple's scale runs 0-100, higher being better, and saturates near the
/// top. Measured on an M1 in October 2026, in the right order, with the
/// pieces above and a grainy 4K clip harder than all of them: at 65 that
/// clip comes as close as with AV1 (41.2 against 41.4 dB, VMAF 98 against
/// 96) and the others score 43 dB or more. 75 gave 42.4 dB there at six
/// times AV1's size, hardly smaller than the camera's own file.
const videoToolboxQuality = '65';

/// The level a player needs for a picture of this size and frame rate, and
/// the most its main tier allows per second: 4.1 up to 1080p at 60 frames,
/// 5.1 for 4K up to 60, and so on. 4K is given 5.1 even below 30 frames,
/// as every 4K player handles it.
({String level, int megabits}) playableLevel(VideoStream video) {
  final picture = video.width * video.height;
  final samples = picture * (video.frameRate ?? 30);
  const levels = [
    ('4.1', 2228224, 133693440, 20),
    ('5.1', 8912896, 534773760, 40),
    ('5.2', 8912896, 1069547520, 60),
    ('6.1', 35651584, 2139095040, 100),
  ];
  for (final (level, maxPicture, maxSamples, megabits) in levels) {
    if (picture <= maxPicture && samples <= maxSamples) {
      return (level: level, megabits: megabits);
    }
  }
  return (level: '6.2', megabits: 160);
}

class ArchivePreset implements Preset, RaisesQuality {
  const ArchivePreset();

  @override
  String get id => 'archive.master';

  static const codec = 'codec';
  static const speed = 'speed';

  /// AV1 is the default: the smallest file for the same look. HEVC is for
  /// older phones, computers and TVs, which do not play AV1. The defaults
  /// need no thought; each choice says on the panel what it trades away.
  @override
  List<PresetOption> get options => const [
    PresetOption(id: codec, choices: ['av1', 'hevc'], defaultChoice: 'av1'),
    PresetOption(id: speed, choices: ['cpu', 'gpu'], defaultChoice: 'cpu'),
  ];

  /// Whether this FFmpeg can make AV1 at all. Common Windows builds cannot;
  /// they get HEVC, and the choice of format is not offered.
  static bool encodesAv1(Capabilities capabilities) =>
      capabilities.hasEncoder('libsvtav1');

  /// The format that will really be written: the chosen one, unless this
  /// FFmpeg cannot make it.
  static String formatFor(OptionValues values, Capabilities capabilities) {
    final chosen = const ArchivePreset().choice(values, codec);
    return chosen == 'av1' && !encodesAv1(capabilities) ? 'hevc' : chosen;
  }

  /// The hardware encoder the fast choice would use for [format] on this
  /// machine, or null when there is none and the choice is not offered.
  static String? gpuEncoder(Capabilities capabilities, String format) {
    for (final encoder in gpuEncoderPreference) {
      if (encoder.startsWith('${format}_') &&
          capabilities.hasHardwareEncoder(encoder)) {
        return encoder;
      }
    }
    return null;
  }

  @override
  ConversionPlan plan(
    MediaInfo input,
    OptionValues values,
    Capabilities capabilities,
  ) {
    final video = input.video;
    if (video == null) {
      return const ConversionPlan.unsupported([PlanNote.noVideoStream]);
    }
    final target = formatFor(values, capabilities);
    final hardware = choice(values, speed) == 'gpu'
        ? gpuEncoder(capabilities, target)
        : null;
    final encode = hardware != null
        ? _gpu(video, hardware)
        : target == 'av1'
        ? _svtAv1(video, capabilities)
        : _x265(video);
    return ConversionPlan(
      kind: PlanKind.encode,
      video: encode,
      audio: _audio(input),
      muxer: 'mp4',
      extension: 'mp4',
      nameSuffix: '_${encoderTag(encode)}',
      outputArgs: [
        if (video.isVariableFrameRate) ...constantFrameRateArgs(video),
        // Apple players only recognise HEVC under this tag.
        if (target == 'hevc') ...['-tag:v', 'hvc1'],
        // Index at the front, so the file starts playing before it has
        // fully downloaded. Without `use_metadata_tags` MP4 drops the
        // camera's make and model.
        '-movflags', '+faststart+use_metadata_tags',
        // ...but with it, the source's file type tags are copied too, and a
        // camera's MOV would make the MP4 claim to be QuickTime. The real
        // file type box is written regardless.
        for (final tag in const [
          'major_brand',
          'minor_version',
          'compatible_brands',
        ]) ...['-metadata', '$tag='],
      ],
      notes: [
        if (video.isVariableFrameRate) PlanNote.variableFrameRateFixed,
        if (video.chroma != ChromaSubsampling.yuv420) PlanNote.chromaReduced,
      ],
      cost: _cost(encode.encoder),
    );
  }

  VideoEncode _svtAv1(VideoStream video, Capabilities capabilities) {
    return VideoEncode(
      encoder: 'libsvtav1',
      pixFmt: 'yuv420p10le',
      filters: to420Filters(video, 'yuv420p10le'),
      args: [
        '-preset',
        '5',
        '-crf',
        svtAv1Crf,
        if (capabilities.svtAv1Params.isNotEmpty) ...[
          '-svtav1-params',
          capabilities.svtAv1Params,
        ],
        ...av1ChromaPositionArgs(video),
      ],
    );
  }

  VideoEncode _x265(VideoStream video) {
    return VideoEncode(
      encoder: 'libx265',
      pixFmt: 'yuv420p10le',
      filters: to420Filters(video, 'yuv420p10le'),
      args: [
        '-preset',
        'slow',
        '-crf',
        x265Crf,
        '-profile:v',
        'main10',
        '-x265-params',
        'aq-mode=3:no-sao=1:log-level=error',
      ],
    );
  }

  VideoEncode _gpu(VideoStream video, String encoder) {
    final isAv1 = encoder.startsWith('av1');
    // Hardware quality scales differ from the software CRF scale and from
    // each other; HEVC needs a lower number than AV1 for the same result.
    // The Intel and AMD numbers are not measured.
    final q = isAv1 ? 24 : 20;
    final rateControl = switch (encoder.split('_').last) {
      'nvenc' => [
        '-preset',
        'p7',
        '-tune',
        'hq',
        '-rc',
        'vbr',
        '-cq',
        isAv1 ? nvencAv1Cq : nvencHevcCq,
        '-b:v',
        '0',
        '-rc-lookahead',
        '32',
        '-spatial-aq',
        '1',
        '-temporal-aq',
        '1',
        '-b_ref_mode',
        'middle',
        ..._levelLimit(video, isAv1),
      ],
      'qsv' => [
        '-preset',
        'veryslow',
        '-global_quality',
        '$q',
        '-extbrc',
        '1',
        '-look_ahead_depth',
        '40',
      ],
      'amf' => [
        '-usage',
        'transcoding',
        '-quality',
        'high_quality',
        '-rc',
        'qvbr',
        '-qvbr_quality_level',
        '$q',
      ],
      _ => ['-q:v', videoToolboxQuality],
    };
    return VideoEncode(
      encoder: encoder,
      pixFmt: 'p010le',
      filters: to420Filters(video, 'p010le'),
      args: [
        ...rateControl,
        if (isAv1) ...av1ChromaPositionArgs(video),
        if (!isAv1) ...['-profile:v', 'main10'],
      ],
    );
  }

  /// Without a limit of its own, NVENC caps "constant quality" at a bitrate
  /// it picks, far below what detailed footage needs, and the picture falls
  /// short of the other encoders'. Set too high, it writes a level that some
  /// players refuse. So the limit is that of the level such a video needs,
  /// in the main tier, which every player of it supports.
  List<String> _levelLimit(VideoStream video, bool isAv1) {
    final (:level, :megabits) = playableLevel(video);
    return [
      '-maxrate',
      '${megabits}M',
      '-bufsize',
      '${megabits * 2}M',
      '-level',
      level,
      '-tier',
      isAv1 ? '0' : 'main',
    ];
  }

  /// AAC that is already reasonably small is kept as is: re-encoding lossy
  /// audio only loses quality.
  AudioAction _audio(MediaInfo input) {
    if (input.audio.isEmpty) return const AudioCopy();
    final keep = input.audio.every(
      (a) => a.codec == 'aac' && (a.bitRate ?? 0) <= keepAacUpTo,
    );
    return keep ? const AudioCopy() : highQualityAac(input);
  }

  @override
  QualityRange? qualityRange(ConversionPlan plan) => switch (plan.video) {
    VideoEncode(encoder: 'libsvtav1') => QualityRange(
      standard: int.parse(svtAv1Crf),
      best: svtAv1BestCrf,
    ),
    VideoEncode(encoder: 'libx265') => QualityRange(
      standard: int.parse(x265Crf),
      best: x265BestCrf,
    ),
    _ => null,
  };

  @override
  ConversionPlan withQuality(
    ConversionPlan plan,
    int? value, {
    bool belowTarget = false,
  }) {
    final video = plan.video;
    if (video is! VideoEncode) return plan;
    final at = video.args.indexOf('-crf');
    final encode = value == null || at < 0 || qualityRange(plan) == null
        ? video
        : VideoEncode(
            encoder: video.encoder,
            pixFmt: video.pixFmt,
            filters: video.filters,
            args: [...video.args]..[at + 1] = '$value',
          );
    return plan.withVideo(
      encode,
      nameSuffix:
          '_${encoderTag(encode)}${belowTarget ? belowTargetMarker : ''}',
    );
  }

  ResourceCost _cost(String encoder) => switch (encoder) {
    'libsvtav1' => const ResourceCost(cpuThreads: 12),
    'libx265' => const ResourceCost(cpuThreads: 16),
    _ => const ResourceCost(cpuThreads: 3, usesGpuEncoder: true),
  };
}
