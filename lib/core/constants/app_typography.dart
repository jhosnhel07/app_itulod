import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Type scale for the app.
///
/// Headings use **Plus Jakarta Sans** (geometric, confident) and body copy uses
/// **Inter** (highly legible at small sizes). Both are pulled through
/// `google_fonts`. Each style's colour follows the active light/dark palette,
/// so the styles are cached getters; [resetCache] is called by the theme
/// controller when the palette flips.
class AppTypography {
  AppTypography._();

  static final Map<String, TextStyle> _cache = {};

  /// Drop cached styles so the next read picks up the new palette colours.
  static void resetCache() => _cache.clear();

  static TextStyle _cached(String key, TextStyle Function() build) =>
      _cache.putIfAbsent(key, build);

  static TextStyle _display(
    double size,
    FontWeight weight, {
    double spacing = -0.5,
    double height = 1.15,
    Color? color,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
        color: color ?? AppColors.neutral900,
      );

  static TextStyle _body(
    double size,
    FontWeight weight, {
    double height = 1.5,
    Color? color,
    double spacing = 0,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? AppColors.neutral700,
      );

  // Display — for hero panels and big numbers.
  static TextStyle get display =>
      _cached('display', () => _display(32, FontWeight.w800, height: 1.1));

  // Heading 1 — screen titles.
  static TextStyle get h1 =>
      _cached('h1', () => _display(27, FontWeight.w800, height: 1.2));

  // Heading 2 — section titles / large stats.
  static TextStyle get h2 => _cached(
      'h2', () => _display(22, FontWeight.w700, spacing: -0.3, height: 1.3));

  // Heading 3 — card titles / app bar titles.
  static TextStyle get h3 => _cached(
      'h3', () => _display(18, FontWeight.w700, spacing: -0.2, height: 1.35));

  // Body — default paragraph text.
  static TextStyle get body => _cached('body', () => _body(15, FontWeight.w400));

  static TextStyle get bodyMedium => _cached('bodyMedium',
      () => _body(15, FontWeight.w500, height: 1.4, color: AppColors.neutral900));

  static TextStyle get bodyBold => _cached('bodyBold',
      () => _body(15, FontWeight.w700, height: 1.4, color: AppColors.neutral900));

  // Caption — metadata, timestamps.
  static TextStyle get caption => _cached('caption',
      // neutral500 (not 400): small text needs ≥ 4.5:1 contrast to read outdoors.
      () => _body(12, FontWeight.w500, height: 1.3, color: AppColors.neutral500));

  static TextStyle get captionDark => _cached('captionDark',
      () => _body(12.5, FontWeight.w500, height: 1.35, color: AppColors.neutral600));

  // Overline — small all-caps labels above values.
  static TextStyle get overline => _cached(
        'overline',
        () => _body(
          11,
          FontWeight.w700,
          height: 1.2,
          color: AppColors.neutral500,
          spacing: 0.8,
        ),
      );

  // Button label.
  static TextStyle get button => _cached(
        'button',
        () => GoogleFonts.plusJakartaSans(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
      );
}
