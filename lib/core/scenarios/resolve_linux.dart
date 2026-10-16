/// Makes footage importable into DaVinci Resolve on Linux.
///
/// Codec support starts from Blackmagic's "Supported Formats and Codecs"
/// list for Resolve 21.1 (Linux section):
/// - Neither edition decodes AAC audio.
/// - The free edition decodes no H.264 or H.265.
/// - Both decode AV1, VP9, ProRes, DNxHR, MPEG-4, MJPEG, CineForm and FFV1.
///
/// Checked in Resolve Studio 21.1.1 on Linux with an RTX 5080, by importing
/// FFmpeg-made files and comparing Resolve's renders with the sources:
/// - Every video codec above decodes, in MOV, MP4, MKV, WebM and MXF,
///   including 10-bit AV1 and VP9 and 10-bit 4:2:2 H.264 and H.265. With
///   hardware decoding turned off, H.264, H.265 (4:2:2 too), AV1 and VP9
///   still decode, on the processor.
/// - PCM of every kind and FLAC play. AAC, E-AC-3 and Vorbis are silent.
/// - AC-3 is silent in MOV and MP4 and comes out loud and distorted from MKV.
/// - Opus plays from MP4 but is silent in MKV and WebM.
/// - AVI does not import at all. MPEG-4 Part 2 with B-frames moved from an
///   AVI into a MOV does not decode, though the same stream written into a
///   MOV by an encoder does.
/// - A copied picture that starts after the sound (MPEG-TS, MKV) gets an
///   edit list of an empty edit and then the B-frame delay. Resolve applies
///   the delay twice and shows the picture up to two frames early, out of
///   sync with the sound; negative composition offsets avoid the delay.
/// The free edition is not checked yet.
library;

import '../ffmpeg/capabilities.dart';
import '../media/media_info.dart';
import 'blocks.dart';
import 'scenario.dart';

const resolveLinuxScenario = Scenario(
  id: 'resolve',
  presets: [ResolveLinuxPreset.studio, ResolveLinuxPreset.free],
);

enum ResolveEdition { studio, free }

const _freeVideoCodecs = {
  'av1',
  'vp9',
  'prores',
  'dnxhd',
  'mpeg4',
  'mpeg2video',
  'mjpeg',
  'cfhd',
  'ffv1',
};

const _studioVideoCodecs = {..._freeVideoCodecs, 'h264', 'hevc'};

/// Whether Resolve plays [track] from [input] as is. MP3 is left out on
/// purpose: only constant bitrate MP3 is supported, and most MP3 audio is
/// not.
bool _audioReadable(MediaInfo input, AudioStream track) =>
    track.isPcm ||
    track.codec == 'flac' ||
    (track.codec == 'opus' && input.isMovFamily);

/// FFmpeg cannot write these into a MOV, so they go to MP4 with FLAC audio.
const _mp4OnlyVideoCodecs = {'av1', 'vp9'};

/// Keeps a copied picture in sync with the sound in Resolve (see the top of
/// this file). AVI has no presentation times to offset, and its pictures
/// arrive in order without this.
List<String> _copyArgs(MediaInfo input) =>
    input.isAvi ? const [] : const ['-movflags', '+negative_cts_offsets'];

class ResolveLinuxPreset implements Preset {
  const ResolveLinuxPreset._(this.id, this.edition);

  static const studio = ResolveLinuxPreset._(
    'resolve.studio',
    ResolveEdition.studio,
  );
  static const free = ResolveLinuxPreset._('resolve.free', ResolveEdition.free);

  @override
  final String id;
  final ResolveEdition edition;

  static const convertVideo = 'convertVideo';
  static const quality = 'quality';
  static const codec = 'codec';

  @override
  List<PresetOption> get options => [
    if (edition == ResolveEdition.studio)
      // For computers without an NVIDIA card, where Studio decodes
      // H.264/H.265 on the processor and may play them choppily.
      const PresetOption(
        id: convertVideo,
        choices: ['no', 'yes'],
        defaultChoice: 'no',
      ),
    const PresetOption(
      id: quality,
      choices: ['smallest', 'smaller', 'balanced', 'best'],
      defaultChoice: 'balanced',
    ),
    const PresetOption(
      id: codec,
      choices: ['prores', 'dnxhr'],
      defaultChoice: 'prores',
      advanced: true,
    ),
  ];

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

    final forceConvert =
        edition == ResolveEdition.studio &&
        choice(values, convertVideo) == 'yes';
    final decodable = forceConvert || edition == ResolveEdition.free
        ? _freeVideoCodecs
        : _studioVideoCodecs;
    final keepVideo =
        decodable.contains(video.codec) &&
        !video.isVariableFrameRate &&
        !(input.isAvi && video.codec == 'mpeg4');

    if (!keepVideo) return _encodePlan(input, video, values, capabilities);

    final notes = [
      if (video.codec == 'hevc' && video.chroma == ChromaSubsampling.yuv422)
        PlanNote.hevc422MayPlayChoppily,
    ];
    final audioReadable = input.audio.every((a) => _audioReadable(input, a));
    final containerReadable =
        input.isMovFamily || input.isMatroska || input.isMxf;
    if (audioReadable && containerReadable) {
      return ConversionPlan.skip(notes: [PlanNote.alreadyCompatible, ...notes]);
    }

    final allPcm = input.audio.every((a) => a.isPcm);
    if (_mp4OnlyVideoCodecs.contains(video.codec)) {
      final keepAudio = input.audio.every(
        (a) => a.codec == 'flac' || a.codec == 'opus',
      );
      return ConversionPlan(
        kind: keepAudio ? PlanKind.remux : PlanKind.audioOnly,
        audio: keepAudio ? const AudioCopy() : flacAudio,
        muxer: 'mp4',
        extension: 'mp4',
        nameSuffix: _suffix,
        outputArgs: _copyArgs(input),
        notes: notes,
        // FLAC roughly halves PCM; close enough for a pre-start estimate.
        estimatedBytes:
            sourceVideoBytes(input) +
            (keepAudio ? sourceAudioBytes(input) : pcmBytes(input) ~/ 2),
      );
    }
    return ConversionPlan(
      kind: allPcm ? PlanKind.remux : PlanKind.audioOnly,
      audio: allPcm ? const AudioCopy() : pcmAudio,
      muxer: 'mov',
      extension: 'mov',
      nameSuffix: _suffix,
      outputArgs: _copyArgs(input),
      notes: notes,
      estimatedBytes:
          sourceVideoBytes(input) +
          (allPcm ? sourceAudioBytes(input) : pcmBytes(input)),
    );
  }

  static const _suffix = '_resolve';

  ConversionPlan _encodePlan(
    MediaInfo input,
    VideoStream video,
    OptionValues values,
    Capabilities capabilities,
  ) {
    final level = choice(values, quality);
    final frameRate = video.isVariableFrameRate
        ? constantFrameRateArgs(video)
        : const <String>[];
    final notes = [
      if (video.isVariableFrameRate) PlanNote.variableFrameRateFixed,
    ];

    if (level == 'smallest') {
      return _av1Plan(input, video, capabilities, frameRate, notes);
    }

    final intermediate = choice(values, codec) == 'dnxhr'
        ? _dnxhr(video, level)
        : _prores(level);
    return ConversionPlan(
      kind: PlanKind.encode,
      video: VideoEncode(
        encoder: intermediate.encoder,
        pixFmt: intermediate.pixFmt,
        args: intermediate.args,
      ),
      audio: pcmAudio,
      muxer: 'mov',
      extension: 'mov',
      nameSuffix: '_${intermediate.tag}',
      outputArgs: frameRate,
      notes: notes,
      estimatedBytes:
          fixedRateVideoBytes(input, intermediate.megabitsAtUhd30) +
          pcmBytes(input),
      cost: ResourceCost(cpuThreads: intermediate.cpuThreads),
    );
  }

  /// A compact intermediate for users short on disk space. Long-GOP AV1 is
  /// heavier to scrub than ProRes, so a keyframe is forced every second.
  ConversionPlan _av1Plan(
    MediaInfo input,
    VideoStream video,
    Capabilities capabilities,
    List<String> frameRate,
    List<PlanNote> notes,
  ) {
    final gop = (video.frameRate ?? 30).round().toString();
    final useGpu = capabilities.hasHardwareEncoder('av1_nvenc');
    final encode = useGpu
        ? VideoEncode(
            encoder: 'av1_nvenc',
            pixFmt: 'p010le',
            args: [
              '-preset',
              'p6',
              '-tune',
              'hq',
              '-rc',
              'vbr',
              '-cq',
              '24',
              '-b:v',
              '0',
              '-g',
              gop,
            ],
          )
        : VideoEncode(
            encoder: 'libsvtav1',
            pixFmt: 'yuv420p10le',
            args: ['-preset', '8', '-crf', '22', '-g', gop],
          );
    return ConversionPlan(
      kind: PlanKind.encode,
      video: encode,
      audio: flacAudio,
      muxer: 'mp4',
      extension: 'mp4',
      nameSuffix: '_${encoderTag(encode)}',
      outputArgs: frameRate,
      notes: [...notes, PlanNote.experimentalAv1Intermediate],
      cost: useGpu
          ? const ResourceCost(cpuThreads: 3, usesGpuEncoder: true)
          : const ResourceCost(cpuThreads: 12),
    );
  }
}

class _Intermediate {
  const _Intermediate({
    required this.encoder,
    required this.pixFmt,
    required this.args,
    required this.megabitsAtUhd30,
    required this.cpuThreads,
    required this.tag,
  });

  /// For the file name: `prores-hq`, `dnxhr-hqx`.
  final String tag;
  final String encoder;
  final String pixFmt;
  final List<String> args;
  final double megabitsAtUhd30;
  final double cpuThreads;
}

/// ProRes is 10-bit at every size tier, so one family serves 8-bit and 10-bit
/// sources alike. Bitrates are Apple's published targets.
_Intermediate _prores(String level) {
  final (profile, megabits, tag) = switch (level) {
    'best' => ('3', 884.0, 'prores-hq'),
    'smaller' => ('1', 410.0, 'prores-lt'),
    _ => ('2', 589.0, 'prores422'),
  };
  return _Intermediate(
    tag: tag,
    encoder: 'prores_ks',
    pixFmt: 'yuv422p10le',
    args: ['-profile:v', profile, '-vendor', 'apl0'],
    megabitsAtUhd30: megabits,
    cpuThreads: 24,
  );
}

/// DNxHR has no small 10-bit tier: HQX is the only 10-bit 4:2:2 profile, so
/// 10-bit sources always get it.
_Intermediate _dnxhr(VideoStream video, String level) {
  final tenBit = video.bitDepth > 8;
  final (profile, megabits) = switch ((tenBit, level)) {
    (true, _) => ('dnxhr_hqx', 833.0),
    (false, 'smaller') => ('dnxhr_sq', 551.0),
    (false, _) => ('dnxhr_hq', 833.0),
  };
  return _Intermediate(
    tag: profile.replaceFirst('dnxhr_', 'dnxhr-'),
    encoder: 'dnxhd',
    pixFmt: tenBit ? 'yuv422p10le' : 'yuv422p',
    args: ['-profile:v', profile],
    megabitsAtUhd30: megabits,
    cpuThreads: 6,
  );
}
