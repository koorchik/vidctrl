import 'codes.dart';

// The English words the client prints for the codes the window sends, and the
// guard that keeps every text it prints from speaking of deleting a file.

/// The rule every manual and prompt states.
const filesRule = 'Never delete, move or rename any file.';

/// What "remove" means. With [filesRule], the only sentences allowed to name
/// deleting, both forbidding it.
const neverDeletes =
    'VidCtrl deletes no file: "remove" takes a video off the list or a job '
    'out of the queue, and the file stays on disk.';

final _deleting = RegExp(
  r'delet|\brm\b|\bunlink|\btrash|\berase|\bclean(ed|ing)?[ -]?up\b|'
  r'\bremov(e|es|ed|ing) the (original|source|input)|the original can go|'
  r'\bwip(e|es|ed|ing)\b|\bpurg|\bdiscard|\bdestro|get rid of|overwrit|'
  r'originals?\b.{0,20}\b(can|may|could) (go|be removed)|'
  r'\breplac(e|es|ed|ing)\b.{0,20}\boriginal|'
  r'remov\w* .{0,30}(from (the )?disk|to free)|free (up )?space by|'
  r'remove-item|\bdel\b|\brmdir\b|\bmv\b|throw(ing)? away|dispos|'
  r'clear(ing)? out|rewrit|in place',
);

/// True when [text], once the two allowed rules are taken out, speaks of
/// deleting.
bool speaksOfDeleting(String text) {
  final rest = text.replaceAll(filesRule, '').replaceAll(neverDeletes, '');
  return _deleting.hasMatch(rest.toLowerCase());
}

/// A job's status, or a video's: a [JobStatusCodes] or [VideoStatusCodes]
/// code.
String statusWords(String status) => switch (status) {
  JobStatusCodes.waiting => 'Waiting',
  JobStatusCodes.running => 'Converting',
  JobStatusCodes.paused => 'Paused',
  JobStatusCodes.done => 'Done',
  JobStatusCodes.skipped => 'Nothing to do',
  JobStatusCodes.failed => 'Failed',
  JobStatusCodes.cancelled => 'Cancelled',
  JobStatusCodes.removed => 'Taken out of the queue (the file stays on disk)',
  VideoStatusCodes.probing => 'Being read',
  VideoStatusCodes.ready => 'Ready',
  VideoStatusCodes.unreadable => 'Cannot be read: not a video FFmpeg can open',
  _ => status,
};

String planWords(String plan) => switch (plan) {
  PlanCodes.skip => 'Already fine: nothing to do',
  PlanCodes.remux => 'Copied into a new file type, untouched',
  PlanCodes.audioOnly => 'Only the sound is converted',
  PlanCodes.encode => 'Converted',
  PlanCodes.unsupported => 'This goal cannot do anything with it',
  PlanCodes.keptAsIs =>
    'Kept as it is: converting would hardly make it smaller',
  _ => plan,
};

String closenessWords(String closeness) => switch (closeness) {
  ClosenessCodes.same => 'Looks the same as the original',
  ClosenessCodes.veryClose => 'Very close to the original',
  ClosenessCodes.differs => 'Differences may be visible',
  _ => closeness,
};

String outcomeWords(String outcome) => switch (outcome) {
  OutcomeCodes.standard => 'Usual quality',
  OutcomeCodes.raised => 'Raised quality: needed to look the same',
  OutcomeCodes.belowTarget =>
    'Worth a look by eye: even the best quality falls a little short '
        'somewhere',
  OutcomeCodes.notWorthIt =>
    'Kept as it is: converting would hardly make it smaller',
  _ => outcome,
};
