import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/core/estimate/progress_estimator.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

import 'fake_media.dart';

/// A job as the queue holds it, for tests that build queue states by hand.
/// Job [id] converts `/videos/<id>.mp4` to `/videos/<id>_new.mp4`.
QueueJob queueJob(
  int id,
  JobStatus status, {
  int? attempt,
  JobProgress? progress,
}) => QueueJob(
  id: id,
  sourceId: id,
  info: clip(path: '/videos/$id.mp4'),
  recipe: const Recipe(presetId: 'remux.container'),
  plan: const ConversionPlan(kind: PlanKind.remux, extension: 'mp4'),
  output: const OutputSettings(),
  outputPath: '/videos/${id}_new.mp4',
  status: status,
  attempt: attempt,
  progress: progress,
);

QueueJob waitingJob(int id) => queueJob(id, JobStatus.waiting);
QueueJob runningJob(int id) => queueJob(id, JobStatus.running);
QueueJob doneJob(int id) => queueJob(id, JobStatus.done);
QueueJob failedJob(int id) => queueJob(id, JobStatus.failed);
QueueJob cancelledJob(int id) => queueJob(id, JobStatus.cancelled);

JobProgress progressAt(double fraction) => JobProgress(
  fraction: fraction,
  outTime: Duration.zero,
  remaining: const Duration(seconds: 30),
);
