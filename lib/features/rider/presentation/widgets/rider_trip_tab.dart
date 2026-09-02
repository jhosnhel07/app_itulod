import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';
import 'rider_requests_tab.dart' show riderActiveBookingsProvider, riderRequestsProvider;

class RiderTripTab extends ConsumerWidget {
  const RiderTripTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(riderActiveBookingsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(riderActiveBookingsProvider),
      child: activeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load trips.\n$e',
                  textAlign: TextAlign.center, style: AppTypography.body),
            ),
          ],
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.two_wheeler_rounded,
                          size: 56, color: AppColors.neutral300),
                      const SizedBox(height: 12),
                      Text('No active trip. Accept a booking to get started.',
                          style: AppTypography.captionDark),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: bookings.length,
            itemBuilder: (_, i) => _ActiveBookingCard(booking: bookings[i]),
          );
        },
      ),
    );
  }
}

class _ActiveBookingCard extends ConsumerWidget {
  final BookingBase booking;

  const _ActiveBookingCard({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOngoing = booking.status == 'ongoing';
    final paymentBlocked = booking.kind == BookingKind.transport &&
        booking.paymentMethod != null &&
        booking.paymentMethod != 'cash' &&
        booking.paymentStatus != 'paid';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${booking.kind.label} booking', style: AppTypography.h3),
                const Spacer(),
                StatusBadge(status: booking.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(booking.routeLine,
                style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
            const SizedBox(height: 12),
            // Trip progress steps
            Row(
              children: [
                _stepIcon(true, Icons.flag_circle_outlined, 'Accepted'),
                _stepConnector(isOngoing || false),
                _stepIcon(isOngoing, Icons.directions_rounded, 'On trip'),
                _stepConnector(false),
                _stepIcon(false, Icons.emoji_events_outlined, 'Complete'),
              ],
            ),
            if (paymentBlocked) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiting for online payment confirmation before starting the trip.',
                        style: AppTypography.captionDark.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            AppButton(
              text: isOngoing ? 'Mark Complete' : 'Start Trip',
              icon: isOngoing ? Icons.task_alt_rounded : Icons.play_arrow_rounded,
              onPressed: paymentBlocked
                  ? null
                  : () async {
                      final profile = ref.read(authNotifierProvider).profile!;
                      final repo = ref.read(riderRepositoryProvider);
                      try {
                        await repo.updateStatus(
                          booking,
                          isOngoing ? 'completed' : 'ongoing',
                          riderId: profile.id,
                        );
                        ref.invalidate(riderActiveBookingsProvider);
                        ref.invalidate(riderRequestsProvider);
                        if (context.mounted && isOngoing) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Trip completed! Earnings updated.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Update failed: $e'),
                                backgroundColor: AppColors.danger),
                          );
                        }
                      }
                    },
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Fare: ${Formatters.currency(booking.finalFare ?? booking.estimatedFare)}',
                  style: AppTypography.captionDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepIcon(bool active, IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon,
              color: active ? AppColors.success : AppColors.neutral300, size: 26),
          const SizedBox(height: 4),
          Text(label,
              style: AppTypography.caption.copyWith(
                fontSize: 11,
                color: active ? AppColors.success : AppColors.neutral400,
              )),
        ],
      ),
    );
  }

  Widget _stepConnector(bool reached) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: reached ? AppColors.success : AppColors.neutral300,
    );
  }
}
