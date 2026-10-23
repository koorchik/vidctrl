// The English words the client prints for the ids the window sends, and the
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

/// A job's status, or a video's (probing, ready, unreadable).
String statusWords(String status) => switch (status) {
  'waiting' => 'Waiting',
  'running' => 'Converting',
  'paused' => 'Paused',
  'done' => 'Done',
  'skipped' => 'Nothing to do',
  'failed' => 'Failed',
  'cancelled' => 'Cancelled',
  'removed' => 'Taken out of the queue (the file stays on disk)',
  'probing' => 'Being read',
  'ready' => 'Ready',
  'unreadable' => 'Cannot be read: not a video FFmpeg can open',
  _ => status,
};

String planWords(String plan) => switch (plan) {
  'skip' => 'Already fine: nothing to do',
  'remux' => 'Copied into a new file type, untouched',
  'audioOnly' => 'Only the sound is converted',
  'encode' => 'Converted',
  'unsupported' => 'This goal cannot do anything with it',
  'keptAsIs' => 'Kept as it is: converting would hardly make it smaller',
  _ => plan,
};

String closenessWords(String closeness) => switch (closeness) {
  'same' => 'Looks the same as the original',
  'veryClose' => 'Very close to the original',
  'differs' => 'Differences may be visible',
  _ => closeness,
};

String outcomeWords(String outcome) => switch (outcome) {
  'standard' => 'Usual quality',
  'raised' => 'Raised quality: needed to look the same',
  'belowTarget' =>
    'Worth a look by eye: even the best quality falls a little short '
        'somewhere',
  'notWorthIt' => 'Kept as it is: converting would hardly make it smaller',
  _ => outcome,
};
