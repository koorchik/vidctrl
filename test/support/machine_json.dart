import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/control/codes.dart';

/// The keys whose values are codes, wherever they appear.
const _codeKeys = {
  'status',
  'state',
  'plan',
  'closeness',
  'outcome',
  'result',
  'reason',
  'sample',
  'code',
  'kind',
  'event',
  'group',
};

/// The keys of the window's labels, which JSON leaves to the manual.
const _wordKeys = {'title', 'subtitle', 'label', 'hint', 'rows'};

/// Fails unless [json] is fit for a program: no key ends in `Text` or is
/// one of [_wordKeys], every value under a key of [_codeKeys] is a code, and
/// so is every key of a Status's `jobs` object. Only those keys are checked
/// for codes: a value under any other key may be anything. `raw` is
/// ffprobe's report as it gave it, so what is in it is not checked.
void expectMachineJson(Object? json, {String at = r'$'}) {
  switch (json) {
    case final Map<Object?, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        final path = '$at.$key';
        if (key == 'raw') continue;
        expect(key, isNot(endsWith('Text')), reason: '$path is words');
        expect(_wordKeys, isNot(contains(key)), reason: '$path is words');
        if (_codeKeys.contains(key) && value is! Map && value is! List) {
          expect(value, matches(codePattern), reason: '$path is no code');
        }
        if (key == 'jobs' && value is Map) {
          for (final status in value.keys) {
            expect(status, matches(codePattern), reason: '$path is no code');
          }
        }
        expectMachineJson(value, at: path);
      }
    case final List<Object?> list:
      for (final (i, item) in list.indexed) {
        expectMachineJson(item, at: '$at[$i]');
      }
  }
}
