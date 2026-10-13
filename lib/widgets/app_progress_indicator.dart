import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:spotiflac_android/theme/material_expressive.dart';

/// Task progress (downloads, scans, updates), determinate or not.
///
/// The Material theme draws the expressive wavy indicators. Mornye and
/// reduced motion keep Flutter's flat indicators with the same parameters.
class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator.linear({
    super.key,
    this.value,
    this.color,
    this.trackColor,
    this.minHeight,
    this.borderRadius,
    this.semanticsLabel,
  }) : strokeWidth = null,
       strokeCap = null,
       _circular = false;

  /// Fills the smaller side of its parent, or 48dp when unbounded.
  const AppProgressIndicator.circular({
    super.key,
    this.value,
    this.color,
    this.trackColor,
    this.strokeWidth,
    this.strokeCap,
    this.semanticsLabel,
  }) : minHeight = null,
       borderRadius = null,
       _circular = true;

  /// Progress in `0..1`, or null for indeterminate.
  final double? value;
  final Color? color;
  final Color? trackColor;

  /// Height of the flat linear fallback; the wavy track keeps its own height.
  final double? minHeight;
  final BorderRadiusGeometry? borderRadius;
  final double? strokeWidth;

  /// Cap of the flat circular fallback; the wavy stroke is always round.
  final StrokeCap? strokeCap;
  final String? semanticsLabel;
  final bool _circular;

  @override
  Widget build(BuildContext context) {
    final value = this.value?.clamp(0.0, 1.0);
    if (!materialExpressiveEnabled(context)) {
      return _circular
          ? CircularProgressIndicator(
              value: value,
              color: color,
              backgroundColor: trackColor,
              strokeWidth: strokeWidth,
              strokeCap: strokeCap,
              semanticsLabel: semanticsLabel,
            )
          : LinearProgressIndicator(
              value: value,
              color: color,
              backgroundColor: trackColor,
              minHeight: minHeight,
              borderRadius: borderRadius,
              semanticsLabel: semanticsLabel,
            );
    }
    final scheme = Theme.of(context).colorScheme;
    if (!_circular) {
      return MaterialExpressiveScope(
        child: M3EProgressIndicator.linearWavy(
          value: value,
          color: color ?? scheme.primary,
          trackColor: trackColor,
          semanticsLabel: semanticsLabel,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return MaterialExpressiveScope(
          child: M3EProgressIndicator.circularWavy(
            value: value,
            size: side.isFinite ? side : null,
            color: color ?? scheme.primary,
            trackColor: trackColor,
            strokeWidth: strokeWidth,
            trackStrokeWidth: strokeWidth,
            semanticsLabel: semanticsLabel,
          ),
        );
      },
    );
  }
}
