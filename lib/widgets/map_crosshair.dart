import 'package:flutter/material.dart';

/// Reusable high-contrast Map Center Crosshair overlay.
///
/// Responsive sizing:
/// - Screen width < 600 (Mobile): 56x56 px
/// - Screen width >= 600 (Desktop/Web): 64x64 px
///
/// Wrapped in [IgnorePointer] so map gestures pass through unimpeded.
class MapCrosshair extends StatelessWidget {
  final bool isTargetAcquired;
  final double? size;

  const MapCrosshair({super.key, this.isTargetAcquired = false, this.size});

  /// Helper to calculate responsive crosshair size based on device layout.
  static double getResponsiveSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 ? 64.0 : 56.0;
  }

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? getResponsiveSize(context);
    final isDesktop = dimension >= 60.0;

    // Reticle styling
    final accentColor = isTargetAcquired
        ? const Color(0xFF00E5FF) // High-contrast bright cyan
        : const Color(0xFF00B0FF); // Vibrant cyan
    final outerRingColor = Colors.white.withValues(alpha: 0.85);
    final darkShadowColor = Colors.black.withValues(alpha: 0.60);

    final lineThickness = isDesktop ? 2.5 : 2.0;
    final lineLength = isDesktop ? 14.0 : 12.0;
    final gapFromCenter = isDesktop ? 6.0 : 5.0;

    return IgnorePointer(
      child: SizedBox(
        width: dimension,
        height: dimension,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dark glow backdrop for contrast over both light & dark map regions
            Container(
              width: dimension - 8,
              height: dimension - 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isTargetAcquired
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.45)
                        : darkShadowColor,
                    blurRadius: isTargetAcquired ? 12 : 8,
                    spreadRadius: isTargetAcquired ? 2 : 1,
                  ),
                ],
              ),
            ),

            // Outer subtle white ring / reticle brackets
            Container(
              width: dimension,
              height: dimension,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: outerRingColor, width: 1.2),
              ),
            ),

            // Center targeting ring / dot
            Container(
              width: isDesktop ? 8.0 : 7.0,
              height: isDesktop ? 8.0 : 7.0,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.0),
              ),
            ),

            // Reticle Segments: Top, Bottom, Left, Right
            // Top segment
            Positioned(
              top: (dimension / 2) - gapFromCenter - lineLength,
              child: _buildReticleSegment(
                width: lineThickness,
                height: lineLength,
                color: accentColor,
              ),
            ),
            // Bottom segment
            Positioned(
              bottom: (dimension / 2) - gapFromCenter - lineLength,
              child: _buildReticleSegment(
                width: lineThickness,
                height: lineLength,
                color: accentColor,
              ),
            ),
            // Left segment
            Positioned(
              left: (dimension / 2) - gapFromCenter - lineLength,
              child: _buildReticleSegment(
                width: lineLength,
                height: lineThickness,
                color: accentColor,
              ),
            ),
            // Right segment
            Positioned(
              right: (dimension / 2) - gapFromCenter - lineLength,
              child: _buildReticleSegment(
                width: lineLength,
                height: lineThickness,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReticleSegment({
    required double width,
    required double height,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 2),
        ],
      ),
    );
  }
}
