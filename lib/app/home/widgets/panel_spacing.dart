import 'package:flutter/material.dart';

/// How much air the panel's rows get. Compact at the smallest window size,
/// where everything must still fit; roomier when there is height to spare.
class PanelSpacing extends InheritedWidget {
  const PanelSpacing({super.key, required this.roomy, required super.child});

  /// Width of the label column of the option rows.
  static const labelWidth = 84.0;

  /// Panel height from which the roomier spacing is used.
  static const roomyFrom = 700.0;

  /// Panel height from which the goal's explanation fits beside two options
  /// that explain themselves (the archive's format and speed), in the
  /// compact spacing too: a 705 px window.
  static const explainedFrom = 615.0;

  final bool roomy;

  /// False outside the panel, e.g. in the extra-options window.
  static bool isRoomy(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelSpacing>()?.roomy ??
      false;

  /// Space between rows.
  static double gap(BuildContext context) => isRoomy(context) ? 16 : 10;

  /// Height of a goal tile.
  static double tileHeight(BuildContext context) => isRoomy(context) ? 58 : 50;

  /// Space above and below the text of a segmented button.
  static double segmentPadding(BuildContext context) =>
      isRoomy(context) ? 6 : 2;

  @override
  bool updateShouldNotify(PanelSpacing oldWidget) => roomy != oldWidget.roomy;
}

class PanelGap extends StatelessWidget {
  const PanelGap({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: PanelSpacing.gap(context));
}
