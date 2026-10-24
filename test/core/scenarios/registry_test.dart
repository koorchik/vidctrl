import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/scenarios/registry.dart';

void main() {
  test('each preset belongs to the goal that offers it', () {
    for (final scenario in scenarios) {
      for (final preset in scenario.presets) {
        expect(scenarioOf(preset).id, scenario.id);
      }
    }
    expect(scenarioOf(findPreset('resolve.studio')!).id, 'resolve');
  });
}
