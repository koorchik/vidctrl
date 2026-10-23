// The codes `--json` carries for every value that is one of a few, in
// SCREAMING_SNAKE_CASE, never words: a program reads these, and the words
// for people are in words.dart. A Dart enum's value becomes its code through
// [codeOf] alone; each kind of value lists its codes here, so the window,
// the client and the manual take them from one place.

/// [value]'s code: its name in SCREAMING_SNAKE_CASE (`audioOnly` is
/// `AUDIO_ONLY`).
String codeOf(Enum value) => value.name
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}')
    .toUpperCase();

/// The one of [values] whose code is [code], or null.
T? fromCode<T extends Enum>(Iterable<T> values, Object? code) {
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  return null;
}

/// What every code looks like.
final codePattern = RegExp(r'^[A-Z][A-Z0-9_]*$');

/// A job's status (Job `status`, and the keys of Status `jobs`), and how a
/// job ended (Outcome `status`).
abstract final class JobStatusCodes {
  static const waiting = 'WAITING';
  static const running = 'RUNNING';
  static const paused = 'PAUSED';
  static const done = 'DONE';
  static const skipped = 'SKIPPED';
  static const failed = 'FAILED';
  static const cancelled = 'CANCELLED';

  /// Only in an Outcome: taken out of the queue while it was waited for.
  static const removed = 'REMOVED';

  static const all = [
    waiting,
    running,
    paused,
    done,
    skipped,
    failed,
    cancelled,
    removed,
  ];
}

/// A video's status (Video `status`).
abstract final class VideoStatusCodes {
  static const probing = 'PROBING';
  static const ready = 'READY';
  static const unreadable = 'UNREADABLE';

  static const all = [probing, ready, unreadable];
}

/// What a goal would do to a video (Preview `plan`): a `PlanKind`, or
/// [keptAsIs] when Archive found converting not worth it.
abstract final class PlanCodes {
  static const skip = 'SKIP';
  static const remux = 'REMUX';
  static const audioOnly = 'AUDIO_ONLY';
  static const encode = 'ENCODE';
  static const unsupported = 'UNSUPPORTED';
  static const keptAsIs = 'KEPT_AS_IS';

  static const all = [skip, remux, audioOnly, encode, unsupported, keptAsIs];
}

/// How close a result looks to its original: a `Closeness`.
abstract final class ClosenessCodes {
  static const same = 'SAME';
  static const veryClose = 'VERY_CLOSE';
  static const differs = 'DIFFERS';

  static const all = [same, veryClose, differs];
}

/// How a job's quality was chosen (Quality `outcome`): a `QualityOutcome`.
abstract final class OutcomeCodes {
  static const standard = 'STANDARD';
  static const raised = 'RAISED';
  static const belowTarget = 'BELOW_TARGET';
  static const notWorthIt = 'NOT_WORTH_IT';

  static const all = [standard, raised, belowTarget, notWorthIt];
}

/// How the window stands (Status `state`).
abstract final class StateCodes {
  static const starting = 'STARTING';
  static const ready = 'READY';
  static const ffmpegMissing = 'FFMPEG_MISSING';

  static const all = [starting, ready, ffmpegMissing];
}

/// What adding a path gave (`videos.add`'s `result`), and why `queue.add`
/// skipped one (its `skipped[].reason`: [notFound] or [unreadable]).
abstract final class AddResultCodes {
  static const added = 'ADDED';

  /// In the list already.
  static const known = 'KNOWN';
  static const notFound = 'NOT_FOUND';
  static const unreadable = 'UNREADABLE';

  static const all = [added, known, notFound, unreadable];
}

/// Where a sample is taken from (Job `sample`, and `queue.add`'s
/// `sample`): a `SampleChoice` but none.
abstract final class SampleCodes {
  static const start = 'START';
  static const middle = 'MIDDLE';

  static const all = [start, middle];
}

/// How a comparison with the original ended (`job.compare`'s and
/// `COMPARE_FINISHED`'s `status`).
abstract final class ComparisonCodes {
  static const measured = 'MEASURED';
  static const failed = 'FAILED';

  static const all = [measured, failed];
}

/// The errors only the client itself reports, beside the window's
/// (`ControlErrorKind.code`).
abstract final class ClientErrorCodes {
  static const timeout = 'TIMEOUT';
  static const unexpected = 'UNEXPECTED';

  static const all = [timeout, unexpected];
}
