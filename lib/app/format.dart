import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../core/media/media_info.dart';
import '../l10n/app_localizations.dart';

/// Human-readable sizes, durations and video descriptions.
class Formatter {
  Formatter(this.l10n);

  final AppLocalizations l10n;

  /// `1.2 GB`, `340 MB`. Decimal units, as file managers show them.
  String bytes(int bytes) {
    final (double value, String unit) = switch (bytes) {
      >= 1000000000 => (bytes / 1e9, l10n.unitGB),
      >= 1000000 => (bytes / 1e6, l10n.unitMB),
      _ => (bytes / 1e3, l10n.unitKB),
    };
    final pattern = value >= 100 || unit == l10n.unitKB ? '#,##0' : '#,##0.0';
    return '${NumberFormat(pattern, l10n.localeName).format(value)} $unit';
  }

  /// A length of video as a clock reading: `2:31`, `1:05:09`.
  String clock(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  /// A waiting time in words, rounded to what a person needs: seconds below a
  /// minute, minutes below an hour.
  String wait(Duration d) {
    if (d.inSeconds < 60) return l10n.durationSeconds(d.inSeconds.clamp(1, 59));
    final minutes = (d.inSeconds / 60).round();
    if (minutes < 60) return l10n.durationMinutes(minutes);
    return l10n.durationHours(minutes ~/ 60, minutes % 60);
  }

  /// The resolution as people name it: `4K`, `1080p`.
  String resolution(VideoStream video) {
    final long = video.width > video.height ? video.width : video.height;
    final short = video.width > video.height ? video.height : video.width;
    if (long >= 7680) return '8K';
    if (long >= 3840) return '4K';
    if (short >= 1440) return '1440p';
    if (short >= 1080) return '1080p';
    if (short >= 720) return '720p';
    return '${video.width}×${video.height}';
  }

  /// One line about a file: `4K · 2:31 · 1.2 GB`.
  String summary(MediaInfo info) => [
    if (info.video != null) resolution(info.video!),
    clock(info.duration),
    bytes(info.sizeBytes),
  ].join(' · ');

  String fileName(String path) => p.basename(path);

  /// `71% smaller` or `240% larger`.
  String sizeChange(int before, int after) {
    if (before <= 0) return '';
    final percent = ((after - before) * 100 / before).round();
    return percent <= 0
        ? l10n.percentSmaller(-percent)
        : l10n.percentLarger(percent);
  }

  /// `240% larger`, or null when the size did not grow: what a line shows
  /// in another colour.
  String? largerBy(int before, int after) {
    final change = sizeChange(before, after);
    return before > 0 && ((after - before) * 100 / before).round() > 0
        ? change
        : null;
  }
}
