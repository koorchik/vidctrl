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

/// Fails unless [json] is fit for a program: no key ends in `Text`, every
/// value under a key of [_codeKeys] is a code, and so is every key of a
/// Status's `jobs` object. Only those keys are checked for codes: a value
/// under any other key may be anything.
void expectMachineJson(Object? json, {String at = r'$'}) {
  switch (json) {
    case final Map<Object?, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        final path = '$at.$key';
        expect(key, isNot(endsWith('Text')), reason: '$path is words');
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
