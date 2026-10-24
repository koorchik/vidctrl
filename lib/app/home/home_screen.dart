import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../queue/queue_controller.dart';
import '../sources/sources_controller.dart';
import '../theme.dart';
import 'widgets/app_header.dart';
import 'widgets/queue_pane.dart';
import 'widgets/recipe_pane.dart';
import 'widgets/videos_pane.dart';

/// The whole app on one screen: the videos above the queue on the left, and
/// what to do with the selected videos on the right.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final environment = ref.watch(environmentProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppLook.of(context).backdrop),
        child: SafeArea(
          child: environment.when(
            loading: () => _WithHeader(
              _Message(
                icon: const CircularProgressIndicator(),
                title: l10n.startingUp,
              ),
            ),
            error: (_, _) => _WithHeader(
              _Message(
                icon: Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: l10n.engineMissingTitle,
                body: l10n.engineMissingBody,
              ),
            ),
            data: (_) => const _Workspace(),
          ),
        ),
      ),
    );
  }
}

/// Around the panes and between them; the header takes the place of the
/// margin above them.
const _margin = 20.0;

/// The line around the window that lights up while files are dragged over.
const _dropBorder = 2.0;

/// A screen other than the workspace, under the header, which sits where it
/// does over the workspace.
class _WithHeader extends StatelessWidget {
  const _WithHeader(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _margin + _dropBorder,
        _dropBorder,
        _margin + _dropBorder,
        _margin + _dropBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Workspace extends ConsumerStatefulWidget {
  const _Workspace();

  @override
  ConsumerState<_Workspace> createState() => _WorkspaceState();
}

/// Width of the "What to do" panel.
const _panelWidth = 440.0;

class _WorkspaceState extends ConsumerState<_Workspace> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sources = ref.read(sourcesProvider.notifier);
    final queueEmpty = ref.watch(queueProvider.select((q) => q.jobs.isEmpty));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            sources.clearSelection,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            sources.selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            sources.selectAll,
      },
      child: Focus(
        autofocus: true,
        // Files and folders can be dropped anywhere in the window, at any
        // time, including while converting.
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            unawaited(sources.addPaths(details.files.map((f) => f.path)));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(_margin, 0, _margin, _margin),
            decoration: BoxDecoration(
              color: _dragging
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
              border: Border.all(
                color: _dragging ? scheme.primary : Colors.transparent,
                width: _dropBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppHeader(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // An empty queue shrinks to its one line of
                            // explanation and the videos take the room.
                            Expanded(flex: 9, child: const VideosPane()),
                            const SizedBox(height: 16),
                            if (queueEmpty)
                              const QueuePane()
                            else
                              const Expanded(flex: 11, child: QueuePane()),
                          ],
                        ),
                      ),
                      const SizedBox(width: _margin),
                      const SizedBox(width: _panelWidth, child: RecipePane()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.body});

  final Widget icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
