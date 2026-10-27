import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Rides · Food · Parcels · Hauling switcher for the booking lists. The
/// selected service is a solid blue rounded rectangle with white text, so it
/// reads at a glance (web twin: .segmented / .seg-btn in dashboard.css).
class ServiceTabBar extends StatelessWidget {
  final TabController controller;

  /// A count on each service (Rides, Food, Parcels, Hauling), e.g. bookings
  /// that need the customer; 0 shows nothing.
  final List<int> counts;
  const ServiceTabBar({super.key, required this.controller, this.counts = const []});

  static const _labels = ['Rides', 'Food', 'Parcels', 'Hauling'];

  Widget _tab(int i) {
    final n = i < counts.length ? counts[i] : 0;
    if (n <= 0) return Tab(text: _labels[i], height: 40);
    return Tab(
      height: 40,
      child: Badge(
        key: Key('service-count-${_labels[i]}'),
        label: Text(n > 99 ? '99+' : '$n'),
        backgroundColor: AppColors.danger,
        offset: const Offset(12, -6),
        child: Text(_labels[i]),
      ),
    );
  }

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
          tabs: [for (var i = 0; i < _labels.length; i++) _tab(i)],
        ),
      ),
    );
  }
}
