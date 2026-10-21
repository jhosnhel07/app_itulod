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
/// **Dark mode.** Colours that must change in dark mode (surfaces, text greys,
/// soft tints, borders) are getters that read [dark]; brand blue, the status
/// colours and the gradients are the same in both themes and stay `const`.
/// [dark] is set by the theme controller (core/theme/theme_controller.dart),
/// which then rebuilds every widget so the new values are picked up.
class AppColors {
  AppColors._();

  /// True while the dark palette is active.
  static bool dark = false;

  static Color _pick(int light, int darkValue) => Color(dark ? darkValue : light);

  /// A light/dark pair for one-off colours that have no named token here.
  static Color pick(int light, int darkValue) => _pick(light, darkValue);

  // ── Primary brand palette — iTULOD Blue ────────────────────────────────
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryLight = Color(0xFF64B5F6); // derived 300
  /// Deep navy — text/icons on light; a light blue in dark mode so it stays
  /// readable on dark surfaces.
  static Color get primaryDark => _pick(0xFF0D47A1, 0xFF90CAF9);
  static const Color primaryDeep = Color(0xFF08326E); // derived, gradient tail
  static Color get primary50 => _pick(0xFFE3F2FD, 0xFF102540);
  static Color get primary100 => _pick(0xFF90CAF9, 0xFF2B5C92);
  static const Color primary200 = Color(0xFF64B5F6); // derived

  // ── Secondary / accent palette — Warm Blush ────────────────────────────
  static const Color secondary = Color(0xFFC97F8E); // derived 600 for icons/text
  static const Color secondaryLight = Color(0xFFE2B4BD); // supplied
  static Color get secondaryDark => _pick(0xFFA65A6B, 0xFFE2A3B1); // derived 700
  static Color get secondary50 => _pick(0xFFFFF5F5, 0xFF221820); // supplied
  static Color get secondary100 => _pick(0xFFF7D6D0, 0xFF3A2630); // supplied

  /// Semantic aliases for the blush family, for readable call sites.
  static Color get blush => _pick(0xFFFFF5F5, 0xFF221820);
  static Color get blushBorder => _pick(0xFFF7D6D0, 0xFF3A2630);
  static const Color blushAccent = Color(0xFFE2B4BD);
  static Color get warmInk => _pick(0xFF4A4A4A, 0xFFC3CDD9);

  // ── Semantic feedback ─────────────────────────────────────────────────
  static const Color success = Color(0xFF12B76A);
  static const Color successLight = Color(0xFF32D583);
  static Color get success50 => _pick(0xFFE7F8F0, 0xFF0F2A1F);

  static const Color danger = Color(0xFFF04438);
  static const Color dangerLight = Color(0xFFF97066);
  static Color get danger50 => _pick(0xFFFDECEA, 0xFF2F151B);

  static const Color warning = Color(0xFFF79009);
  static const Color warningLight = Color(0xFFFDB022);
  static Color get warning50 => _pick(0xFFFFF4E5, 0xFF2B2210);

  static const Color info = Color(0xFF2196F3);
  static Color get info50 => _pick(0xFFE3F2FD, 0xFF102540);

  // ── Neutrals — cool grey ramp (inverted in dark mode) ──────────────────
  static Color get neutral900 => _pick(0xFF131B2B, 0xFFE8EEF6);
  static Color get neutral800 => _pick(0xFF1F2A3C, 0xFFD5DDE8);
  static Color get neutral700 => _pick(0xFF374151, 0xFFC3CDD9);
  static Color get neutral600 => _pick(0xFF4B5563, 0xFFA9B5C4);
  static Color get neutral500 => _pick(0xFF6B7280, 0xFF8D9AAB);
  static Color get neutral400 => _pick(0xFF98A2B3, 0xFF6C7A8D);
  static Color get neutral300 => _pick(0xFFD0D7E2, 0xFF46566C);
  static Color get neutral200 => _pick(0xFFE5EAF2, 0xFF2A384C);
  static Color get neutral100 => _pick(0xFFF1F4F9, 0xFF1C2839);
  static Color get neutral50 => _pick(0xFFF8FAFD, 0xFF162030);

  // ── Background & surface ──────────────────────────────────────────────
  static Color get surface => _pick(0xFFFFFFFF, 0xFF131C29);
  static Color get surfaceAlt => _pick(0xFFF4F8FE, 0xFF172131); // faint blue tint
  static Color get background => _pick(0xFFF3F6FC, 0xFF0B121C);
  static Color get cardBorder => _pick(0xFFE7ECF4, 0xFF243246);
  static Color get divider => _pick(0xFFEDF1F7, 0xFF1F2B3D);

  // ── Auth / legacy brand aliases (kept so existing screens compile) ─────
  static const Color brandBlue = Color(0xFF2196F3);
  static Color get brandBlueDark => _pick(0xFF0D47A1, 0xFF90CAF9);

  /// Historically an orange accent for the rider flow; now the warm blush
  /// rose, so the customer/rider split reads as blue vs. rose.
  static const Color brandOrange = Color(0xFFC97F8E);
  static Color get brandOrangeDark => _pick(0xFFA65A6B, 0xFFE2A3B1);

  static Color get ink => _pick(0xFF131B2B, 0xFFE8EEF6);
  static Color get slate => _pick(0xFF5B6472, 0xFFA9B5C4);
  static Color get inputFill => _pick(0xFFF3F6FC, 0xFF172131);
  static Color get placeholder => _pick(0xFFAEB7C4, 0xFF6C7A8D);
  static Color get iconMuted => _pick(0xFF8A94A6, 0xFF8D9AAB);

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

  static LinearGradient get blushGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF3A2630), Color(0xFF5A3542)]
            : const [Color(0xFFF7D6D0), Color(0xFFE2B4BD)],
      );

  // ── Shadows ───────────────────────────────────────────────────────────
  /// Soft, close ambient shadow for cards and tiles.
  static List<BoxShadow> get cardShadow => dark
      ? const [
          BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
        ]
      : const [
          BoxShadow(color: Color(0x0D18294D), blurRadius: 14, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x0818294D), blurRadius: 3, offset: Offset(0, 1)),
        ];

  /// Lifted shadow for hero panels and floating actions.
  static List<BoxShadow> get elevatedShadow => dark
      ? const [
          BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 14)),
          BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
        ]
      : const [
          BoxShadow(color: Color(0x1F1565C0), blurRadius: 28, offset: Offset(0, 14)),
          BoxShadow(color: Color(0x0F18294D), blurRadius: 6, offset: Offset(0, 2)),
        ];

  /// Coloured glow under primary buttons.
  static const List<BoxShadow> primaryGlow = [
    BoxShadow(color: Color(0x452196F3), blurRadius: 18, offset: Offset(0, 8)),
  ];
}
