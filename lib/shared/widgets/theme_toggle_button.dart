import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_controller.dart';

/// Sun/moon button for the top-right of the dashboard headers: shows a moon
/// in light mode (tap → dark) and a sun in dark mode (tap → light).
class ThemeToggleButton extends ConsumerWidget {
  /// Icon colour — white on the blue gradient headers.
  final Color? color;
  const ThemeToggleButton({super.key, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeChoiceProvider);
    final dark = AppColors.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => ref.read(themeChoiceProvider.notifier).toggle(),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(dark),
          color: color,
        ),
      ),
    );
  }
}
