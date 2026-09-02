import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../screens/book_food_screen.dart';
import '../screens/book_parcel_screen.dart';
import '../screens/book_ride_screen.dart';

class CustomerHomeTab extends ConsumerWidget {
  const CustomerHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authNotifierProvider).profile;
    final firstName = profile?.fullName.split(' ').first ?? 'friend';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(22),
            decoration: AppDecorations.hero(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where to today,\n$firstName?',
                  style: AppTypography.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'Book a ride, order food, or send a parcel — all in one app.',
                  style: AppTypography.body
                      .copyWith(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BookRideScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              color: AppColors.iconMuted, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Set your destination',
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.neutral500),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // ── Services ────────────────────────────────────────────
          Row(
            children: [
              Text('Our Services', style: AppTypography.h3),
              const Spacer(),
              Text('Choose one to start',
                  style: AppTypography.caption),
            ],
          ),
          const SizedBox(height: 12),
          _ServiceCard(
            title: 'Book a Ride',
            subtitle: 'Reliable point-to-point transportation',
            icon: Icons.directions_car_rounded,
            color: AppColors.primary,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BookRideScreen())),
          ),
          _ServiceCard(
            title: 'Food Delivery',
            subtitle: 'Order from your favourite local restaurants',
            icon: Icons.restaurant_rounded,
            color: AppColors.secondary,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BookFoodScreen())),
          ),
          _ServiceCard(
            title: 'Send Parcel',
            subtitle: 'Fast, secure door-to-door parcel delivery',
            icon: Icons.inventory_2_rounded,
            color: AppColors.success,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BookParcelScreen())),
          ),
          const SizedBox(height: 18),

          // ── Warm blush info panel ───────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppDecorations.blushPanel(),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.blushBorder),
                  ),
                  child: const Icon(Icons.verified_user_rounded,
                      color: AppColors.secondaryDark, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verified iTULOD partners',
                          style: AppTypography.bodyBold.copyWith(
                              fontSize: 14, color: AppColors.warmInk)),
                      const SizedBox(height: 2),
                      Text(
                        'Every rider is ID-checked and rated by the community.',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.warmInk),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecorations.softCard(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: AppDecorations.iconTile(color),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTypography.bodyBold.copyWith(fontSize: 15.5)),
                      const SizedBox(height: 3),
                      Text(subtitle, style: AppTypography.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.neutral100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.neutral500, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
