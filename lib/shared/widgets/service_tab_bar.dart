import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Rides · Food · Parcels · Hauling switcher for the booking lists. The
/// selected service is a solid blue rounded rectangle with white text, so it
/// reads at a glance (web twin: .segmented / .seg-btn in dashboard.css).
class ServiceTabBar extends StatelessWidget {
  final TabController controller;
  const ServiceTabBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: TabBar(
          controller: controller,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          splashBorderRadius: BorderRadius.circular(9),
          indicator: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.neutral600,
          labelStyle: AppTypography.bodyBold.copyWith(fontSize: 14),
          unselectedLabelStyle: AppTypography.bodyMedium.copyWith(fontSize: 14),
          labelPadding: EdgeInsets.zero,
          tabs: const [
            Tab(text: 'Rides', height: 40),
            Tab(text: 'Food', height: 40),
            Tab(text: 'Parcels', height: 40),
            Tab(text: 'Hauling', height: 40),
          ],
        ),
      ),
    );
  }
}
