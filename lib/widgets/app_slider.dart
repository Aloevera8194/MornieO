import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:spotiflac_android/theme/material_expressive.dart';

/// Settings slider with the Material 3 Expressive track and handle.
/// Mornye and reduced motion keep the standard [Slider].
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticFormatterCallback,
    this.trackThickness,
    this.thumbLength,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final SemanticFormatterCallback? semanticFormatterCallback;

  /// Expressive track height; a secondary control can sit thinner than the
  /// default extra-small track.
  final double? trackThickness;

  /// Expressive handle height; shorten it together with a thinner track so
  /// the handle stays in proportion.
  final double? thumbLength;

  @override
  Widget build(BuildContext context) {
    if (!materialExpressiveEnabled(context)) {
      return Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      );
    }
    return MaterialExpressiveScope(
      child: M3ESlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        trackThickness: trackThickness,
        thumbLength: thumbLength,
        enabled: onChanged != null,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
