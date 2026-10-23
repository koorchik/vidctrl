import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/app/control/control_controller.dart';
import 'package:vidctrl/app/providers.dart';
import 'package:vidctrl/app/quality/quality_controller.dart';
import 'package:vidctrl/app/queue/queue_controller.dart';
import 'package:vidctrl/app/queue/queue_state.dart';
import 'package:vidctrl/app/recipe/recipe.dart';
import 'package:vidctrl/app/recipe/recipe_controller.dart';
import 'package:vidctrl/app/sources/sources_controller.dart';
import 'package:vidctrl/core/control/connection.dart';
import 'package:vidctrl/core/control/endpoint.dart';
import 'package:vidctrl/core/control/listener.dart';
import 'package:vidctrl/core/control/protocol.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/output/output_namer.dart';
import 'package:vidctrl/core/quality/quality_search.dart';

import '../../support/control.dart';
import '../../support/fake_media.dart';
import '../../support/fakes.dart';

/// A client as the window sees it, that keeps what it is told.
class _Peer implements ControlPeer {
  final told = <String>[];

  @override
  void notify(String method, Map<String, Object?> params) => told.add(method);

  @override
  Future<void> get closed => Completer<void>().future;
}

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
      env = FakeEnvironment(capabilities: withGpu({'av1_nvenc'}));
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

    test('a choice the panel does not offer on this computer is refused, '
        'naming what it offers', () async {
      // No graphics card encoder works here: the panel has no speed row.
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));

      await expectLater(
        client.call(Methods.queueAdd, {
          'videos': [id],
          'goal': 'archive',
          'options': {'speed': 'gpu'},
        }),
        _failsWith(
          ControlErrorKind.badArgument,
          allOf(contains('speed'), contains('Options here: codec.')),
        ),
      );
      expect(container.read(queueProvider).jobs, isEmpty);
    });

    test('an option the panel does not offer takes the choice made here '
        'anyway', () async {
      // No graphics card encoder: the processor converts, whatever is asked.
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));

      final answer = await client.call(Methods.queueAdd, {
        'videos': [id],
        'goal': 'archive',
        'options': {'speed': 'cpu'},
      }) as Map;

      expect(answer['added'], hasLength(1));
      expect(container.read(queueProvider).jobs, hasLength(1));
    });

    test('without AV1 the archive takes codec hevc only', () async {
      env = FakeEnvironment(
        capabilities: const Capabilities(
          ffmpegVersion: 'test',
          encoders: {'libx265', 'libx264', 'aac'},
          filters: {'xpsnr'},
        ),
      );
      final (container, client) = await startControlled(env);
      final id = await addVideo(client, video('a.mp4'));

      await expectLater(
        client.call(Methods.queueAdd, {
          'videos': [id],
          'goal': 'archive',
          'options': {'codec': 'av1'},
        }),
        _failsWith(
          ControlErrorKind.badArgument,
          allOf(
            contains('codec'),
            contains('hevc'),
            contains('no options on this computer'),
          ),
        ),
      );
      expect(container.read(queueProvider).jobs, isEmpty);

      // What it makes here anyway.
      await client.call(Methods.queueAdd, {
        'videos': [id],
        'goal': 'archive',
        'options': {'codec': 'hevc'},
      });
      expect(
        p.basename(container.read(queueProvider).jobs.single.outputPath),
        contains('hevc'),
      );
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

  group('queue controls', () {
    /// Queues [names] through [client] with [goal]; returns the job ids.
    Future<List<int>> queue(
      ControlConnection client,
      List<String> names, {
      String goal = 'space',
      String? sample,
    }) async {
      final answer = await client.call(Methods.queueAdd, {
        'videos': [for (final name in names) video(name)],
        'goal': goal,
        'sample': ?sample,
      }) as Map;
      return [for (final job in answer['added'] as List) (job as Map)['id']];
    }

    /// Until the fake executor has started [count] conversions.
    Future<void> started(int count) async {
      for (var i = 0; i < 100 && env.executor.started.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(env.executor.started, hasLength(count));
    }

    List<QueueJob> jobs(ProviderContainer container) =>
        container.read(queueProvider).jobs;

    test('cancel stops the job under way, as the cancel button does, and the '
        'queue goes on', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4', 'b.mp4']);
      await started(1);

      final answer = await client.call(Methods.queueCancel);

      expect(answer, {'cancelled': ids.first});
      expect(env.executor.started.first.cancelRequested, isTrue);
      expect(jobs(container).first.status, JobStatus.cancelled);
      await started(2);
    });

    test('cancel of a job not converting says how to take it out', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4', 'b.mp4']);
      await started(1);

      await expectLater(
        client.call(Methods.queueCancel, {'job': ids.last}),
        _failsWith(
          ControlErrorKind.badArgument,
          'Job ${ids.last} is not converting; `vidctrl-client queue remove '
          '${ids.last}` takes it out of the queue.',
        ),
      );
      expect(env.executor.started.first.cancelRequested, isFalse);
      expect(await client.call(Methods.queueCancel, {'job': ids.first}), {
        'cancelled': ids.first,
      });
      expect(jobs(container).first.status, JobStatus.cancelled);
    });

    test('cancel with nothing converting cancels nothing', () async {
      final (_, client) = await startControlled(env);

      expect(await client.call(Methods.queueCancel), {'cancelled': null});
      await expectLater(
        client.call(Methods.queueCancel, {'job': 42}),
        _failsWith(ControlErrorKind.notFound, contains('42')),
      );
    });

    test('cancel stops a job still choosing its quality', () async {
      env.estimator.hold = true;
      final (container, client) = await startControlled(env);
      final id = (await queue(client, ['a.mp4'], goal: 'archive')).single;
      for (var i = 0; i < 100 && jobs(container).single.attempt == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(jobs(container).single.checking, isTrue);

      expect(await client.call(Methods.queueCancel), {'cancelled': id});

      expect(jobs(container).single.status, JobStatus.cancelled);
      expect(env.executor.started, isEmpty);
    });

    test('move of the last job to position 1 puts it first', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4', 'b.mp4', 'c.mp4']);
      await started(1);

      final answer = await client.call(Methods.queueMove, {
        'job': ids.last,
        'position': 1,
      }) as Map;

      final order = [ids.last, ids.first, ids[1]];
      expect([for (final j in answer['jobs'] as List) (j as Map)['id']], order);
      expect([for (final job in jobs(container)) job.id], order);

      // Past the end is the end.
      await client.call(Methods.queueMove, {'job': ids.last, 'position': 9});
      expect(jobs(container).last.id, ids.last);
    });

    test('move takes waiting jobs only, as dragging does', () async {
      final (_, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4', 'b.mp4']);
      await started(1);

      await expectLater(
        client.call(Methods.queueMove, {'job': ids.first, 'position': 2}),
        _failsWith(ControlErrorKind.badArgument, contains('waiting')),
      );
      await expectLater(
        client.call(Methods.queueMove, {'job': ids.last, 'position': 'top'}),
        _failsWith(ControlErrorKind.badArgument, contains('position')),
      );
    });

    test('remove takes a done job out of the queue and leaves its file on '
        'disk', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4', 'b.mp4']);
      await started(1);
      final output = File(jobs(container).first.outputPath)
        ..createSync(recursive: true);
      env.executor.started.first.finish();
      await started(2);

      await expectLater(
        client.call(Methods.queueRemove, {
          'jobs': [ids.first, 42],
        }),
        _failsWith(ControlErrorKind.notFound, contains('42')),
      );
      expect(jobs(container), hasLength(2));

      final answer = await client.call(Methods.queueRemove, {
        'jobs': [ids.first],
      });

      expect(answer, {
        'removed': [ids.first],
      });
      expect([for (final job in jobs(container)) job.id], [ids.last]);
      expect(output.existsSync(), isTrue);
    });

    test('remove of the job under way cancels it first', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4']);
      await started(1);

      await client.call(Methods.queueRemove, {'jobs': ids});

      expect(env.executor.started.single.cancelRequested, isTrue);
      expect(jobs(container), isEmpty);
    });

    test('retry queues a failed job again; one that did not fail is '
        'refused', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4']);
      await started(1);

      await expectLater(
        client.call(Methods.queueRetry, {'job': ids.single}),
        _failsWith(ControlErrorKind.badArgument, contains('failed')),
      );
      env.executor.started.single.fail();
      await pumpEventQueue();
      expect(jobs(container).single.status, JobStatus.failed);

      final answer =
          await client.call(Methods.queueRetry, {'job': ids.single}) as Map;

      expect(answer['job'], containsPair('id', ids.single));
      await started(2);
      expect(jobs(container).single.status, JobStatus.running);
    });

    test(
      'clear finished takes out the done jobs, as its button does',
      () async {
        final (container, client) = await startControlled(env);
        final ids = await queue(client, ['a.mp4', 'b.mp4']);
        await started(1);
        env.executor.started.first.finish();
        await started(2);

        final answer = await client.call(Methods.queueClearFinished);

        expect(answer, {
          'removed': [ids.first],
        });
        expect([for (final job in jobs(container)) job.id], [ids.last]);
      },
    );

    test('pause and resume hold and continue the queue, each as often as '
        'asked', () async {
      final (container, client) = await startControlled(env);
      await queue(client, ['a.mp4']);
      await started(1);
      final handle = env.executor.started.single;

      expect(await client.call(Methods.queuePause), {'paused': true});
      expect(await client.call(Methods.queuePause), {'paused': true});
      expect(container.read(queueProvider).paused, isTrue);
      expect(handle.paused, isTrue);
      expect(jobs(container).single.status, JobStatus.paused);

      expect(await client.call(Methods.queueResume), {'paused': false});
      expect(await client.call(Methods.queueResume), {'paused': false});
      expect(handle.paused, isFalse);
      expect(jobs(container).single.status, JobStatus.running);
    });

    test('convert whole queues the whole video after a sample', () async {
      final (container, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4'], sample: 'start');
      await started(1);
      env.executor.started.single.finish();
      await pumpEventQueue();

      final answer = await client.call(Methods.queueConvertWhole, {
        'job': ids.single,
      }) as Map;

      final whole = jobs(container).last;
      expect(whole.isSample, isFalse);
      expect(whole.recipe.presetId, 'space.small');
      expect(answer['alreadyQueued'], isFalse);
      expect((answer['added'] as List).single, containsPair('id', whole.id));
      expect((answer['added'] as List).single, isNot(contains('sample')));

      final again = await client.call(Methods.queueConvertWhole, {
        'job': ids.single,
      });
      expect(again, {'added': isEmpty, 'alreadyQueued': true});
      expect(jobs(container), hasLength(2));

      await expectLater(
        client.call(Methods.queueConvertWhole, {'job': whole.id}),
        _failsWith(ControlErrorKind.badArgument, contains('sample')),
      );
    });

    test('convert anyway converts a video kept as it is', () async {
      final a = video('a.mp4');
      env.estimator.choices[a] = fakeChoice(QualityOutcome.notWorthIt);
      final (container, client) = await startControlled(env);
      final kept = (await queue(client, ['a.mp4'], goal: 'archive')).single;
      for (var i = 0; i < 100 && jobs(container).single.isPending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(jobs(container).single.keptAsIs, isTrue);

      final answer =
          await client.call(Methods.queueConvertAnyway, {'job': kept}) as Map;

      final anyway = jobs(container).last;
      expect(anyway.id, isNot(kept));
      expect(anyway.keptAsIs, isFalse);
      expect(answer['alreadyQueued'], isFalse);
      expect((answer['added'] as List).single, containsPair('id', anyway.id));
      await started(1);

      await expectLater(
        client.call(Methods.queueConvertAnyway, {'job': anyway.id}),
        _failsWith(ControlErrorKind.badArgument, contains('kept as it is')),
      );
    });

    test('a job that is not in the queue is not found', () async {
      final (_, client) = await startControlled(env);

      for (final (method, params) in [
        (Methods.queueMove, {'job': 7, 'position': 1}),
        (Methods.queueRetry, {'job': 7}),
        (Methods.queueConvertWhole, {'job': 7}),
        (Methods.queueConvertAnyway, {'job': 7}),
      ]) {
        await expectLater(
          client.call(method, params),
          _failsWith(ControlErrorKind.notFound, contains('7')),
          reason: method,
        );
      }
      await expectLater(
        client.call(Methods.queueRetry, {'job': 'first'}),
        _failsWith(ControlErrorKind.badArgument, contains('first')),
      );
    });
  });

  group('events and wait', () {
    /// Queues [names] to be made smaller through [client]; returns the job
    /// ids.
    Future<List<int>> queue(
      ControlConnection client,
      List<String> names,
    ) async {
      final answer = await client.call(Methods.queueAdd, {
        'videos': [for (final name in names) video(name)],
        'goal': 'space',
      }) as Map;
      return [for (final job in answer['added'] as List) (job as Map)['id']];
    }

    /// Until the window has read everything [client] sent before: it reads
    /// requests in order and answers `status` at once.
    Future<void> caughtUp(ControlConnection client) =>
        client.call(Methods.status);

    /// Until the fake executor has started [count] conversions.
    Future<void> started(int count) async {
      for (var i = 0; i < 100 && env.executor.started.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(env.executor.started, hasLength(count));
    }

    test(
      'a client sees each job finish while the rest still converts',
      () async {
        final (container, client) = await startControlled(env);
        final heard = Heard(client);
        final ids = await queue(client, ['a.mp4', 'b.mp4']);
        await client.call(Methods.subscribe, {'snapshot': false});
        await started(1);

        env.executor.started.first.finish();

        final finished = await heard.first(Events.jobFinished, job: ids.first);
        expect(finished.params['status'], 'done');
        expect(finished.params['outputPath'], isA<String>());
        expect(DateTime.tryParse(finished.params['time'] as String), isNotNull);
        await heard.first(Events.jobStarted, job: ids.last);
        expect(
          container.read(queueProvider).jobs.last.status,
          JobStatus.running,
        );
        expect(heard.names, isNot(contains(Events.snapshot)));
      },
    );

    test('subscribing first tells how everything stands', () async {
      final (_, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4']);
      final heard = Heard(client);

      expect(await client.call(Methods.subscribe), isEmpty);

      final snapshot = await heard.first(Events.snapshot);
      expect(heard.names.first, Events.snapshot);
      expect(
        (snapshot.params['videos'] as List).single,
        containsPair('path', endsWith('a.mp4')),
      );
      expect(
        (snapshot.params['jobs'] as List).single,
        containsPair('id', ids.single),
      );
      expect(snapshot.params['busy'], isTrue);
      expect(snapshot.params['paused'], isFalse);
    });

    test('events go only to clients that subscribed', () async {
      final shared = await Directory.systemTemp.createTemp('vidctrl_control_');
      addTearDown(() => shared.delete(recursive: true));
      final (_, subscribed) = await startControlled(env, dir: shared);
      final other = (await connectIfLive(controlFile(shared)))!;
      addTearDown(other.close);
      final heard = Heard(subscribed);
      final unheard = Heard(other);
      await subscribed.call(Methods.subscribe, {'snapshot': false});

      await other.call(Methods.videosAdd, {
        'paths': [video('a.mp4')],
      });

      final added = await heard.first(Events.videoAdded);
      expect(added.params['path'], endsWith('a.mp4'));
      await heard.first(Events.videoReady);
      expect(unheard.all, isEmpty);
    });

    test('progress is told at most once a second for each job', () async {
      final (_, client) = await startControlled(env);
      final heard = Heard(client);
      final ids = await queue(client, ['a.mp4']);
      await client.call(Methods.subscribe, {'snapshot': false});
      await started(1);

      final handle = env.executor.started.single;
      handle.report(0.1);
      handle.report(0.2);
      handle.report(0.3);
      handle.finish();
      await heard.first(Events.jobFinished, job: ids.single);

      final progress = [
        for (final n in heard.all)
          if (n.method == Events.jobProgress) n.params,
      ];
      expect(progress, hasLength(1));
      expect(progress.single, containsPair('fraction', 0.1));
      expect(progress.single, containsPair('job', ids.single));
    });

    test('a finished comparison is told', () async {
      final (container, client) = await startControlled(env);
      final heard = Heard(client);
      // Made no smaller in size: its frames pair with the original's.
      final hd = video('hd.mp4');
      env.ffprobe.add(hd, like: clip(width: 1920, height: 1080));
      await client.call(Methods.queueAdd, {
        'videos': [hd],
        'goal': 'space',
      });
      await client.call(Methods.subscribe, {'snapshot': false});
      await started(1);
      env.executor.started.single.finish();
      final job = await heard.first(Events.jobFinished);
      final done = container.read(queueProvider).jobs.single;
      expect(container.read(qualityProvider.notifier).canCompare(done), isTrue);

      unawaited(container.read(qualityProvider.notifier).compare(done));
      await pumpEventQueue();
      env.qualityMeter.last.finish(43, vmaf: 96);

      final compared = await heard.first(Events.compareFinished);
      expect(compared.params['job'], job.params['id']);
      expect(compared.params['closeness'], 'same');
    });

    test('wait returns when the queue is done, with each outcome', () async {
      final (_, client) = await startControlled(env);
      final ids = await queue(client, ['a.mp4', 'b.mp4']);
      var answered = false;
      final waiting = client.call(Methods.wait).then((answer) {
        answered = true;
        return answer as Map;
      });
      await caughtUp(client);
      await started(1);

      env.executor.started.first.finish();
      await started(2);
      expect(answered, isFalse);
      env.executor.started.last.fail();

      final outcomes = (await waiting)['outcomes'] as List;
      expect(outcomes.map((o) => ((o as Map)['jobId'], o['status'])), [
        (ids.first, 'done'),
        (ids.last, 'failed'),
      ]);
      expect((outcomes.first as Map)['outputPath'], isA<String>());
    });

    test('wait with nothing pending answers at once', () async {
      final (_, client) = await startControlled(env);

      expect(await client.call(Methods.wait), {'outcomes': isEmpty});
    });

    test('wait for an unknown job is not found', () async {
      final (_, client) = await startControlled(env);

      await expectLater(
        client.call(Methods.wait, {
          'jobs': [42],
        }),
        _failsWith(ControlErrorKind.notFound, contains('42')),
      );
    });

    test('a waiting client is told once that the queue is paused', () async {
      final (container, client) = await startControlled(env);
      final heard = Heard(client);
      await queue(client, ['a.mp4']);
      unawaited(client.call(Methods.wait).catchError((Object _) => null));
      await caughtUp(client);
      await started(1);

      container.read(queueProvider.notifier).pause();

      await heard.first(Events.queuePaused);
      expect(heard.names, [Events.queuePaused]);
    });

    test('a wait ends with app-closing when the window closes', () async {
      final (container, client) = await startControlled(env);
      final heard = Heard(client);
      await queue(client, ['a.mp4']);
      final waiting = expectLater(
        client.call(Methods.wait),
        _failsWith(ControlErrorKind.appClosed),
      );
      await caughtUp(client);
      await started(1);

      await container.read(controlProvider.notifier).stop();

      await waiting;
      await client.done.timeout(const Duration(seconds: 2));
      expect(heard.names, [Events.appClosing]);
    });

    test('a client that subscribes while the window stops is told '
        'nothing', () async {
      final (container, _) = await startControlled(env);
      final control = container.read(controlProvider.notifier);
      await control.stop();

      final peer = _Peer();
      control.subscribe(peer);
      await container.read(sourcesProvider.notifier).addPaths([video('a.mp4')]);

      expect(peer.told, isEmpty);
    });

    test('a peer whose socket drops is forgotten', () async {
      final shared = await Directory.systemTemp.createTemp('vidctrl_control_');
      addTearDown(() => shared.delete(recursive: true));
      final (container, client) = await startControlled(env, dir: shared);
      final ids = await queue(client, ['a.mp4', 'b.mp4']);
      await client.call(Methods.subscribe);
      unawaited(client.call(Methods.wait).catchError((Object _) => null));
      await caughtUp(client);
      await started(1);

      await client.close();
      await pumpEventQueue();
      env.executor.started.first.finish();
      await started(2);

      // The window goes on, and tells the clients still there.
      final later = (await connectIfLive(controlFile(shared)))!;
      addTearDown(later.close);
      final told = Heard(later);
      await later.call(Methods.subscribe, {'snapshot': false});
      env.executor.started.last.finish();
      await told.first(Events.jobFinished, job: ids.last);
      expect(container.read(queueProvider).jobs.map((j) => j.status), [
        JobStatus.done,
        JobStatus.done,
      ]);
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
