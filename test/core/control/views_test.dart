import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/control/codes.dart';
import 'package:vidctrl/core/control/views.dart';
import 'package:vidctrl/core/control/words.dart';

import '../../support/machine_json.dart';

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
      status: JobStatusCodes.done,
      outputPath: '/videos/Converted/a_av1-crf35.mp4',
      outputBytes: 10,
      quality: QualityView(
        outcome: OutcomeCodes.belowTarget,
        value: 20,
        share: .4,
      ),
      needsALook: true,
      errorLines: const [],
    );
    expect(JobView.fromJson(_through(job.toJson())).toJson(), job.toJson());

    final video = VideoView(
      id: 1,
      path: '/videos/a.mov',
      status: VideoStatusCodes.ready,
      sizeBytes: 1000,
      durationSeconds: 12.5,
      width: 3840,
      height: 2160,
      videoCodec: 'hevc',
      audioCodecs: const ['aac'],
      hdr: true,
      preview: GoalPreview(
        goal: 'archive.master',
        plan: PlanCodes.encode,
        expectedBytes: 100,
        measured: true,
        measuring: false,
        closeness: ClosenessCodes.same,
      ),
    );
    expect(
      VideoView.fromJson(_through(video.toJson())).toJson(),
      video.toJson(),
    );

    final status = StatusView(
      state: StateCodes.ready,
      version: '1.0.0',
      busy: true,
      paused: false,
      jobs: {JobStatusCodes.waiting: 2, JobStatusCodes.done: 1},
    );
    expect(
      StatusView.fromJson(_through(status.toJson())).toJson(),
      status.toJson(),
    );

    final goal = GoalView(
      id: 'archive.master',
      scenario: 'archive',
      options: [
        OptionView(
          id: 'speed',
          defaultChoice: 'gpu',
          advanced: false,
          choices: ['cpu', 'gpu'],
        ),
      ],
    );
    expect(GoalView.fromJson(_through(goal.toJson())).toJson(), goal.toJson());

    final outcome = JobOutcome(
      jobId: 3,
      path: '/videos/a.mov',
      status: JobStatusCodes.done,
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
      status: VideoStatusCodes.probing,
      audioCodecs: const [],
      hdr: false,
    ).toJson();
    expect(json.containsKey('sizeBytes'), isFalse);
    expect(json.containsKey('preview'), isFalse);
  });

  test('the JSON carries codes, never words', () {
    final video = VideoView(
      id: 0,
      path: '/videos/a.mov',
      status: VideoStatusCodes.ready,
      audioCodecs: const [],
      hdr: false,
      preview: GoalPreview(
        goal: 'archive.master',
        plan: PlanCodes.keptAsIs,
        measured: true,
        measuring: false,
        closeness: ClosenessCodes.veryClose,
      ),
    ).toJson();
    final job = JobView(
      id: 3,
      videoId: 0,
      path: '/videos/a.mov',
      goal: 'archive.master',
      options: {'speed': 'fast'},
      sample: SampleCodes.middle,
      status: JobStatusCodes.done,
      quality: QualityView(outcome: OutcomeCodes.belowTarget, share: .4),
      needsALook: true,
      errorLines: const [],
    ).toJson();
    final status = StatusView(
      state: StateCodes.ready,
      version: '1.0.0',
      busy: false,
      paused: false,
      jobs: {JobStatusCodes.waiting: 1},
    ).toJson();
    final outcome = JobOutcome(
      jobId: 3,
      path: '/videos/a.mov',
      status: JobStatusCodes.removed,
      needsALook: false,
    ).toJson();
    for (final json in [video, job, status, outcome]) {
      expectMachineJson(json);
    }
    expect((video['preview'] as Map)['plan'], 'KEPT_AS_IS');
    expect((job['quality'] as Map)['outcome'], 'BELOW_TARGET');
  });

  test('no word the client prints speaks of deleting', () {
    final all = [
      for (final s in [...JobStatusCodes.all, ...VideoStatusCodes.all])
        statusWords(s),
      for (final s in PlanCodes.all) planWords(s),
      for (final s in ClosenessCodes.all) closenessWords(s),
      for (final s in OutcomeCodes.all) outcomeWords(s),
    ];
    for (final text in all) {
      expect(speaksOfDeleting(text), isFalse, reason: text);
    }
  });

  test('every code has its words', () {
    for (final (words, codes) in [
      (statusWords, [...JobStatusCodes.all, ...VideoStatusCodes.all]),
      (planWords, PlanCodes.all),
      (closenessWords, ClosenessCodes.all),
      (outcomeWords, OutcomeCodes.all),
    ]) {
      for (final code in codes) {
        expect(words(code), isNot(code), reason: code);
      }
    }
  });

  test('the guard catches every way of speaking of deleting', () {
    for (final phrase in [
      'Delete the original when done.',
      'then rm the source',
      'unlink the file',
      'Move it to the Trash.',
      'Erase the card.',
      'The folder is cleaned up afterwards.',
      'Run a cleanup.',
      'Clean up the originals.',
      'Cleaning up the folder.',
      'This removes the original.',
      'Removing the originals frees space.',
      'Once removed the original is gone.',
      'Remove the source.',
      'Remove the input files.',
      'The original can go now.',
      'Wipe the folder.',
      'Purge the old files.',
      'Discard the originals.',
      'It destroys the file.',
      'Get rid of the big files.',
      'The result overwrites the original.',
      'Overwriting is allowed.',
      'The originals can go once they are converted.',
      'The originals can be removed once checked.',
      'Replace the originals with the results.',
      'The result replaces the original.',
      'Remove the files from disk.',
      'Remove them to free up space.',
      'Free up space by removing the camera files.',
      r'Remove-Item $files',
      'del beach.mov',
      'rmdir Converted',
      'mv beach.mov old/',
      'Throw away the big files.',
      'Dispose of the originals.',
      'Clear out the folder.',
      'Every file is rewritten.',
      'The file is changed in place.',
    ]) {
      expect(speaksOfDeleting(phrase), isTrue, reason: phrase);
    }
  });

  test('the guard lets the two rules and harmless words through', () {
    for (final text in [
      filesRule,
      neverDeletes,
      'Confirm the format.',
      'The size may increase.',
      'The original stays.',
      'remove takes a video off the list',
      'Remove personal data',
      'Removes the hidden notes about place and date.',
      'Confirm the format. $filesRule $neverDeletes',
    ]) {
      expect(speaksOfDeleting(text), isFalse, reason: text);
    }
  });
}
