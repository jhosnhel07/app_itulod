import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/screens/booking_details_sheet.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import '../screens/book_food_screen.dart';
import '../screens/book_parcel_screen.dart';
import '../screens/book_ride_screen.dart';
import 'customer_bookings_tab.dart' show authProfileIdProvider;
import 'cancellation_dialog.dart';
import 'gcash_pay_action.dart';
import 'support_request_dialog.dart';
import '../../../chat/presentation/screens/chat_screen.dart' as import_chat;

/// Lifetime stats + the booking currently in flight. Refreshed by realtime.
final customerHomeSummaryProvider =
    FutureProvider.autoDispose<CustomerHomeSummary>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final userId = ref.watch(authProfileIdProvider);
  return repo.fetchHomeSummary(userId);
});

class CustomerHomeTab extends ConsumerWidget {
  const CustomerHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authNotifierProvider).profile;
    final firstName = profile?.fullName.split(' ').first ?? 'friend';
    final summaryAsync = ref.watch(customerHomeSummaryProvider);
    final summary = summaryAsync.value;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(customerHomeSummaryProvider);
        await ref.read(customerHomeSummaryProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
          const SizedBox(height: 16),

          // ── Active booking tracker ──────────────────────────────
          if (summary?.activeBooking != null) ...[
            _ActiveBookingCard(summary: summary!),
            const SizedBox(height: 16),
          ],

          // ── Lifetime stats ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Trips',
                  value: '${summary?.completedTrips ?? 0}',
                  icon: Icons.check_circle_rounded,
                  tint: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'Total spent',
                  value: Formatters.currency(summary?.totalSpent ?? 0),
                  icon: Icons.account_balance_wallet_rounded,
                  tint: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'This month',
                  value: '${summary?.tripsThisMonth ?? 0}',
                  icon: Icons.calendar_month_rounded,
                  tint: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Services ────────────────────────────────────────────
          Row(
            children: [
              Text('Our Services', style: AppTypography.h3),
              const Spacer(),
              Text('Choose one to start', style: AppTypography.caption),
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

class _ActiveBookingCard extends ConsumerWidget {
  final CustomerHomeSummary summary;

  const _ActiveBookingCard({required this.summary});

  String get _stage {
    switch (summary.activeBooking!.status) {
      case 'accepted':
        return 'Your rider is on the way to the pickup point.';
      case 'ongoing':
        return 'Trip in progress — enjoy the ride.';
      default:
        return 'Finding you a rider…';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = summary.activeBooking!;

    return Container(
      decoration: AppDecorations.softCard(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
            child: Row(
              children: [
                const Icon(Icons.electric_bolt_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Active ${b.kind.label.toLowerCase()} booking',
                    style: AppTypography.bodyBold
                        .copyWith(color: Colors.white, fontSize: 13.5)),
                const Spacer(),
                StatusBadge(status: b.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.routeLine,
                    style: AppTypography.bodyMedium.copyWith(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(_stage, style: AppTypography.caption),
                if (b.expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          size: 12, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        b.status == 'pending'
                            ? 'Expires ${Formatters.timeOnly(b.expiresAt)} if not accepted'
                            : 'Expires ${Formatters.timeOnly(b.expiresAt)} if not completed',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.warning, fontSize: 11),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      summary.activeRiderName != null
                          ? Icons.two_wheeler_rounded
                          : Icons.person_search_rounded,
                      size: 16,
                      color: AppColors.neutral500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.activeRiderName == null
                            ? 'No rider assigned yet'
                            : '${summary.activeRiderName}'
                                '${summary.activeRiderPhone != null && summary.activeRiderPhone!.isNotEmpty ? ' · ${summary.activeRiderPhone}' : ''}',
                        style: AppTypography.captionDark,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(b.displayFare,
                        style: AppTypography.bodyBold
                            .copyWith(color: AppColors.primaryDark)),
                  ],
                ),
                if (b.awaitingFinalFare) ...[
                  const SizedBox(height: 8),
                  Text(
                    "We'll ask you to pay once the rider confirms the fare at pickup.",
                    style: AppTypography.caption.copyWith(fontSize: 11.5),
                  ),
                ],
                if (b.needsPayment) ...[
                  const SizedBox(height: 12),
                  AppButton(
                    text: 'Pay ${Formatters.currency(b.payableAmount)}',
                    icon: Icons.account_balance_wallet_rounded,
                    onPressed: () => payBookingOnline(context, ref, b),
                  ),
                ],
                if (b.canSendChat) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          text: 'Track rider',
                          icon: Icons.map_outlined,
                          type: AppButtonType.outline,
                          onPressed: () => _openDetails(context, ref, b),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          text: 'Chat',
                          icon: Icons.chat_bubble_outline_rounded,
                          onPressed: () => Navigator.push(context, import_chat.ChatScreen.route(b)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openDetails(context, ref, b),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View details'),
                      ),
                    ),
                    if (b.canCancel) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cancel(context, ref, b),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetails(
      BuildContext context, WidgetRef ref, BookingBase booking) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BookingDetailsSheet(
        booking: booking,
        actions: [
          if (booking.needsPayment) ...[
            AppButton(
              text: 'Pay ${Formatters.currency(booking.payableAmount)}',
              icon: Icons.account_balance_wallet_rounded,
              onPressed: () {
                Navigator.pop(sheetContext);
                payBookingOnline(context, ref, booking);
              },
            ),
            const SizedBox(height: 8),
          ],
          AppButton(
            text: 'Report an issue with this booking',
            icon: Icons.report_problem_outlined,
            type: AppButtonType.secondary,
            onPressed: () {
              Navigator.pop(sheetContext);
              showSupportRequestDialog(context, ref, booking: booking);
            },
          ),
        ],
      ),
    );
    ref.invalidate(customerHomeSummaryProvider);
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, BookingBase booking) async {
    await showCancellationDialog(context, ref, booking);
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: AppDecorations.softCard(borderRadius: AppDecorations.radiusSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: AppTypography.h3.copyWith(fontSize: 16)),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption, maxLines: 1),
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
