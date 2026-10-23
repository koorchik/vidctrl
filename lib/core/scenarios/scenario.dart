import '../ffmpeg/capabilities.dart';
import '../media/media_info.dart';

/// A goal the user can pick ("Edit in Resolve", "Make it small"). Adding a
/// scenario means writing one file with its presets and listing it in
/// `registry.dart`; the UI renders presets and their options generically.
class Scenario {
  const Scenario({required this.id, required this.presets});

  final String id;
  final List<Preset> presets;
}

/// One way of reaching a scenario's goal. A preset does not hold a fixed
/// command line: it looks at each file and decides the least work that gets
/// the file to the goal.
abstract interface class Preset {
  /// Stable identifier, also the key for translated texts, e.g.
  /// `resolve.studio`.
  String get id;

  List<PresetOption> get options;

  ConversionPlan plan(
    MediaInfo input,
    OptionValues values,
    Capabilities capabilities,
  );
}

/// A preset that gives one video a better quality than its standard one
/// when measuring shows the standard one falls short of looking the same.
abstract interface class RaisesQuality {
  /// The quality numbers [plan]'s encoder can be given, from the plan's own
  /// (the poorest allowed) to the best worth its size. Null where the encoder
  /// has none to change, as on a graphics card.
  QualityRange? qualityRange(ConversionPlan plan);

  /// [plan] encoding at [value], or at its own quality when null. With
  /// [belowTarget] the file name says the result needs a look: even the
  /// best quality tried fell short.
  ConversionPlan withQuality(
    ConversionPlan plan,
    int? value, {
    bool belowTarget = false,
  });
}

/// The quality numbers a search may try, lower being better, as with every
/// constant-rate factor.
class QualityRange {
  const QualityRange({required this.standard, required this.best});

  /// The plan's own number: the poorest allowed.
  final int standard;

  /// The best (lowest) number tried.
  final int best;
}

/// Ends the file name of a result that fell short of looking the same even
/// at the best quality tried: `clip_av1-crf20-check.mp4`.
const belowTargetMarker = '-check';

typedef OptionValues = Map<String, String>;

/// A choice the user can make within a preset. The UI shows it as a segmented
/// control and looks up labels by `<preset id>.<option id>.<choice>`.
class PresetOption {
  const PresetOption({
    required this.id,
    required this.choices,
    required this.defaultChoice,
    this.advanced = false,
  });

  final String id;
  final List<String> choices;
  final String defaultChoice;

  /// Hidden behind the "advanced" disclosure.
  final bool advanced;
}

extension PresetOptionValues on Preset {
  /// The chosen value for [optionId], falling back to the option's default
  /// when nothing valid was chosen.
  String choice(OptionValues values, String optionId) {
    final option = options.firstWhere((o) => o.id == optionId);
    final value = values[optionId];
    return value != null && option.choices.contains(value)
        ? value
        : option.defaultChoice;
  }
}

/// How much work a plan involves, from none to a full re-encode. Shown to the
/// user as the per-file status before anything starts.
enum PlanKind {
  /// The file already meets the goal. Nothing is written.
  skip,

  /// Streams are moved to another container untouched.
  remux,

  /// Video is kept untouched; only audio is converted.
  audioOnly,

  /// Video is re-encoded.
  encode,

  /// The preset cannot do anything useful with this file.
  unsupported,
}

sealed class VideoAction {
  const VideoAction();
}

final class VideoCopy extends VideoAction {
  const VideoCopy();
}

/// The output has no picture (audio extraction).
final class VideoNone extends VideoAction {
  const VideoNone();
}

final class VideoEncode extends VideoAction {
  const VideoEncode({
    required this.encoder,
    required this.pixFmt,
    this.args = const [],
    this.filters = const [],
  });

  /// FFmpeg encoder name, e.g. `libsvtav1`.
  final String encoder;
  final String pixFmt;

  /// Encoder options, already split into arguments.
  final List<String> args;

  /// Entries of the `-vf` filter chain, in order.
  final List<String> filters;
}

sealed class AudioAction {
  const AudioAction();
}

final class AudioCopy extends AudioAction {
  const AudioCopy();
}

final class AudioNone extends AudioAction {
  const AudioNone();
}

final class AudioEncode extends AudioAction {
  const AudioEncode({required this.codec, this.args = const []});

  final String codec;
  final List<String> args;
}

/// Things worth telling the user about a plan. Codes rather than sentences so
/// the UI can translate them.
enum PlanNote {
  alreadyCompatible,
  noVideoStream,
  variableFrameRateFixed,

  /// Resolve Studio decodes H.265 4:2:2 in hardware only on recent NVIDIA
  /// cards; elsewhere on the processor, which can be too slow to play.
  hevc422MayPlayChoppily,

  /// Compact but harder to edit than ProRes; not yet confirmed in Resolve Free.
  experimentalAv1Intermediate,

  /// Chroma is reduced from 4:2:2 or 4:4:4 to 4:2:0.
  chromaReduced,
  noAudioStream,

  /// HDR brightness and colour are mapped down to ordinary video.
  hdrToneMapped,

  /// HDR source, but this FFmpeg build cannot tone-map it.
  hdrNotConverted,

  /// The sound has to be converted to fit the chosen file type.
  audioConvertedToFit,

  /// The chosen file type cannot hold this kind of picture.
  containerCannotHold,
}

/// What the scheduler needs to know to run jobs side by side without
/// overloading the machine.
class ResourceCost {
  const ResourceCost({required this.cpuThreads, this.usesGpuEncoder = false});

  /// Threads one such job keeps busy, roughly.
  final double cpuThreads;
  final bool usesGpuEncoder;

  static const copy = ResourceCost(cpuThreads: 1);
}

/// The decision a preset made for one file: enough to build the FFmpeg
/// command, explain it to the user, and schedule it.
class ConversionPlan {
  const ConversionPlan({
    required this.kind,
    this.video = const VideoCopy(),
    this.audio = const AudioCopy(),
    this.muxer = '',
    this.extension = '',
    this.nameSuffix = '',
    this.outputArgs = const [],
    this.keepMetadata = true,
    this.keepFileDate = true,
    this.firstAudioOnly = false,
    this.notes = const [],
    this.estimatedBytes,
    this.cost = ResourceCost.copy,
  });

  const ConversionPlan.skip({this.notes = const [PlanNote.alreadyCompatible]})
    : kind = PlanKind.skip,
      video = const VideoCopy(),
      audio = const AudioCopy(),
      muxer = '',
      extension = '',
      nameSuffix = '',
      outputArgs = const [],
      keepMetadata = true,
      keepFileDate = true,
      firstAudioOnly = false,
      estimatedBytes = null,
      cost = ResourceCost.copy;

  /// [notes] says why, e.g. `[PlanNote.noVideoStream]`.
  const ConversionPlan.unsupported(this.notes)
    : kind = PlanKind.unsupported,
      video = const VideoCopy(),
      audio = const AudioCopy(),
      muxer = '',
      extension = '',
      nameSuffix = '',
      outputArgs = const [],
      keepMetadata = true,
      keepFileDate = true,
      firstAudioOnly = false,
      estimatedBytes = null,
      cost = ResourceCost.copy;

  final PlanKind kind;
  final VideoAction video;
  final AudioAction audio;

  /// FFmpeg muxer name (`mov`, `mp4`, `matroska`), passed explicitly because
  /// the output is written under a temporary name.
  final String muxer;

  /// File extension without the dot.
  final String extension;

  /// Appended to the source file name, e.g. `_resolve`.
  final String nameSuffix;

  /// Muxer and stream options that follow the codec options.
  final List<String> outputArgs;

  /// Carry titles, dates and timecode over from the source.
  final bool keepMetadata;

  /// Give the output the source file's modification time.
  final bool keepFileDate;

  /// Take only the first sound track instead of all of them. Audio-only
  /// file types hold a single track.
  final bool firstAudioOnly;

  final List<PlanNote> notes;

  /// Expected output size when it can be known up front (copies and
  /// fixed-bitrate codecs). Null for quality-targeted encodes.
  final int? estimatedBytes;

  final ResourceCost cost;

  /// True when there is something to run.
  bool get producesOutput =>
      kind != PlanKind.skip && kind != PlanKind.unsupported;

  /// The same plan with a different picture, and the name that goes with it.
  ConversionPlan withVideo(VideoAction video, {String? nameSuffix}) =>
      ConversionPlan(
        kind: kind,
        video: video,
        audio: audio,
        muxer: muxer,
        extension: extension,
        nameSuffix: nameSuffix ?? this.nameSuffix,
        outputArgs: outputArgs,
        keepMetadata: keepMetadata,
        keepFileDate: keepFileDate,
        firstAudioOnly: firstAudioOnly,
        notes: notes,
        estimatedBytes: estimatedBytes,
        cost: cost,
      );

  /// The same plan with different sound handling.
  ConversionPlan withAudio(AudioAction audio) => ConversionPlan(
    kind: kind,
    video: video,
    audio: audio,
    muxer: muxer,
    extension: extension,
    nameSuffix: nameSuffix,
    outputArgs: outputArgs,
    keepMetadata: keepMetadata,
    keepFileDate: keepFileDate,
    firstAudioOnly: firstAudioOnly,
    notes: notes,
    estimatedBytes: estimatedBytes,
    cost: cost,
  );
}
