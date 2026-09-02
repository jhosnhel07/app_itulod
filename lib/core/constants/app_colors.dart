import 'package:flutter/material.dart';

/// Centralised colour system for the iTULOD mobile app.
///
/// Two families drive the whole UI:
///  * **iTULOD Blue** (primary) — Material Blue: `#E3F2FD #90CAF9 #2196F3 #0D47A1`.
///    Used for primary actions, links, active states, headers and focus rings.
///  * **Warm Blush** (accent) — `#FFF5F5 #F7D6D0 #E2B4BD #4A4A4A`.
///    Used for soft secondary surfaces, highlights, the food service and warm
///    empty-state panels.
///
/// A handful of `600`/`700` steps are derived from the supplied swatches so the
/// families carry enough contrast for text and icons on light surfaces.
class AppColors {
  AppColors._();

  // ── Primary brand palette — iTULOD Blue ────────────────────────────────
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryLight = Color(0xFF64B5F6); // derived 300
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryDeep = Color(0xFF08326E); // derived, gradient tail
  static const Color primary50 = Color(0xFFE3F2FD);
  static const Color primary100 = Color(0xFF90CAF9);
  static const Color primary200 = Color(0xFF64B5F6); // derived

  // ── Secondary / accent palette — Warm Blush ────────────────────────────
  static const Color secondary = Color(0xFFC97F8E); // derived 600 for icons/text
  static const Color secondaryLight = Color(0xFFE2B4BD); // supplied
  static const Color secondaryDark = Color(0xFFA65A6B); // derived 700
  static const Color secondary50 = Color(0xFFFFF5F5); // supplied
  static const Color secondary100 = Color(0xFFF7D6D0); // supplied

  /// Semantic aliases for the blush family, for readable call sites.
  static const Color blush = Color(0xFFFFF5F5);
  static const Color blushBorder = Color(0xFFF7D6D0);
  static const Color blushAccent = Color(0xFFE2B4BD);
  static const Color warmInk = Color(0xFF4A4A4A);

  // ── Semantic feedback ─────────────────────────────────────────────────
  static const Color success = Color(0xFF12B76A);
  static const Color successLight = Color(0xFF32D583);
  static const Color success50 = Color(0xFFE7F8F0);

  static const Color danger = Color(0xFFF04438);
  static const Color dangerLight = Color(0xFFF97066);
  static const Color danger50 = Color(0xFFFDECEA);

  static const Color warning = Color(0xFFF79009);
  static const Color warningLight = Color(0xFFFDB022);
  static const Color warning50 = Color(0xFFFFF4E5);

  static const Color info = Color(0xFF2196F3);
  static const Color info50 = Color(0xFFE3F2FD);

  // ── Neutrals — cool grey ramp that pairs with the blue primary ─────────
  static const Color neutral900 = Color(0xFF131B2B);
  static const Color neutral800 = Color(0xFF1F2A3C);
  static const Color neutral700 = Color(0xFF374151);
  static const Color neutral600 = Color(0xFF4B5563);
  static const Color neutral500 = Color(0xFF6B7280);
  static const Color neutral400 = Color(0xFF98A2B3);
  static const Color neutral300 = Color(0xFFD0D7E2);
  static const Color neutral200 = Color(0xFFE5EAF2);
  static const Color neutral100 = Color(0xFFF1F4F9);
  static const Color neutral50 = Color(0xFFF8FAFD);

  // ── Background & surface ──────────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF4F8FE); // faint blue tint
  static const Color background = Color(0xFFF3F6FC);
  static const Color cardBorder = Color(0xFFE7ECF4);
  static const Color divider = Color(0xFFEDF1F7);

  // ── Auth / legacy brand aliases (kept so existing screens compile) ─────
  static const Color brandBlue = Color(0xFF2196F3);
  static const Color brandBlueDark = Color(0xFF0D47A1);

  /// Historically an orange accent for the rider flow; now the warm blush
  /// rose, so the customer/rider split reads as blue vs. rose.
  static const Color brandOrange = Color(0xFFC97F8E);
  static const Color brandOrangeDark = Color(0xFFA65A6B);

  static const Color ink = Color(0xFF131B2B);
  static const Color slate = Color(0xFF5B6472);
  static const Color inputFill = Color(0xFFF3F6FC);
  static const Color placeholder = Color(0xFFAEB7C4);
  static const Color iconMuted = Color(0xFF8A94A6);

  // ── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
  );

  static const LinearGradient skyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF42A5F5), Color(0xFF0D47A1)],
  );

  static const LinearGradient blushGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7D6D0), Color(0xFFE2B4BD)],
  );

  // ── Shadows ───────────────────────────────────────────────────────────
  /// Soft, close ambient shadow for cards and tiles.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0D18294D), blurRadius: 14, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0818294D), blurRadius: 3, offset: Offset(0, 1)),
  ];

  /// Lifted shadow for hero panels and floating actions.
  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(color: Color(0x1F1565C0), blurRadius: 28, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0F18294D), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Coloured glow under primary buttons.
  static const List<BoxShadow> primaryGlow = [
    BoxShadow(color: Color(0x452196F3), blurRadius: 18, offset: Offset(0, 8)),
  ];
}
