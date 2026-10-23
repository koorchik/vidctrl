import '../../core/ffmpeg/command_builder.dart';
import '../../core/output/output_namer.dart';
import '../../core/scenarios/registry.dart';
import '../../core/scenarios/scenario.dart';

/// Whether a job converts the whole video or a short piece of it.
enum SampleChoice { none, start, middle }

/// How long a sample is.
const sampleLength = Duration(seconds: 10);

/// What to do with a video: a goal (preset), its options, and whether to make
/// only a sample. A queued job keeps the recipe it was added with.
class Recipe {
  const Recipe({
    required this.presetId,
    this.values = const {},
    this.sample = SampleChoice.none,
  });

  final String presetId;
  final OptionValues values;
  final SampleChoice sample;

  bool get isSample => sample != SampleChoice.none;

  Recipe copyWith({
    String? presetId,
    OptionValues? values,
    SampleChoice? sample,
  }) => Recipe(
    presetId: presetId ?? this.presetId,
    values: values ?? this.values,
    sample: sample ?? this.sample,
  );

  /// The same goal and options for the whole video.
  Recipe withoutSample() => copyWith(sample: SampleChoice.none);

  /// Identifies the goal and options, not the sample choice: a sample and a
  /// whole-video conversion with the same goal share expected sizes. Options
  /// count as the preset will apply them, so a default chosen again is the
  /// same goal as one never changed.
  String get goalKey {
    final preset = findPreset(presetId);
    final applied = preset == null
        ? values
        : {for (final o in preset.options) o.id: preset.choice(values, o.id)};
    final entries = applied.entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    return '$presetId|${entries.join(',')}';
  }

  @override
  bool operator ==(Object other) =>
      other is Recipe && other.goalKey == goalKey && other.sample == sample;

  @override
  int get hashCode => Object.hash(goalKey, sample);
}

/// The piece of a video of [duration] that a sample job converts, or null
/// for the whole video.
SampleRange? sampleRangeFor(SampleChoice choice, Duration duration) {
  if (choice == SampleChoice.none) return null;
  final length = duration < sampleLength ? duration : sampleLength;
  final start = choice == SampleChoice.middle
      ? (duration - length) * 0.5
      : Duration.zero;
  return SampleRange(start: start, length: length);
}

/// Added to a sample's file name, after the settings tag.
String sampleSuffix(SampleChoice choice) =>
    choice == SampleChoice.middle ? '_sample10s-mid' : '_sample10s';

bool sameOutput(OutputSettings a, OutputSettings b) =>
    a.mode == b.mode &&
    a.subfolderName == b.subfolderName &&
    (a.mode != OutputMode.customFolder || a.customDir == b.customDir);
