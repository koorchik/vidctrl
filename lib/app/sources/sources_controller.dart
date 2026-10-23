import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media/ffprobe.dart';
import '../../core/media/media_info.dart';
import '../../core/media/video_files.dart';
import '../providers.dart';

enum SourceStatus { probing, ready, unreadable }

/// A file the user added. Each file appears once.
class SourceVideo {
  const SourceVideo({
    required this.id,
    required this.path,
    this.status = SourceStatus.probing,
    this.info,
  });

  final int id;
  final String path;
  final SourceStatus status;
  final MediaInfo? info;

  bool get isReady => status == SourceStatus.ready && info != null;

  SourceVideo copyWith({SourceStatus? status, MediaInfo? info}) => SourceVideo(
    id: id,
    path: path,
    status: status ?? this.status,
    info: info ?? this.info,
  );
}

class SourcesState {
  const SourcesState({this.videos = const [], this.selectedIds = const {}});

  final List<SourceVideo> videos;

  /// The videos the "What to do" panel applies to.
  final Set<int> selectedIds;

  /// Selected videos that can be converted.
  List<SourceVideo> get selectedReady => [
    for (final video in videos)
      if (video.isReady && selectedIds.contains(video.id)) video,
  ];

  List<SourceVideo> get ready => [
    for (final video in videos)
      if (video.isReady) video,
  ];

  SourceVideo? byId(int id) {
    for (final video in videos) {
      if (video.id == id) return video;
    }
    return null;
  }

  SourcesState copyWith({List<SourceVideo>? videos, Set<int>? selectedIds}) =>
      SourcesState(
        videos: videos ?? this.videos,
        selectedIds: selectedIds ?? this.selectedIds,
      );
}

final sourcesProvider = NotifierProvider<SourcesController, SourcesState>(
  SourcesController.new,
);

/// The list of videos the user added, and which of them are selected.
class SourcesController extends Notifier<SourcesState> {
  late AppEnvironment _env;
  var _nextId = 0;
  final _probes = <Future<void>>{};

  /// How many files are inspected at once when a folder is added.
  static const _probeConcurrency = 4;

  @override
  SourcesState build() {
    _env = ref.watch(environmentProvider).requireValue;
    return const SourcesState();
  }

  /// Completes when every file added so far has been inspected.
  Future<void> get settled => Future.wait(_probes.toList());

  /// Adds files, and the videos inside any folders. A file already in the
  /// list is not added again. The newly added videos become the selection,
  /// so they can be queued straight away.
  Future<List<int>> addPaths(Iterable<String> paths) async {
    final files = await expandDroppedPaths(paths);
    final known = {for (final video in state.videos) video.path: video.id};
    final ids = <int>[];
    final added = <SourceVideo>[];
    for (final path in files) {
      final id = known[path];
      if (id != null) {
        ids.add(id);
        continue;
      }
      final video = SourceVideo(id: _nextId++, path: path);
      known[path] = video.id;
      added.add(video);
      ids.add(video.id);
    }
    if (added.isEmpty) return ids;
    state = state.copyWith(
      videos: [...state.videos, ...added],
      selectedIds: {for (final video in added) video.id},
    );

    final queue = [...added];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        await _probe(queue.removeAt(0));
      }
    }

    final probing = Future.wait([
      for (var i = 0; i < _probeConcurrency; i++) worker(),
    ]);
    _probes.add(probing);
    await probing;
    _probes.remove(probing);
    return ids;
  }

  Future<void> _probe(SourceVideo video) async {
    try {
      final info = await _env.ffprobe.probe(video.path);
      _update(
        video.id,
        (v) => v.copyWith(status: SourceStatus.ready, info: info),
      );
    } on FfprobeException {
      _update(video.id, (v) => v.copyWith(status: SourceStatus.unreadable));
      state = state.copyWith(
        selectedIds: {...state.selectedIds}..remove(video.id),
      );
    }
  }

  /// Takes a video off the list. Jobs already queued for it are kept.
  void remove(int id) {
    state = state.copyWith(
      videos: [
        for (final v in state.videos)
          if (v.id != id) v,
      ],
      selectedIds: {...state.selectedIds}..remove(id),
    );
  }

  /// Selects just this video.
  void select(int id) {
    if (!_selectable(id)) return;
    state = state.copyWith(selectedIds: {id});
  }

  /// Adds the video to the selection, or takes it out.
  void toggle(int id) {
    if (!_selectable(id)) return;
    final selected = {...state.selectedIds};
    if (!selected.remove(id)) selected.add(id);
    state = state.copyWith(selectedIds: selected);
  }

  void selectAll() {
    state = state.copyWith(
      selectedIds: {
        for (final video in state.videos)
          if (video.status != SourceStatus.unreadable) video.id,
      },
    );
  }

  void clearSelection() => state = state.copyWith(selectedIds: const {});

  bool _selectable(int id) {
    final video = state.byId(id);
    return video != null && video.status != SourceStatus.unreadable;
  }

  void _update(int id, SourceVideo Function(SourceVideo) change) {
    state = state.copyWith(
      videos: [for (final v in state.videos) v.id == id ? change(v) : v],
    );
  }
}
