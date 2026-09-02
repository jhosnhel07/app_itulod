import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Reusable container decorations so panels look identical everywhere.
class AppDecorations {
  AppDecorations._();

  static const BorderRadius radius = BorderRadius.all(Radius.circular(16));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(12));

  /// White card with a hairline border and a soft ambient shadow.
  static BoxDecoration softCard({BorderRadius? borderRadius}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius ?? radius,
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.cardShadow,
      );

  /// Flat white card with just a border — for dense lists.
  static BoxDecoration flatCard({BorderRadius? borderRadius}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius ?? radius,
        border: Border.all(color: AppColors.cardBorder),
      );

  /// The iTULOD Blue hero panel used on dashboards.
  static BoxDecoration hero({BorderRadius? borderRadius}) => BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: borderRadius ?? radiusLg,
        boxShadow: AppColors.elevatedShadow,
      );

  /// Warm blush panel for secondary / informational sections.
  static BoxDecoration blushPanel({BorderRadius? borderRadius}) => BoxDecoration(
        color: AppColors.blush,
        borderRadius: borderRadius ?? radius,
        border: Border.all(color: AppColors.blushBorder),
      );

  /// Tinted pill / chip background for a given accent colour.
  static BoxDecoration tintPill(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      );

  /// Rounded icon badge in a tinted square.
  static BoxDecoration iconTile(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: radiusSm,
      );
}
