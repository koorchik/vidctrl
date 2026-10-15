import 'package:flutter/material.dart';

import '../theme.dart';

/// A line of text in which a "55% larger" stands out by colour. A conversion
/// is rarely meant to make a file bigger, so that should not read like the
/// rest of the line, which may be the green of a finished job.
class SizeChangeText extends StatelessWidget {
  const SizeChangeText(
    this.text, {
    super.key,
    required this.larger,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;

  /// The "N% larger" within [text] (`Formatter.largerBy`), or null when the
  /// size did not grow.
  final String? larger;

  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final larger = this.larger;
    final at = larger == null ? -1 : text.indexOf(larger);
    if (larger == null || at < 0) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    // Amber, for caution, in both looks: Professional's colour for things
    // worth noticing is amber already.
    final color =
        AppLook.of(context).hues?.amber.deep ??
        Theme.of(context).colorScheme.tertiary;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: larger,
            style: TextStyle(color: color),
          ),
          TextSpan(text: text.substring(at + larger.length)),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
