import 'dart:convert';
import 'dart:io';

/// Remembers the user's choices between runs: language, last goal, output
/// folder. Values are plain JSON (strings, numbers, maps, lists).
abstract interface class SettingsStore {
  Object? read(String key);

  /// Writes [value], or forgets the key when it is null.
  Future<void> write(String key, Object? value);
}

/// Settings kept in a JSON file. Everything is read once when opened, so
/// reading is instant; every change is written straight away.
class FileSettingsStore implements SettingsStore {
  FileSettingsStore._(this._file, this._values);

  final File _file;
  final Map<String, Object?> _values;

  /// The write under way: writes go one after another, as they share the
  /// file they are written aside to.
  Future<void> _writing = Future.value();

  /// A missing or damaged file starts from defaults rather than failing:
  /// losing a remembered language is better than not starting.
  static Future<FileSettingsStore> open(String path) async {
    final file = File(path);
    var values = <String, Object?>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) values = decoded;
    } on Object {
      // No settings yet, or unreadable ones.
    }
    return FileSettingsStore._(file, values);
  }

  @override
  Object? read(String key) => _values[key];

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    final written = _writing.then((_) => _save());
    // A failed write does not hold up the next one.
    _writing = written.then((_) {}, onError: (Object _) {});
    await written;
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    // Written aside and renamed, so a crash mid-write cannot leave a
    // half-written file behind.
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_values),
    );
    await temporary.rename(_file.path);
  }
}

/// Settings that last only as long as the app runs; used by tests.
class MemorySettingsStore implements SettingsStore {
  final values = <String, Object?>{};

  @override
  Object? read(String key) => values[key];

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
