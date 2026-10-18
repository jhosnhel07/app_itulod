import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Keeps a screen's main action (Review Booking, Place Order…) pinned above
/// the bottom edge so it stays in reach while the form scrolls (web: the
/// sticky booking submit button).
class StickyActionBar extends StatelessWidget {
  final Widget child;
  const StickyActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: const [BoxShadow(color: Color(0x1418294D), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: child,
        ),
      ),
    );
  }
}
