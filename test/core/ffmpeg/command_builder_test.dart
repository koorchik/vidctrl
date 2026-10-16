import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/command_builder.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

void main() {
  const audioFix = ConversionPlan(
    kind: PlanKind.audioOnly,
    audio: AudioEncode(codec: 'pcm_s24le'),
    muxer: 'mov',
    extension: 'mov',
  );

  List<String> build(ConversionPlan plan, {SampleRange? sample}) =>
      buildFfmpegArgs(
        input: '/videos/clip.mp4',
        output: '/videos/Converted/.clip.mov.part',
        plan: plan,
        sample: sample,
      );

  test('an audio fix copies the video and names the muxer explicitly', () {
    expect(build(audioFix), [
      '-hide_banner',
      '-y',
      '-loglevel',
      'error',
      '-nostats',
      '-progress',
      'pipe:1',
      '-i',
      'file:/videos/clip.mp4',
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-map_metadata',
      '0',
      '-c:v',
      'copy',
      '-c:a',
      'pcm_s24le',
      '-f',
      'mov',
      'file:/videos/Converted/.clip.mov.part',
    ]);
  });

  test('an encode places filters and pixel format after encoder options', () {
    const plan = ConversionPlan(
      kind: PlanKind.encode,
      video: VideoEncode(
        encoder: 'libsvtav1',
        pixFmt: 'yuv420p10le',
        args: ['-preset', '5', '-crf', '25'],
        filters: ['scale=flags=lanczos+accurate_rnd', 'format=yuv420p10le'],
      ),
      audio: AudioEncode(codec: 'aac', args: ['-b:a', '256k']),
      muxer: 'mp4',
      extension: 'mp4',
      outputArgs: ['-movflags', '+faststart'],
    );

    expect(
      build(plan),
      containsAllInOrder([
        '-c:v',
        'libsvtav1',
        '-preset',
        '5',
        '-crf',
        '25',
        '-vf',
        'scale=flags=lanczos+accurate_rnd,format=yuv420p10le',
        '-pix_fmt',
        'yuv420p10le',
        '-c:a',
        'aac',
        '-b:a',
        '256k',
        '-movflags',
        '+faststart',
        '-f',
        'mp4',
      ]),
    );
  });

  test('a sample seeks before the input and limits the length after it', () {
    final args = build(
      audioFix,
      sample: const SampleRange(
        start: Duration(seconds: 90),
        length: Duration(seconds: 10),
      ),
    );

    expect(
      args,
      containsAllInOrder([
        '-ss',
        '90.000',
        '-i',
        'file:/videos/clip.mp4',
        '-t',
        '10.000',
      ]),
    );
  });

  test('a sample from the very start does not seek', () {
    final args = build(
      audioFix,
      sample: const SampleRange(length: Duration(seconds: 10)),
    );

    expect(args, isNot(contains('-ss')));
    expect(args, containsAllInOrder(['-t', '10.000']));
  });

  test('a sample differs from the full run only by its time range', () {
    final full = build(audioFix);
    final sample = build(
      audioFix,
      sample: const SampleRange(
        start: Duration(seconds: 5),
        length: Duration(seconds: 10),
      ),
    );
    final withoutRange = [...sample]
      ..removeRange(sample.indexOf('-t'), sample.indexOf('-t') + 2)
      ..removeRange(sample.indexOf('-ss'), sample.indexOf('-ss') + 2);

    expect(withoutRange, full);
  });

  test('audio extraction leaves the picture out', () {
    const plan = ConversionPlan(
      kind: PlanKind.audioOnly,
      video: VideoNone(),
      muxer: 'ipod',
      extension: 'm4a',
    );
    final args = build(plan);

    expect(args, contains('-vn'));
    expect(args, isNot(contains('0:v:0')));
    expect(args, isNot(contains('-c:v')));
  });

  test('a privacy plan drops the source metadata', () {
    const plan = ConversionPlan(
      kind: PlanKind.remux,
      muxer: 'mp4',
      extension: 'mp4',
      keepMetadata: false,
    );

    expect(build(plan), containsAllInOrder(['-map_metadata', '-1']));
  });

  test(
    'file names with spaces, colons or a leading dash stay one argument',
    () {
      final args = buildFfmpegArgs(
        input: '/videos/-trip: day 1.mp4',
        output: '/videos/out.part',
        plan: audioFix,
      );

      expect(args, contains('file:/videos/-trip: day 1.mp4'));
    },
  );

  test(
    'the version shown to people leaves out what the app adds for itself',
    () {
      final args = buildFfmpegArgs(
        input: '/videos/clip.mp4',
        output: '/videos/Converted/clip.mov',
        plan: audioFix,
        forDisplay: true,
      );

      expect(args, isNot(contains('-progress')));
      expect(args, isNot(contains('-y')));
      expect(args, containsAllInOrder(['-i', '/videos/clip.mp4']));
      expect(args.last, '/videos/Converted/clip.mov');
    },
  );

  test('a shown path keeps its protection when its name could mislead', () {
    final args = buildFfmpegArgs(
      input: '/videos/-odd: name.mp4',
      output: '/videos/out.mov',
      plan: audioFix,
      forDisplay: true,
    );

    expect(args, contains('file:/videos/-odd: name.mp4'));
  });
}
