// Getting one picture out of FFmpeg, with a stand-in for it: a shell script.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/ffmpeg/picture.dart';

import '../../support/eventually.dart';

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('picture_test');
  });

  tearDown(() => folder.delete(recursive: true));

  String ffmpeg(String body) {
    final script = File(p.join(folder.path, 'ffmpeg'))
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  const second = Duration(seconds: 1);

  test('the picture FFmpeg writes', () async {
    final picture = await ffmpegPicture(
      ffmpeg("printf 'PNG'; echo 'a warning' >&2"),
      const [],
      timeout: second,
    );

    expect(String.fromCharCodes(picture!), 'PNG');
  });

  test('none when FFmpeg fails or writes nothing', () async {
    expect(
      await ffmpegPicture(
        ffmpeg("printf 'PNG'; exit 1"),
        const [],
        timeout: second,
      ),
      isNull,
    );
    expect(
      await ffmpegPicture(ffmpeg('true'), const [], timeout: second),
      isNull,
    );
  });

  test('none, and FFmpeg stopped, when it takes too long', () async {
    final pidFile = p.join(folder.path, 'pid');
    final picture = await ffmpegPicture(
      ffmpeg('echo \$\$ > $pidFile; exec sleep 30'),
      const [],
      timeout: const Duration(milliseconds: 300),
    );

    expect(picture, isNull);
    final pid = File(pidFile).readAsStringSync().trim();
    await eventually(() => Process.runSync('kill', ['-0', pid]).exitCode != 0);
  });

  test('none when there is no FFmpeg to run', () async {
    expect(
      await ffmpegPicture(
        p.join(folder.path, 'missing'),
        const [],
        timeout: second,
      ),
      isNull,
    );
  });
}
