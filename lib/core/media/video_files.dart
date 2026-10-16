import 'dart:io';

import 'package:path/path.dart' as p;

/// File extensions treated as video when a folder is added. Individual files
/// the user picks are always tried, whatever their extension.
const videoExtensions = {
  '.mp4',
  '.mov',
  '.mkv',
  '.m4v',
  '.avi',
  '.mts',
  '.m2ts',
  '.ts',
  '.mxf',
  '.webm',
  '.wmv',
  '.flv',
  '.3gp',
  '.mpg',
  '.mpeg',
};

bool looksLikeVideo(String path) =>
    videoExtensions.contains(p.extension(path).toLowerCase());

/// The extensions for the file dialog's filter, without the dot. GTK on
/// Linux matches them case-sensitively, which would hide a camera's
/// `DSC_0001.MOV`, so there each letter is given in both cases:
/// `[mM][oO][vV]`.
List<String> dialogExtensions({required bool linux}) => [
  for (final e in videoExtensions)
    linux
        ? e
              .substring(1)
              .replaceAllMapped(
                RegExp('[a-z]'),
                (m) => '[${m[0]}${m[0]!.toUpperCase()}]',
              )
        : e.substring(1),
];

/// Turns what the user dropped into a list of files: files are kept as they
/// are, folders are searched for videos, including subfolders. Hidden files
/// and folders are skipped, which also keeps the app's own unfinished
/// outputs out.
Future<List<String>> expandDroppedPaths(Iterable<String> paths) async {
  final files = <String>[];
  for (final path in paths) {
    if (await FileSystemEntity.isDirectory(path)) {
      final found = <String>[];
      await for (final entity in Directory(path).list(recursive: true)) {
        if (entity is! File || !looksLikeVideo(entity.path)) continue;
        final relative = p.relative(entity.path, from: path);
        if (p.split(relative).any((part) => part.startsWith('.'))) continue;
        found.add(entity.path);
      }
      files.addAll(found..sort());
    } else {
      files.add(path);
    }
  }
  return files;
}
