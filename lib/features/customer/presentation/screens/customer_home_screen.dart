import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authNotifierProvider).profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('iTULOD Customer Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      AvatarWidget(
                        name: profile?.fullName ?? 'Customer',
                        url: profile?.avatarUrl,
                        radius: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile?.fullName ?? 'Welcome!', style: AppTypography.h3),
                            const SizedBox(height: 4),
                            Text(
                              profile?.email ?? '',
                              style: AppTypography.captionDark,
                            ),
                            const SizedBox(height: 6),
                            const StatusBadge(status: 'Customer'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Our Services', style: AppTypography.h3),
              const SizedBox(height: 12),
              _buildServiceCard(
                context,
                title: 'Book a Ride',
                subtitle: 'Reliable point-to-point transportation across Ilocos',
                icon: Icons.directions_car_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              _buildServiceCard(
                context,
                title: 'Food Delivery',
                subtitle: 'Order delicious food from your favorite local restaurants',
                icon: Icons.restaurant_rounded,
                color: AppColors.secondary,
              ),
              const SizedBox(height: 12),
              _buildServiceCard(
                context,
                title: 'Send Parcel',
                subtitle: 'Fast, secure on-demand door-to-door parcel delivery',
                icon: Icons.local_shipping_rounded,
                color: AppColors.success,
              ),
              const SizedBox(height: 32),
              AppButton(
                text: 'Sign Out',
                type: AppButtonType.outline,
                onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyBold.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.captionDark),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.neutral400),
          ],
        ),
      ),
    );
  }
}
