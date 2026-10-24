import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidctrl/core/settings/settings_store.dart';

void main() {
  late Directory folder;
  late String path;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('settings_store_test');
    path = p.join(folder.path, 'settings.json');
  });

  tearDown(() => folder.delete(recursive: true));

  test('settings are there the next time the app starts', () async {
    final store = await FileSettingsStore.open(path);
    await store.write('language', 'uk');
    await store.write('look', 'pro');
    await store.write('look', null);

    final again = await FileSettingsStore.open(path);

    expect(again.read('language'), 'uk');
    expect(again.read('look'), isNull);
  });

  test('quick clicks writing at once all get written, whole', () async {
    final store = await FileSettingsStore.open(path);

    await Future.wait([
      for (var i = 0; i < 50; i++) store.write('option$i', i),
    ]);

    final saved = jsonDecode(await File(path).readAsString()) as Map;
    expect(saved, hasLength(50));
    expect(saved['option49'], 49);
    expect(folder.listSync().map((f) => p.basename(f.path)), ['settings.json']);
  });

  test('a damaged file starts from the defaults', () async {
    await File(path).writeAsString('{"language": "uk"');

    final store = await FileSettingsStore.open(path);

    expect(store.read('language'), isNull);
    await store.write('language', 'en');
    expect((await FileSettingsStore.open(path)).read('language'), 'en');
  });
}
