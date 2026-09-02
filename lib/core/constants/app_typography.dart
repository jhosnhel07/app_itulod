import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Type scale for the app.
///
/// Headings use **Plus Jakarta Sans** (geometric, confident) and body copy uses
/// **Inter** (highly legible at small sizes). Both are pulled through
/// `google_fonts`, so these are `static final` rather than `const`.
class AppTypography {
  AppTypography._();

  static TextStyle _display(
    double size,
    FontWeight weight, {
    double spacing = -0.5,
    double height = 1.15,
    Color color = AppColors.neutral900,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
        color: color,
      );

  static TextStyle _body(
    double size,
    FontWeight weight, {
    double height = 1.5,
    Color color = AppColors.neutral700,
    double spacing = 0,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color,
      );

  // Display — for hero panels and big numbers.
  static final TextStyle display = _display(32, FontWeight.w800, height: 1.1);

  // Heading 1 — screen titles.
  static final TextStyle h1 = _display(27, FontWeight.w800, height: 1.2);

  // Heading 2 — section titles / large stats.
  static final TextStyle h2 =
      _display(22, FontWeight.w700, spacing: -0.3, height: 1.3);

  // Heading 3 — card titles / app bar titles.
  static final TextStyle h3 =
      _display(18, FontWeight.w700, spacing: -0.2, height: 1.35);

  // Body — default paragraph text.
  static final TextStyle body = _body(15, FontWeight.w400);

  static final TextStyle bodyMedium =
      _body(15, FontWeight.w500, height: 1.4, color: AppColors.neutral900);

  static final TextStyle bodyBold =
      _body(15, FontWeight.w700, height: 1.4, color: AppColors.neutral900);

  // Caption — metadata, timestamps.
  static final TextStyle caption =
      _body(12, FontWeight.w500, height: 1.3, color: AppColors.neutral400);

  static final TextStyle captionDark =
      _body(12.5, FontWeight.w500, height: 1.35, color: AppColors.neutral600);

  // Overline — small all-caps labels above values.
  static final TextStyle overline = _body(
    11,
    FontWeight.w700,
    height: 1.2,
    color: AppColors.neutral500,
    spacing: 0.8,
  );

  // Button label.
  static final TextStyle button = GoogleFonts.plusJakartaSans(
    fontSize: 15.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: Colors.white,
  );
}
