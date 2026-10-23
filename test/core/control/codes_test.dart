import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/control/codes.dart';
import 'package:vidctrl/core/control/protocol.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/quality/quality_search.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';

void main() {
  test('an enum value\'s code is its name in capitals, words split by _', () {
    expect(codeOf(PlanKind.audioOnly), 'AUDIO_ONLY');
    expect(codeOf(Closeness.veryClose), 'VERY_CLOSE');
    expect(codeOf(QualityOutcome.notWorthIt), 'NOT_WORTH_IT');
    expect(codeOf(ControlErrorKind.ffmpegMissing), 'FFMPEG_MISSING');
    expect(fromCode(Closeness.values, 'VERY_CLOSE'), Closeness.veryClose);
    expect(fromCode(Closeness.values, 'veryClose'), isNull);
  });

  test('the engine\'s values have exactly the codes listed', () {
    expect([...PlanKind.values.map(codeOf), PlanCodes.keptAsIs], PlanCodes.all);
    expect(Closeness.values.map(codeOf), ClosenessCodes.all);
    expect(QualityOutcome.values.map(codeOf), OutcomeCodes.all);
  });

  test('the errors have the codes the manual names', () {
    expect(
      [for (final kind in ControlErrorKind.values) kind.code],
      [
        'BAD_ARGUMENT',
        'NOT_FOUND',
        'BUSY',
        'UNKNOWN_METHOD',
        'FFMPEG_MISSING',
        'UNAUTHORIZED',
        'NOT_RUNNING',
        'APP_CLOSED',
      ],
    );
    expect(ClientErrorCodes.all, ['TIMEOUT', 'UNEXPECTED']);
  });

  test('every code is in capitals', () {
    for (final code in [
      ...JobStatusCodes.all,
      ...VideoStatusCodes.all,
      ...PlanCodes.all,
      ...ClosenessCodes.all,
      ...OutcomeCodes.all,
      ...StateCodes.all,
      ...AddResultCodes.all,
      ...SampleCodes.all,
      ...ComparisonCodes.all,
      ...ClientErrorCodes.all,
    ]) {
      expect(code, matches(codePattern));
    }
  });
}
