import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Whether the computer is being kept awake now, as its operating system
/// agreed: the queue says so only then.
final keepingAwakeProvider = NotifierProvider<KeepingAwake, bool>(
  KeepingAwake.new,
);

class KeepingAwake extends Notifier<bool> {
  @override
  bool build() {
    final inhibitor = ref
        .watch(environmentProvider)
        .requireValue
        .sleepInhibitor;
    final listening = inhibitor.changes.listen((active) => state = active);
    // Not awaited: see the queue controller.
    ref.onDispose(listening.cancel);
    return inhibitor.isActive;
  }
}
