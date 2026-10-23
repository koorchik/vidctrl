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
      'choices': ['av1', 'hevc'],
    });
  });

  test('ffprobe\'s report passes as it is, its own tags and all', () {
    expectMachineJson({
      'raw': {
        'format': {
          'tags': {'title': 'Family trip'},
        },
        'streams': [
          {'codec_type': 'audio', 'status': 'whatever'},
        ],
      },
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
    for (final key in ['title', 'subtitle', 'label', 'hint', 'rows']) {
      expect(
        () => expectMachineJson({
          'goals': [
            {'id': 'archive.master', key: 'Archive'},
          ],
        }),
        fails,
        reason: key,
      );
    }
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
