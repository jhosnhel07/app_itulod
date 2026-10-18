import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// The user's light/dark choice. [system] means no choice saved yet, which
/// shows the light theme — same rule as the web dashboards' theme switch:
/// light by default, dark only after the user taps the switch.
enum AppThemeChoice { system, light, dark }

final themeChoiceProvider =
    StateNotifierProvider<ThemeController, AppThemeChoice>((ref) => ThemeController());

class ThemeController extends StateNotifier<AppThemeChoice> {
  ThemeController() : super(AppThemeChoice.system) {
    _load();
  }

  static const _key = 'itulod-theme';

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved == 'light') state = AppThemeChoice.light;
      if (saved == 'dark') state = AppThemeChoice.dark;
    } catch (_) {
      // Storage unavailable — keep following the device.
    }
  }

  /// Flip to the opposite of what's on screen now and remember it.
  Future<void> toggle() async {
    final next = AppColors.dark ? AppThemeChoice.light : AppThemeChoice.dark;
    state = next;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, next.name);
    } catch (_) {
      // Applies for this session only.
    }
  }
}

/// Dark only when the user chose it; light otherwise (the phone's own
/// light/dark setting doesn't change the app).
bool resolveDark(AppThemeChoice choice, Brightness platform) => choice == AppThemeChoice.dark;

/// Switch the static palette. Returns true when it actually changed, so the
/// caller can rebuild every widget (many read AppColors directly).
bool applyPalette(bool dark) {
  if (AppColors.dark == dark) return false;
  AppColors.dark = dark;
  AppTypography.resetCache();
  return true;
}

/// Mark every element dirty so widgets that read AppColors/AppTypography
/// directly (including const ones) rebuild with the new palette, while keeping
/// all state (navigation stack, form input, scroll position).
void rebuildAllElements(BuildContext context) {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
}
