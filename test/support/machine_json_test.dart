import 'package:flutter_test/flutter_test.dart';

import 'machine_json.dart';

void main() {
  final fails = throwsA(isA<TestFailure>());

  test('JSON with codes, ids, numbers and paths passes', () {
    expectMachineJson({
      'id': 1,
      'path': '/videos/a.mov',
      'status': 'DONE',
      'options': {'speed': 'fast'},
      'jobs': {'WAITING': 2},
      'details': [
        {'group': 'VIDEO', 'title': 'Video track 1'},
      ],
    });
  });

  test('a value that is no code where a code belongs fails', () {
    expect(() => expectMachineJson({'status': 'done'}), fails);
    expect(
      () => expectMachineJson({
        'jobs': [
          {
            'quality': {'outcome': 'belowTarget'},
          },
        ],
      }),
      fails,
    );
  });

  test('a field of words fails', () {
    expect(() => expectMachineJson({'fooText': 'Done'}), fails);
  });

  test('a count of jobs by a status that is no code fails', () {
    expect(
      () => expectMachineJson({
        'jobs': {'waiting': 2},
      }),
      fails,
    );
  });
}
