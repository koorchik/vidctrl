import 'package:flutter/material.dart';

/// A small spinner as tall as a line of small text, beside words that say
/// something is being worked out ("measuring size and quality…"), so it is
/// seen to be under way.
class BusyMark extends StatelessWidget {
  const BusyMark({super.key, this.color});

  /// The accent where null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 11,
      child: CircularProgressIndicator(
        strokeWidth: 1.6,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
