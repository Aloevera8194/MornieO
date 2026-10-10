import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

/// A bounded package lens without a captured-screen view or a touch ticker.
class MornyeLiquidBackdrop extends StatelessWidget {
  const MornyeLiquidBackdrop({
    super.key,
    required this.borderRadius,
    required this.clarity,
    required this.blurSigma,
    required this.child,
    this.interaction = false,
    this.progress = 1,
    this.refractionDepth = 0.30,
    this.refractionWidth = 20,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
  });

  final BorderRadius borderRadius;
  final double clarity;
  final double blurSigma;
  final Widget child;
  final bool interaction;
  final double progress;
  final double refractionDepth;
  final double refractionWidth;
  final bool smoothCorners;
  final double highlightIntensity;

  @override
  Widget build(BuildContext context) {
    if (interaction && progress <= 0) return child;
    final effect = interaction ? progress : 1.0;
    final outlines = MornyeTheme.glassOutlinesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: LiquidGlassShape(
          cornerStyle: smoothCorners
              ? LiquidGlassCornerStyle.squircle
              : LiquidGlassCornerStyle.roundedRectangle,
          clipQuality: smoothCorners
              ? LiquidGlassClipQuality.exact
              : LiquidGlassClipQuality.roundedRectangle,
          cornerRadius: borderRadius.topLeft.x,
          borderWidth: outlines ? 0.75 : 0,
          lightDirection: 0,
          lightIntensity: outlines
              ? (dark ? 0.25 : 0.12) * effect * highlightIntensity
              : 0,
          lightColor: dark ? Colors.white : const Color(0x88ffffff),
          borderType: OpticalBorder(
            ambientIntensity: 0.05 * highlightIntensity,
            lightSpread: 0.2,
          ),
        ),
        appearance: LiquidGlassAppearance(
          blur: LiquidGlassBlur(sigmaX: blurSigma, sigmaY: blurSigma),
        ),
        // Translate Figma percentages into this package's optical controls.
        // Keep color separation subtle instead of copying its contrast demo.
        refraction: LiquidGlassRefraction(
          refractionType: OpticalRefraction(
            refraction: 1.7,
            depth: refractionDepth * effect,
            refractionWidth: refractionWidth,
          ),
          chromaticAberration: 0.002 * clarity * effect,
        ),
      ),
      child: child,
    );
  }
}
