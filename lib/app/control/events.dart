import '../../core/control/protocol.dart';
import '../../core/control/words.dart';
import '../quality/quality_controller.dart';
import '../queue/queue_state.dart';
import '../sources/sources_controller.dart';
import 'app_views.dart';

// What a subscribed client is told, worked out by comparing the window's
// state before and after each change.

/// One thing that happened in the window, named as in [Events].
class ControlEvent {
  const ControlEvent(this.name, this.data);

  final String name;
  final Map<String, Object?> data;
}

/// What a notification carries: when it was sent, then [data].
Map<String, Object?> eventParams(Map<String, Object?> data) => {
  'time': DateTime.now().toUtc().toIso8601String(),
  ...data,
};

/// What changed in the queue from [before] to [after]: for each job in
/// order, then for the queue as a whole.
List<ControlEvent> queueEvents(QueueState before, QueueState after) {
  final earlier = {for (final job in before.jobs) job.id: job};
  final events = <ControlEvent>[];
  for (final job in after.jobs) {
    var was = earlier[job.id];
    if (was == null) {
      events.add(ControlEvent(Events.jobAdded, jobView(job).toJson()));
      // As if it had come in waiting, so a job that is further along by now
      // is told the rest too.
      was = job.copyWith(
        status: JobStatus.waiting,
        clearAttempt: true,
        clearProgress: true,
      );
    }
    if (identical(was, job)) continue;
    if (was.status == JobStatus.waiting && job.status == JobStatus.running) {
      events.add(ControlEvent(Events.jobStarted, jobView(job).toJson()));
    }
    if (job.attempt case final attempt? when attempt != was.attempt) {
      events.add(
        ControlEvent(Events.jobChecking, {'job': job.id, 'attempt': attempt}),
      );
    }
    final progress = job.progress;
    if (job.isActive && progress != null && progress != was.progress) {
      final remaining = progress.remaining;
      events.add(
        ControlEvent(Events.jobProgress, {
          'job': job.id,
          'fraction': progress.fraction,
          'remainingSeconds': ?(remaining == null
              ? null
              : remaining.inMilliseconds / 1000),
        }),
      );
    }
    if (job.status != was.status && _ended(job.status)) {
      events.add(ControlEvent(Events.jobFinished, jobView(job).toJson()));
    }
  }
  final now = {for (final job in after.jobs) job.id};
  for (final job in before.jobs) {
    if (!now.contains(job.id)) {
      events.add(ControlEvent(Events.jobRemoved, {'job': job.id}));
    }
  }
  if (!before.paused && after.paused) {
    events.add(const ControlEvent(Events.queuePaused, {}));
  }
  if (before.paused && !after.paused) {
    events.add(const ControlEvent(Events.queueResumed, {}));
  }
  if (before.busy && !after.busy) {
    events.add(const ControlEvent(Events.queueIdle, {}));
  }
  return events;
}

bool _ended(JobStatus status) => switch (status) {
  JobStatus.done ||
  JobStatus.skipped ||
  JobStatus.failed ||
  JobStatus.cancelled => true,
  JobStatus.waiting || JobStatus.running || JobStatus.paused => false,
};

/// What changed in the list of videos from [before] to [after]. The
/// selection is the owner's and is not told.
List<ControlEvent> sourceEvents(SourcesState before, SourcesState after) {
  final earlier = {for (final video in before.videos) video.id: video};
  final events = <ControlEvent>[];
  for (final video in after.videos) {
    final was = earlier[video.id];
    if (was == null) {
      events.add(ControlEvent(Events.videoAdded, videoView(video).toJson()));
    }
    final status = was?.status ?? SourceStatus.probing;
    if (status == video.status) continue;
    switch (video.status) {
      case SourceStatus.ready:
        events.add(ControlEvent(Events.videoReady, videoView(video).toJson()));
      case SourceStatus.unreadable:
        events.add(
          ControlEvent(Events.videoUnreadable, videoView(video).toJson()),
        );
      case SourceStatus.probing:
        break;
    }
  }
  final now = {for (final video in after.videos) video.id};
  for (final video in before.videos) {
    if (!now.contains(video.id)) {
      events.add(ControlEvent(Events.videoRemoved, {'video': video.id}));
    }
  }
  return events;
}

/// Comparisons with the original that ended from [before] to [after], by
/// job id.
List<ControlEvent> qualityEvents(
  Map<int, QualityCheck> before,
  Map<int, QualityCheck> after,
) {
  final events = <ControlEvent>[];
  for (final MapEntry(key: job, value: check) in after.entries) {
    if (identical(before[job], check)) continue;
    switch (check) {
      case QualityMeasured():
        events.add(
          ControlEvent(Events.compareFinished, {
            'job': job,
            'status': 'measured',
            'closeness': check.closeness.name,
            'closenessText': closenessWords(check.closeness.name),
            'xpsnr': check.lumaDb,
            'vmaf': ?check.vmaf,
          }),
        );
      case QualityFailed():
        events.add(
          ControlEvent(Events.compareFinished, {
            'job': job,
            'status': 'failed',
            'errorLines': check.errorLines,
          }),
        );
      case QualityComparing():
        break;
    }
  }
  return events;
}
