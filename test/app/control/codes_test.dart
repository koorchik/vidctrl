import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/control/app_views.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/control/codes.dart';

import '../../support/fake_media.dart';
import '../../support/machine_json.dart';
import '../../support/queue_jobs.dart';

void main() {
  test('the window\'s values have exactly the codes listed', () {
    expect([
      ...JobStatus.values.map(codeOf),
      JobStatusCodes.removed,
    ], JobStatusCodes.all);
    expect(SourceStatus.values.map(codeOf), VideoStatusCodes.all);
    expect([
      for (final sample in SampleChoice.values)
        if (sample != SampleChoice.none) codeOf(sample),
    ], SampleCodes.all);
  });

  test('a job and a video are told by their codes', () {
    final done = doneJob(1);
    final sample = QueueJob(
      id: done.id,
      sourceId: done.sourceId,
      info: done.info,
      recipe: const Recipe(
        presetId: 'remux.container',
        sample: SampleChoice.middle,
      ),
      plan: done.plan,
      output: done.output,
      outputPath: done.outputPath,
      status: done.status,
    );
    final job = jobView(sample, softwareOnly).toJson();
    expect(job, containsPair('status', 'DONE'));
    expect(job, containsPair('sample', 'MIDDLE'));
    expectMachineJson(job);

    final video = videoView(const SourceVideo(id: 1, path: '/videos/a.mov'))
        .toJson();
    expect(video, containsPair('status', 'PROBING'));
    expectMachineJson(video);
  });
}
