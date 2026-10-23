import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/control/views.dart';
import 'package:vidctrl/core/control/words.dart';

Map<String, Object?> _through(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  test('every view survives JSON', () {
    final job = JobView(
      id: 3,
      videoId: 1,
      path: '/videos/a.mov',
      goal: 'archive.master',
      options: {'speed': 'fast'},
      status: 'done',
      outputPath: '/videos/Converted/a_av1-crf35.mp4',
      outputBytes: 10,
      quality: QualityView(outcome: 'belowTarget', value: 20, share: .4),
      needsALook: true,
      errorLines: const [],
    );
    expect(JobView.fromJson(_through(job.toJson())).toJson(), job.toJson());

    final video = VideoView(
      id: 1,
      path: '/videos/a.mov',
      status: 'ready',
      sizeBytes: 1000,
      durationSeconds: 12.5,
      width: 3840,
      height: 2160,
      videoCodec: 'hevc',
      audioCodecs: const ['aac'],
      hdr: true,
      preview: GoalPreview(
        goal: 'archive.master',
        plan: 'encode',
        expectedBytes: 100,
        measured: true,
        measuring: false,
        closeness: 'same',
      ),
    );
    expect(
      VideoView.fromJson(_through(video.toJson())).toJson(),
      video.toJson(),
    );

    final status = StatusView(
      state: 'ready',
      version: '1.0.0',
      busy: true,
      paused: false,
      jobs: {'waiting': 2, 'done': 1},
    );
    expect(
      StatusView.fromJson(_through(status.toJson())).toJson(),
      status.toJson(),
    );

    final goal = GoalView(
      id: 'archive.master',
      scenario: 'archive',
      title: 'Archive',
      subtitle: 'no quality loss',
      options: [
        OptionView(
          id: 'speed',
          title: 'Speed',
          defaultChoice: 'fast',
          advanced: false,
          choices: [ChoiceView(id: 'fast', label: 'Fast', hint: 'Bigger')],
        ),
      ],
    );
    expect(GoalView.fromJson(_through(goal.toJson())).toJson(), goal.toJson());

    final outcome = JobOutcome(
      jobId: 3,
      path: '/videos/a.mov',
      status: 'done',
      outputPath: '/videos/Converted/a.mp4',
      needsALook: false,
    );
    expect(
      JobOutcome.fromJson(_through(outcome.toJson())).toJson(),
      outcome.toJson(),
    );
  });

  test('absent values are left out of the JSON', () {
    final json = VideoView(
      id: 0,
      path: '/videos/a.mov',
      status: 'probing',
      audioCodecs: const [],
      hdr: false,
    ).toJson();
    expect(json.containsKey('sizeBytes'), isFalse);
    expect(json.containsKey('preview'), isFalse);
  });

  test('English text stands beside the ids', () {
    final video = VideoView(
      id: 0,
      path: '/videos/a.mov',
      status: 'unreadable',
      audioCodecs: const [],
      hdr: false,
      preview: GoalPreview(
        goal: 'archive.master',
        plan: 'keptAsIs',
        measured: true,
        measuring: false,
        closeness: 'veryClose',
      ),
    ).toJson();
    expect(video['statusText'], 'Cannot be read: not a video FFmpeg can open');
    final preview = video['preview'] as Map<String, Object?>;
    expect(preview['planText'], planWords('keptAsIs'));
    expect(preview['closenessText'], 'Very close to the original');
    final quality = QualityView(outcome: 'raised', share: 1).toJson();
    expect(quality['outcomeText'], startsWith('Raised quality'));
  });

  test('no word the client prints speaks of deleting', () {
    final all = [
      for (final s in [
        'waiting',
        'running',
        'paused',
        'done',
        'skipped',
        'failed',
        'cancelled',
        'removed',
        'probing',
        'ready',
        'unreadable',
      ])
        statusWords(s),
      for (final s in [
        'skip',
        'remux',
        'audioOnly',
        'encode',
        'unsupported',
        'keptAsIs',
      ])
        planWords(s),
      for (final s in ['same', 'veryClose', 'differs']) closenessWords(s),
      for (final s in ['standard', 'raised', 'belowTarget', 'notWorthIt'])
        outcomeWords(s),
    ];
    for (final text in all) {
      expect(speaksOfDeleting(text), isFalse, reason: text);
    }
  });

  test('the guard catches deleting but lets the two rules through', () {
    expect(speaksOfDeleting('Delete the original when done.'), isTrue);
    expect(speaksOfDeleting('then rm the source'), isTrue);
    expect(
      speaksOfDeleting('Confirm the format. $filesRule $neverDeletes'),
      isFalse,
    );
  });
}
