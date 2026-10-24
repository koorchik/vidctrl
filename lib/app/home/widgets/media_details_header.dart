import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/media/media_details.dart';
import '../../../core/media/media_info.dart';
import '../../../l10n/app_localizations.dart';
import '../../format.dart';
import '../../theme.dart';
import '../technical_text.dart';

/// A frame of the video, its name and where it is, and the facts people ask
/// about first.
class MediaDetailsHeader extends StatelessWidget {
  const MediaDetailsHeader({
    super.key,
    required this.info,
    required this.thumbnail,
  });

  final MediaInfo info;
  final Future<Uint8List?> thumbnail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = Formatter(l10n);
    final video = info.video;
    final audio = info.audio.firstOrNull;
    final rate = video?.frameRate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(
            thumbnail: thumbnail,
            duration: format.clock(info.duration),
            audioOnly: video == null,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  p.basename(info.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.dirname(info.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (video != null) ...[
                      _Fact(
                        Icons.aspect_ratio_rounded,
                        '${format.resolution(video)}  '
                        '${video.width}×${video.height}',
                        kind: 0,
                      ),
                      _Fact(Icons.movie_outlined, sourceFormat(video), kind: 1),
                      if (video.color.isHdr)
                        _Fact(
                          Icons.hdr_on_rounded,
                          video.color.transfer == 'smpte2084' ? 'HDR10' : 'HLG',
                          highlight: true,
                        ),
                      if (rate != null)
                        _Fact(
                          Icons.speed_rounded,
                          '${_trim(rate.toStringAsFixed(2))} fps',
                          kind: 2,
                        ),
                    ],
                    if (audio != null)
                      _Fact(
                        Icons.graphic_eq_rounded,
                        '${audioFormat(audio)}  ${_channels(audio.channels)}',
                        kind: 3,
                      ),
                    _Fact(
                      Icons.sd_storage_outlined,
                      format.bytes(info.sizeBytes),
                      kind: 4,
                    ),
                    if (info.bitRate case final bitRate?)
                      _Fact(
                        Icons.data_usage_rounded,
                        formatBitrate(bitRate),
                        kind: 5,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.close,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  static String _trim(String number) =>
      number.replaceFirst(RegExp(r'\.?0+$'), '');

  static String _channels(int channels) => switch (channels) {
    1 => 'mono',
    2 => 'stereo',
    6 => '5.1',
    8 => '7.1',
    _ => '$channels ch',
  };
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.thumbnail,
    required this.duration,
    required this.audioOnly,
  });

  final Future<Uint8List?> thumbnail;
  final String duration;
  final bool audioOnly;

  @override
  Widget build(BuildContext context) {
    final look = AppLook.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(look.panelRadius),
      child: SizedBox(
        width: 192,
        height: 108,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Shown until the frame arrives, and for files without one.
            ColoredBox(
              color: look.badge.soft,
              child: Icon(
                audioOnly ? Icons.graphic_eq_rounded : Icons.movie_outlined,
                size: 40,
                color: look.badge.deep.withValues(alpha: 0.7),
              ),
            ),
            FutureBuilder<Uint8List?>(
              future: thumbnail,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                );
              },
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(look.tagRadius),
                ),
                child: Text(
                  duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One key fact as a small rounded label.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, {this.highlight = false, this.kind = 0});

  final IconData icon;
  final String text;

  /// For facts worth noticing, such as HDR.
  final bool highlight;

  /// Which fact of the row this is; each gets its own colour, where the
  /// look has colours.
  final int kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = AppLook.of(context);
    final hue = highlight ? null : look.hues?.at(kind);
    final background = highlight
        ? scheme.tertiaryContainer
        : hue?.soft ?? scheme.surfaceContainerHighest;
    final foreground = highlight
        ? scheme.onTertiaryContainer
        : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(look.tagRadius),
        border: Border.all(
          color: highlight
              ? scheme.tertiary.withValues(alpha: 0.4)
              : hue?.soft ?? scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: hue?.deep ?? foreground.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
