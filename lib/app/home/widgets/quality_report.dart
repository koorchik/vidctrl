import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_info.dart';
import '../../../core/quality/frame_grabber.dart';
import '../../../core/quality/quality_search.dart';
import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../technical_text.dart';

/// How a video's quality was settled, in one line: plain words coloured by
/// the outcome, the numbers in small type, and an (i) for the full story
/// where there is more to tell than "looks the same".
class QualityChoiceLine extends StatelessWidget {
  const QualityChoiceLine({
    super.key,
    required this.choice,
    required this.original,
    this.result,
  });

  final QualityChoice choice;

  /// The video the choice is for.
  final MediaInfo original;

  /// The converted whole video, once there is one, to show its frame.
  final String? result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = SuccessColors.of(context).text;
    final format = Formatter(l10n);
    final chosen = choice.chosen;
    final scores = [
      if (chosen.score.vmaf case final vmaf?)
        l10n.vmafScore(format.score(vmaf)),
      l10n.xpsnrScore(format.score(chosen.score.lumaDb)),
    ];
    final (words, color, technical) = switch (choice.outcome) {
      QualityOutcome.standard => (l10n.closenessSame, success, scores),
      QualityOutcome.raised => (
        l10n.qualityRaised,
        success,
        ['CRF ${choice.standardValue} → ${choice.value}', ...scores],
      ),
      QualityOutcome.belowTarget => (
        l10n.qualityCheckByEye,
        scheme.tertiary,
        [if (choice.value case final value?) 'CRF $value', ...scores],
      ),
      QualityOutcome.notWorthIt => (
        choice.share >= 1
            ? l10n.qualityNotSmaller
            : l10n.qualityNotWorthIt(savedPercent(choice)),
        scheme.tertiary,
        [...scores, l10n.qualitySizeShare(sharePercent(choice))],
      ),
    };
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final details = choice.outcome == QualityOutcome.standard
        ? null
        : QualityDetailsButton(
            choice: choice,
            original: original,
            result: result,
            color: color,
          );
    // The words are what matters: whole where they fit, the numbers taking
    // what room is left; cut short only where even they do not fit.
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: words, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final fits =
              painter.width + (details == null ? 0 : 26) + 40 <=
              constraints.maxWidth;
          painter.dispose();
          final text = Text(
            words,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
          return Row(
            children: [
              if (fits) text else Flexible(child: text),
              ?details,
              if (fits) ...[
                const SizedBox(width: 8),
                Expanded(child: TechnicalText(technical.join('  ·  '))),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A tag beside a video's name when the archive tuned its quality: it chose
/// a better one than usual for it. In the accent where that was enough, in
/// the colour of things worth noticing where the video still needs a look.
/// Opens [QualityReportDialog].
class QualityBadge extends StatelessWidget {
  const QualityBadge({
    super.key,
    required this.choice,
    required this.original,
    this.result,
  });

  final QualityChoice choice;
  final MediaInfo original;
  final String? result;

  /// Whether [choice] changed the quality the video is converted at.
  static bool shows(QualityChoice? choice) =>
      choice != null &&
      choice.converts &&
      choice.value != null &&
      choice.value != choice.standardValue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    final needsALook = choice.outcome == QualityOutcome.belowTarget;
    final (background, foreground) = needsALook
        ? (scheme.tertiaryContainer, scheme.onTertiaryContainer)
        : (
            look.hues?.violet.soft ?? scheme.primaryContainer,
            look.hues?.violet.deep ?? scheme.onPrimaryContainer,
          );
    final radius = BorderRadius.circular(look.tagRadius);
    return Tooltip(
      message: l10n.qualityTunedHint,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: foreground.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => QualityReportDialog(
              choice: choice,
              original: original,
              result: result,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 12, color: foreground),
                const SizedBox(width: 4),
                Text(
                  l10n.qualityTuned,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
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

/// The share of the original's size a result keeps, in whole percent.
int sharePercent(QualityChoice choice) => (choice.share * 100).round();

/// The share of the original's size converting would free, in whole percent.
int savedPercent(QualityChoice choice) => 100 - sharePercent(choice);

/// The (i) that opens [QualityReportDialog].
class QualityDetailsButton extends StatelessWidget {
  const QualityDetailsButton({
    super.key,
    required this.choice,
    required this.original,
    this.result,
    this.color,
  });

  final QualityChoice choice;
  final MediaInfo original;
  final String? result;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // No taller than the line of text it ends.
    return Tooltip(
      message: l10n.qualityDetails,
      child: InkResponse(
        radius: 14,
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => QualityReportDialog(
            choice: choice,
            original: original,
            result: result,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(Icons.info_outline_rounded, size: 15, color: color),
        ),
      ),
    );
  }
}

/// Why a video got the quality it did: what happened in plain words, what
/// was tried, and where the result still falls short, its hardest frame
/// beside the original's, at real size.
class QualityReportDialog extends ConsumerWidget {
  const QualityReportDialog({
    super.key,
    required this.choice,
    required this.original,
    this.result,
  });

  final QualityChoice choice;
  final MediaInfo original;

  /// The converted whole video; before converting, the piece encoded while
  /// measuring stands in for it.
  final String? result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = SuccessColors.of(context).text;
    final (icon, color, title, body) = switch (choice.outcome) {
      QualityOutcome.standard || QualityOutcome.raised => (
        Icons.verified_rounded,
        success,
        l10n.qualityReportRaisedTitle,
        l10n.qualityReportRaised,
      ),
      QualityOutcome.belowTarget => (
        Icons.visibility_rounded,
        scheme.tertiary,
        l10n.qualityReportBelowTitle,
        [
          l10n.qualityReportBelow,
          if (choice.value == null) l10n.qualityReportBelowGpu,
        ].join('\n\n'),
      ),
      QualityOutcome.notWorthIt => (
        Icons.inventory_2_outlined,
        scheme.tertiary,
        l10n.qualityReportKeptTitle,
        choice.share >= 1
            ? l10n.qualityReportKeptLarger
            : l10n.qualityReportKept(sharePercent(choice)),
      ),
    };
    final hardest = choice.chosen.hardest;
    final showsFrames =
        choice.outcome == QualityOutcome.belowTarget && hardest != null;
    final size = MediaQuery.sizeOf(context);

    final header = [
      Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: theme.textTheme.headlineSmall)),
        ],
      ),
      const SizedBox(height: 14),
      Text(body, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 12),
      _Trials(choice: choice),
    ];
    final close = Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.close),
      ),
    );

    if (!showsFrames) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...header, const SizedBox(height: 8), close],
              ),
            ),
          ),
        ),
      );
    }

    final grabber = ref.watch(environmentProvider).requireValue.frameGrabber;
    final fps = original.video?.frameRate ?? 30;
    final at =
        hardest.pieceStart +
        Duration(microseconds: (hardest.frame / fps * 1e6).round());
    final source = result != null
        ? (path: result!, seek: hardest.pieceStart)
        : hardest.encodedPiece != null
        ? (path: hardest.encodedPiece!, seek: Duration.zero)
        : null;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: max(560, size.width - 48),
        height: max(480, size.height - 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...header,
              const SizedBox(height: 16),
              Text(
                l10n.qualityFrameTitle(Formatter(l10n).clock(at)),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FrameCompare(
                  load: () async => grabber == null || source == null
                      ? null
                      : grabber.pair(
                          original: original.path,
                          originalSeek: hardest.pieceStart,
                          result: source.path,
                          resultSeek: source.seek,
                          frame: hardest.frame,
                        ),
                ),
              ),
              close,
            ],
          ),
        ),
      ),
    );
  }
}

/// Each quality tried, with its scores and size; the chosen one marked.
class _Trials extends StatelessWidget {
  const _Trials({required this.choice});

  final QualityChoice choice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final format = Formatter(l10n);
    String line(QualityTrial trial) => [
      if (trial.value case final value?) 'CRF $value',
      if (trial.score.vmaf case final vmaf?) l10n.vmafScore(format.score(vmaf)),
      l10n.xpsnrScore(format.score(trial.score.lumaDb)),
      l10n.qualitySizeShare(
        (trial.bytes * 100 / max(1, choice.sourceBytes)).round(),
      ),
      if (identical(trial, choice.chosen) && choice.trials.length > 1)
        l10n.qualityChosen,
    ].join('  ·  ');
    final sorted = [...choice.trials]
      ..sort((a, b) => (b.value ?? 0).compareTo(a.value ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final trial in sorted) TechnicalText(line(trial)),
        TechnicalText(l10n.qualityPieces(max(1, choice.chosen.pieces))),
      ],
    );
  }
}

/// The original's and the result's picture of one frame, in one place at
/// real size: a person switches between them (or holds Space for the
/// original) and sees what changes, which two pictures side by side hide.
/// Dragging moves around a picture larger than the window.
class FrameCompare extends StatefulWidget {
  const FrameCompare({super.key, required this.load});

  /// Reads the two pictures, once: null when they could not be read.
  final Future<FramePair?> Function() load;

  @override
  State<FrameCompare> createState() => _FrameCompareState();
}

class _FrameCompareState extends State<FrameCompare> {
  var _original = false;
  var _held = false;
  var _fit = false;
  final _focus = FocusNode();
  final _transform = TransformationController();
  Size? _centredFor;

  /// Asked for once, not on every rebuild: the dialog rebuilds as the window
  /// is resized, and each read runs FFmpeg on a full-size frame.
  late final Future<FramePair?> _frames = widget.load();

  @override
  void dispose() {
    _focus.dispose();
    _transform.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent || event is KeyUpEvent) {
      setState(() => _held = event is KeyDownEvent);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<FramePair?>(
      future: _frames,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(l10n.qualityFrameLoading),
              ],
            ),
          );
        }
        final pair = snapshot.data;
        if (pair == null) {
          return Center(
            child: Text(
              l10n.qualityFrameMissing,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          );
        }
        final showOriginal = _original || _held;
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(l10n.qualityFrameOriginal),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.qualityFrameResult),
                      ),
                    ],
                    selected: {showOriginal},
                    onSelectionChanged: (chosen) {
                      setState(() => _original = chosen.single);
                      _focus.requestFocus();
                    },
                  ),
                  FilterChip(
                    label: Text(l10n.qualityFrameFit),
                    selected: _fit,
                    onSelected: (fit) {
                      setState(() => _fit = fit);
                      _focus.requestFocus();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.qualityFrameHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRect(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: _pictures(context, pair, showOriginal),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pictures(BuildContext context, FramePair pair, bool showOriginal) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // Both are kept decoded, so switching shows the other at once.
    Widget picture(Uint8List bytes, bool shown) => Offstage(
      offstage: !shown,
      child: Image.memory(
        bytes,
        // One dot of the picture for one dot of the screen.
        scale: _fit ? 1 : ratio,
        gaplessPlayback: true,
        filterQuality: _fit ? FilterQuality.medium : FilterQuality.none,
      ),
    );
    final both = Stack(
      children: [
        picture(pair.original, showOriginal),
        picture(pair.result, !showOriginal),
      ],
    );
    final label = Positioned(
      left: 8,
      top: 8,
      child: _Tag(
        showOriginal
            ? AppLocalizations.of(context)!.qualityFrameOriginal
            : AppLocalizations.of(context)!.qualityFrameResult,
      ),
    );
    if (_fit) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(child: both),
          label,
        ],
      );
    }
    final picturePixels = pngSize(pair.result);
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.biggest;
        final picture = picturePixels == null ? view : picturePixels / ratio;
        // At least as large as the view, so a smaller picture sits in its
        // middle and a larger one can be dragged to every edge.
        final canvas = Size(
          max(view.width, picture.width),
          max(view.height, picture.height),
        );
        // Starts on the middle of the picture, where people look first,
        // and goes back there when the window changes size. The first time
        // it is set before the viewer listens; later, after the frame.
        final middle = Matrix4.translationValues(
          (view.width - canvas.width) / 2,
          (view.height - canvas.height) / 2,
          0,
        );
        if (_centredFor == null) {
          _transform.value = middle;
        } else if (_centredFor != view) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _transform.value = middle;
          });
        }
        _centredFor = view;
        return Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              scaleEnabled: false,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox.fromSize(
                size: canvas,
                child: Center(child: both),
              ),
            ),
            label,
          ],
        );
      },
    );
  }
}

/// Width and height of a PNG, read from its header; null for anything else.
Size? pngSize(Uint8List png) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (png.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (png[i] != signature[i]) return null;
  }
  final header = ByteData.sublistView(png, 16, 24);
  return Size(header.getUint32(0).toDouble(), header.getUint32(4).toDouble());
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
