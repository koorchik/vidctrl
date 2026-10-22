/// Makes the smallest file that is still decent to watch, for videos kept
/// only in case they are needed again: recordings of video calls and other
/// work videos. Unlike the archive, it gives up detail for size.
///
/// AV1 at most 1080p and 30 frames a second, with sound for speech. HDR is
/// mapped to ordinary video, which is what such recordings are watched as.
library;

import '../ffmpeg/capabilities.dart';
import '../media/media_info.dart';
import 'blocks.dart';
import 'scenario.dart';

const saveSpaceScenario = Scenario(id: 'space', presets: [SaveSpacePreset()]);

/// The quality number, set so that the hardest footage measured stays above
/// VMAF 91: good to watch, fine detail a little softened. Measured in
/// October 2026 on 10-second pieces, against the source made 1080p the same
/// way. A 4K family video from a camera (HEVC, 20 Mbit/s; grass, leaves and
/// smoke) gave VMAF 91.9 to 93.7 at 0.85 to 2.4 Mbit/s, a 23rd to an 8th of
/// the source; a barbecue piece of it about 970 KB for 10 seconds with the
/// sound, where the archive makes 4.3 MB. A Google Meet recording (1080p
/// H.264 at 550 kbit/s) has no detail left to lose: it comes out at about
/// nine tenths of its size.
///
/// 48 gave VMAF 90.1 on the hardest piece at four fifths of the size; 60,
/// first set on the recording alone (a third of its size there), gave 81.5,
/// the grass smeared and the smoke blotchy. One number has to suit all; the
/// hardest footage decides. A slower preset (3 or 4) gained 0.1 to 0.3 at
/// the same size in one and a half to two times the time.
const saveSpaceCrf = '43';

/// Sound for speech: transparent for voices at a fraction of a call's
/// picture. AAC at or below it is kept as it is.
const speechAacBitRate = 96000;

class SaveSpacePreset implements Preset {
  const SaveSpacePreset();

  @override
  String get id => 'space.small';

  @override
  List<PresetOption> get options => const [];

  /// The longest side a result may have: 1080p, landscape or portrait.
  static const longSide = 1920;

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
    final canToneMap =
        capabilities.hasFilter('zscale') && capabilities.hasFilter('tonemap');
    final toneMap = video.color.isHdr && canToneMap;
    final sourceLongSide = video.width > video.height
        ? video.width
        : video.height;
    final resize = sourceLongSide > longSide;

    // Every changed picture ends in 4:2:0 with its colour samples where
    // MPEG puts them: FFmpeg's own conversion puts them elsewhere.
    final picture = [
      if (toneMap) ..._toneMapToSdr,
      if (resize)
        // Fits inside a square of the long side, so landscape and portrait
        // videos are both limited correctly. Never enlarges.
        'scale=$longSide:$longSide:force_original_aspect_ratio=decrease:'
            'force_divisible_by=2:flags=lanczos+accurate_rnd:'
            'out_chroma_loc=left'
      else if (toneMap || video.chroma != ChromaSubsampling.yuv420)
        'scale=flags=lanczos+accurate_rnd:out_chroma_loc=left',
    ];
    if (picture.isNotEmpty) picture.add('format=$_pixFmt');
    final halved = _halvedFrameRate(video);

    final encode = VideoEncode(
      encoder: 'libsvtav1',
      pixFmt: _pixFmt,
      // Frames are dropped first, so the others have fewer to work on.
      filters: [if (halved != null) 'fps=$halved', ...picture],
      args: [
        '-preset',
        '5',
        '-crf',
        saveSpaceCrf,
        if (capabilities.svtAv1Params.isNotEmpty) ...[
          '-svtav1-params',
          capabilities.svtAv1Params,
        ],
        if (picture.isEmpty)
          ...av1ChromaPositionArgs(video)
        else ...[
          '-bsf:v',
          'av1_metadata=chroma_sample_position=vertical',
        ],
      ],
    );
    return ConversionPlan(
      kind: PlanKind.encode,
      video: encode,
      audio: _audio(input),
      muxer: 'mp4',
      extension: 'mp4',
      nameSuffix: '_${encoderTag(encode)}',
      outputArgs: [
        if (halved == null && video.isVariableFrameRate)
          ...constantFrameRateArgs(video),
        // Index at the front, so the file starts playing before it has
        // fully downloaded.
        '-movflags', '+faststart',
      ],
      notes: [
        if (video.color.isHdr)
          canToneMap ? PlanNote.hdrToneMapped : PlanNote.hdrNotConverted,
        if (video.isVariableFrameRate) PlanNote.variableFrameRateFixed,
      ],
      cost: const ResourceCost(cpuThreads: 12),
    );
  }

  /// 10-bit: at the same size as 8-bit, measured a little closer to the
  /// original (0.2 to 0.4 dB), at about a sixth more time.
  static const _pixFmt = 'yuv420p10le';

  /// HDR shown as ordinary video looks grey and washed out, so brightness and
  /// colour are mapped into the standard range first.
  static const _toneMapToSdr = [
    'zscale=t=linear:npl=100',
    'format=gbrpf32le',
    'zscale=p=bt709',
    'tonemap=tonemap=hable:desat=0',
    'zscale=t=bt709:m=bt709:r=tv',
  ];

  /// More than 30 frames a second is halved until it is not: 60 becomes 30,
  /// 50 becomes 25. Smooth motion is not what such a video is kept for. Null
  /// for 30 and less, whose irregular timing is made constant as in the
  /// archive. The `fps` filter, not `-r`: the output option added two frames
  /// at the end of a 2-second clip.
  String? _halvedFrameRate(VideoStream video) {
    final fps = video.frameRate;
    if (fps == null || fps <= 31) return null;
    var target = fps;
    while (target > 31) {
      target /= 2;
    }
    return nearestStandardFrameRate(target);
  }

  AudioAction _audio(MediaInfo input) {
    if (input.audio.isEmpty) return const AudioCopy();
    final keep = input.audio.every(
      (a) =>
          a.codec == 'aac' &&
          a.channels <= 2 &&
          (a.bitRate ?? speechAacBitRate + 1) <= speechAacBitRate,
    );
    if (keep) return const AudioCopy();
    final surround = input.audio.any((a) => a.channels > 2);
    return AudioEncode(
      codec: 'aac',
      args: [
        '-b:a',
        '96k',
        if (surround) ...['-ac', '2'],
      ],
    );
  }
}
