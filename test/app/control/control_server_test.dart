import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/control/control_controller.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/queue/queue_controller.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/app/recipe/recipe_controller.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/protocol.dart';
import 'package:vidctrl/core/output/output_namer.dart';

import '../../support/control.dart';
import '../../support/fake_media.dart';
import '../../support/fakes.dart';

Matcher _failsWith(ControlErrorKind kind, [Object? message]) => throwsA(
  isA<ControlError>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', message ?? anything),
);

void main() {
  late FakeEnvironment env;
  late Directory folder;

  /// A file on disk that the fake ffprobe reads as a video.
  String video(String name) {
    final path = p.join(folder.path, name);
    File(path).writeAsStringSync('');
    env.ffprobe.add(path);
    return path;
  }

  setUp(() async {
    env = FakeEnvironment();
    folder = await Directory.systemTemp.createTemp('vidctrl_videos_');
    addTearDown(() => folder.delete(recursive: true));
  });

  group('status', () {
    test('says ready with the queue in numbers', () async {
      final (_, client) = await startControlled(env);

      final status = await client.call(Methods.status) as Map;
      expect(status['state'], 'ready');
      expect(status['busy'], isFalse);
      expect(status['paused'], isFalse);
      expect(status['jobs'], isEmpty);
    });

    test('answers while FFmpeg is still being looked for', () async {
      final found = Completer<AppEnvironment>();
      final (_, client) = await startControlled(
        env,
        awaitEnvironment: false,
        environment: () => found.future,
      );

      final status = await client.call(Methods.status) as Map;
      expect(status['state'], 'starting');

      var answered = false;
      final list = client.call(Methods.queueList).then((answer) {
        answered = true;
        return answer;
      });
      await pumpEventQueue();
      expect(answered, isFalse);
      found.complete(env.environment);
      expect(await list, containsPair('jobs', isEmpty));
    });

    test('without FFmpeg every method but status fails at once', () async {
      final (_, client) = await startControlled(
        env,
        awaitEnvironment: false,
        environment: () async => throw const FfmpegMissing(),
      );

      await expectLater(
        client.call(Methods.videosList).timeout(const Duration(seconds: 2)),
        _failsWith(ControlErrorKind.ffmpegMissing, contains('FFmpeg')),
      );
      final status = await client.call(Methods.status) as Map;
      expect(status['state'], 'ffmpegMissing');
    });

    test('an unknown method is refused', () async {
      final (_, client) = await startControlled(env);

      await expectLater(
        client.call('videos.shred'),
        _failsWith(ControlErrorKind.unknownMethod),
      );
    });
  });

  group('goals', () {
    test('lists each goal with its words and choices', () async {
      final (_, client) = await startControlled(env);

      final goals = (await client.call(Methods.goals) as Map)['goals'] as List;
      final archive = goals.first as Map;
      expect(archive['id'], 'archive.master');
      expect(archive['scenario'], 'archive');
      expect(archive['title'], 'Archive');
      expect(archive['subtitle'], 'no quality loss');
      expect(
        goals.map((g) => (g as Map)['id']),
        containsAll(['remux.container', 'resolve.studio', 'resolve.free']),
      );
      final codec = (archive['options'] as List).cast<Map>().single;
      expect(codec['id'], 'codec');
      expect(codec['defaultChoice'], 'av1');
      expect((codec['choices'] as List).map((c) => (c as Map)['id']), [
        'av1',
        'hevc',
      ]);
      expect(((codec['choices'] as List).first as Map)['hint'], isNotEmpty);
    });

    test('leaves out what this computer cannot do', () async {
      final (_, client) = await startControlled(env);

      final goals = (await client.call(Methods.goals) as Map)['goals'] as List;
      final archive = goals.first as Map;
      // No graphics card encoder in this environment: no speed row.
      expect(
        (archive['options'] as List).map((o) => (o as Map)['id']),
        isNot(contains('speed')),
      );
    });

    test('offers a row the panel shows once another choice is made', () async {
      // The graphics card makes HEVC only: speed appears with HEVC chosen.
      env = FakeEnvironment(capabilities: withGpu({'hevc_nvenc'}));
      final (_, client) = await startControlled(env);

      final goals = (await client.call(Methods.goals) as Map)['goals'] as List;
      final archive = goals.first as Map;
      expect((archive['options'] as List).map((o) => (o as Map)['id']), [
        'codec',
        'speed',
      ]);
    });
  });

  group('videos', () {
    test(
      'a video added by the client appears in the list and is selected',
      () async {
        final a = video('a.mp4');
        final (container, client) = await startControlled(env);

        final answer = await client.call(Methods.videosAdd, {
          'paths': [a],
        }) as Map;

        final added = container.read(sourcesProvider).videos.single;
        expect(answer['videos'], [
          {'path': a, 'id': added.id, 'result': 'added'},
        ]);
        expect(added.status, SourceStatus.ready);
        expect(container.read(sourcesProvider).selectedIds, {added.id});
      },
    );

    test('a missing path is reported and the others still go in', () async {
      final a = video('a.mp4');
      final missing = p.join(folder.path, 'nope.mp4');
      final (container, client) = await startControlled(env);

      final answer = await client.call(Methods.videosAdd, {
        'paths': [a, missing],
      }) as Map;

      expect(answer['videos'], [
        {'path': a, 'id': isA<int>(), 'result': 'added'},
        {'path': missing, 'result': 'notFound'},
      ]);
      expect(container.read(sourcesProvider).videos, hasLength(1));
    });

    test(
      'a file already listed is known, one not a video unreadable',
      () async {
        final a = video('a.mp4');
        final notes = p.join(folder.path, 'notes.txt');
        File(notes).writeAsStringSync('');
        final (_, client) = await startControlled(env);
        await client.call(Methods.videosAdd, {
          'paths': [a],
        });

        final answer = await client.call(Methods.videosAdd, {
          'paths': [a, notes],
        }) as Map;

        expect((answer['videos'] as List).map((v) => (v as Map)['result']), [
          'known',
          'unreadable',
        ]);
      },
    );

    test('a folder adds the videos inside it', () async {
      final a = video('a.mp4');
      final b = video('b.mp4');
      final (_, client) = await startControlled(env);

      final answer = await client.call(Methods.videosAdd, {
        'paths': [folder.path],
      }) as Map;

      expect((answer['videos'] as List).map((v) => (v as Map)['path']), [a, b]);
    });

    test('nothing addable is a bad argument', () async {
      final (container, client) = await startControlled(env);

      await expectLater(
        client.call(Methods.videosAdd, {
          'paths': [p.join(folder.path, 'nope.mp4')],
        }),
        _failsWith(ControlErrorKind.badArgument, contains('nope.mp4')),
      );
      expect(container.read(sourcesProvider).videos, isEmpty);
    });

    test('a relative path is a bad argument', () async {
      final (_, client) = await startControlled(env);

      await expectLater(
        client.call(Methods.videosAdd, {
          'paths': ['clip.mov'],
        }),
        _failsWith(ControlErrorKind.badArgument, contains('clip.mov')),
      );
    });

    test('the list says what a goal would do to each video', () async {
      final a = video('a.mp4');
      final (_, client) = await startControlled(env);
      await client.call(Methods.videosAdd, {
        'paths': [a],
      });

      final plain =
          ((await client.call(Methods.videosList) as Map)['videos'] as List)
                  .single
              as Map;
      expect(plain['path'], a);
      expect(plain['status'], 'ready');
      expect(plain['width'], 3840);
      expect(plain.containsKey('preview'), isFalse);

      final listed =
          ((await client.call(Methods.videosList, {'goal': 'remux'})
                          as Map)['videos']
                      as List)
                  .single
              as Map;
      final preview = listed['preview'] as Map;
      expect(preview['goal'], 'remux.container');
      expect(preview['plan'], isIn(['remux', 'skip']));
    });

    test('removing takes a video off the list by id or path', () async {
      final a = video('a.mp4');
      final b = video('b.mp4');
      final (container, client) = await startControlled(env);
      await client.call(Methods.videosAdd, {
        'paths': [a, b],
      });
      final ids = [
        for (final v in container.read(sourcesProvider).videos) v.id,
      ];

      final answer = await client.call(Methods.videosRemove, {
        'videos': [ids.first, b],
      }) as Map;

      expect(answer['removed'], ids);
      expect(container.read(sourcesProvider).videos, isEmpty);
      expect(File(a).existsSync(), isTrue);
    });

    test('removing an unknown video is not found', () async {
      final (_, client) = await startControlled(env);

      await expectLater(
        client.call(Methods.videosRemove, {
          'videos': [42],
        }),
        _failsWith(ControlErrorKind.notFound, contains('42')),
      );
    });
  });

  group('queue', () {
    Future<int> addVideo(ControlConnection client, String path) async {
      final answer = await client.call(Methods.videosAdd, {
        'paths': [path],
      }) as Map;
      return ((answer['videos'] as List).single as Map)['id'] as int;
    }

    test('queue add with a goal makes the job the button would, and leaves the '
        'panel alone', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));
      final panel = container.read(recipeProvider);

      final answer = await client.call(Methods.queueAdd, {
        'videos': [id],
        'goal': 'remux',
        'options': <String, Object?>{},
      }) as Map;

      final job = container.read(queueProvider).jobs.single;
      expect(job.recipe.presetId, 'remux.container');
      expect(job.sourceId, id);
      expect(answer['goal'], 'remux.container');
      expect(answer['options'], {'format': 'mp4'});
      expect((answer['added'] as List).single, containsPair('id', job.id));
      expect(answer['alreadyQueued'], isEmpty);
      expect(container.read(recipeProvider), same(panel));
    });

    test('queue add without a goal uses the panel and says which', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));

      final answer = await client.call(Methods.queueAdd, {
        'videos': [id],
      }) as Map;

      expect(answer['goal'], container.read(recipeProvider).recipe.presetId);
      expect(
        container.read(queueProvider).jobs.single.recipe,
        container.read(recipeProvider).recipe,
      );
    });

    test(
      'queue add makes whole videos even when the panel makes samples',
      () async {
        final (container, client) = await startControlled(env);
        final id = await addVideo(client, video('a.mp4'));
        container.read(recipeProvider.notifier).setSample(SampleChoice.start);

        await client.call(Methods.queueAdd, {
          'videos': [id],
        });

        final job = container.read(queueProvider).jobs.single;
        expect(job.sample, isNull);
        expect(job.recipe.sample, SampleChoice.none);
      },
    );

    test('a sample is made when asked for', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));

      await client.call(Methods.queueAdd, {
        'videos': [id],
        'sample': 'middle',
      });

      expect(
        container.read(queueProvider).jobs.single.recipe.sample,
        SampleChoice.middle,
      );
    });

    test('a path not in the list yet is added first', () async {
      final a = video('a.mp4');
      final (container, client) = await startControlled(env);

      await client.call(Methods.queueAdd, {
        'videos': [a],
        'goal': 'remux',
      });

      final listed = container.read(sourcesProvider).videos.single;
      expect(listed.path, a);
      expect(container.read(queueProvider).jobs.single.sourceId, listed.id);
    });

    test('an unknown goal or choice lists the valid ones', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));

      await expectLater(
        client.call(Methods.queueAdd, {
          'videos': [id],
          'goal': 'zip',
        }),
        _failsWith(ControlErrorKind.badArgument, contains('archive')),
      );
      await expectLater(
        client.call(Methods.queueAdd, {
          'videos': [id],
          'goal': 'archive',
          'options': {'speed': 'warp'},
        }),
        _failsWith(
          ControlErrorKind.badArgument,
          allOf(contains('cpu'), contains('gpu')),
        ),
      );
      await expectLater(
        client.call(Methods.queueAdd, {
          'videos': [id],
          'goal': 'archive',
          'options': {'colour': 'red'},
        }),
        _failsWith(
          ControlErrorKind.badArgument,
          allOf(contains('codec'), contains('speed')),
        ),
      );
      await expectLater(
        client.call(Methods.queueAdd, {
          'videos': [id],
          'goal': 'resolve',
        }),
        _failsWith(
          ControlErrorKind.badArgument,
          allOf(contains('resolve.studio'), contains('resolve.free')),
        ),
      );
      expect(container.read(queueProvider).jobs, isEmpty);
    });

    test('the same job twice is reported as already queued', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));
      final add = {
        'videos': [id],
        'goal': 'space',
      };

      await client.call(Methods.queueAdd, add);
      final again = await client.call(Methods.queueAdd, add) as Map;

      expect(again['added'], isEmpty);
      expect(again['alreadyQueued'], [id]);
      expect(container.read(queueProvider).jobs, hasLength(1));
    });

    test('an unreadable video is skipped and the others queued', () async {
      final notes = p.join(folder.path, 'notes.txt');
      File(notes).writeAsStringSync('');
      final (container, client) = await startControlled(env);
      final a = await addVideo(client, video('a.mp4'));
      final unreadable = await addVideo(client, notes);

      final answer = await client.call(Methods.queueAdd, {
        'videos': [a, unreadable],
        'goal': 'remux',
      }) as Map;

      expect(answer['skipped'], [
        {'video': unreadable, 'reason': 'unreadable'},
      ]);
      expect(container.read(queueProvider).jobs.single.sourceId, a);
    });

    test('a video still being read is waited for', () async {
      final (container, client) = await startControlled(env);
      final a = video('a.mp4');
      await client.call(Methods.videosAdd, {
        'paths': [a],
        'wait': false,
      });

      await client.call(Methods.queueAdd, {
        'videos': [a],
        'goal': 'remux',
      });

      expect(container.read(queueProvider).jobs, hasLength(1));
    });

    test('out sends results next to the videos or into a folder', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));
      final elsewhere = p.join(folder.path, 'Results');

      await client.call(Methods.queueAdd, {
        'videos': [id],
        'goal': 'space',
        'out': 'next',
        'subfolder': 'Small',
      });
      await client.call(Methods.queueAdd, {
        'videos': [id],
        'goal': 'space',
        'out': elsewhere,
      });

      final outputs = [
        for (final job in container.read(queueProvider).jobs) job.output,
      ];
      expect(outputs.first.mode, OutputMode.subfolderNextToSource);
      expect(outputs.first.subfolderName, 'Small');
      expect(outputs.last.mode, OutputMode.customFolder);
      expect(outputs.last.customDir, elsewhere);
      expect(
        container.read(queueProvider).jobs.last.outputPath,
        startsWith(elsewhere),
      );
    });

    test('queue list shows each job', () async {
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));
      await client.call(Methods.queueAdd, {
        'videos': [id],
        'goal': 'space',
      });
      await pumpEventQueue();

      final answer = await client.call(Methods.queueList) as Map;

      expect(answer['busy'], isTrue);
      expect(answer['paused'], isFalse);
      final job = (answer['jobs'] as List).single as Map;
      expect(job['videoId'], id);
      expect(job['goal'], 'space.small');
      expect(job['status'], JobStatus.running.name);
      expect(
        job['outputPath'],
        container.read(queueProvider).jobs.single.outputPath,
      );
    });
  });

  group('one window', () {
    test('a second window does not take over a live endpoint', () async {
      final shared = await Directory.systemTemp.createTemp('vidctrl_control_');
      addTearDown(() => shared.delete(recursive: true));
      final first = await startWindow(env, dir: shared);
      final second = await startWindow(FakeEnvironment(), dir: shared);

      expect(first.read(controlProvider).serving, isTrue);
      expect(second.read(controlProvider).serving, isFalse);
      expect(
        (await controlFile(shared).read())!.port,
        first.read(controlProvider).port,
      );
    });

    test('a window takes over a stale endpoint', () async {
      final shared = await Directory.systemTemp.createTemp('vidctrl_control_');
      addTearDown(() => shared.delete(recursive: true));
      final gone = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = gone.port;
      await gone.close();
      await controlFile(shared).write(
        Endpoint(
          port: deadPort,
          token: 'old',
          pid: 1,
          version: '',
          protocol: controlProtocol,
        ),
      );

      final window = await startWindow(env, dir: shared);

      final port = window.read(controlProvider).port;
      expect(port, isNotNull);
      final written = (await controlFile(shared).read())!;
      expect(written.port, port);
      expect(written.token, isNot('old'));
    });

    test('stopping removes the endpoint file only if it is its own', () async {
      final shared = await Directory.systemTemp.createTemp('vidctrl_control_');
      addTearDown(() => shared.delete(recursive: true));
      final file = controlFile(shared);

      final mine = await startWindow(env, dir: shared);
      await mine.read(controlProvider.notifier).stop();
      expect(await file.read(), isNull);
      expect(mine.read(controlProvider).serving, isFalse);

      final other = await startWindow(env, dir: shared);
      final taken = (await file.read())!;
      final newer = Endpoint(
        port: taken.port,
        token: 'another window',
        pid: taken.pid,
        version: taken.version,
        protocol: taken.protocol,
      );
      await file.write(newer);
      await other.read(controlProvider.notifier).stop();
      expect((await file.read())?.token, 'another window');
    });
  });
}
