import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';

final riderRequestsProvider =
    FutureProvider.autoDispose<List<BookingBase>>((ref) async {
  final repo = ref.watch(riderRepositoryProvider);
  final profile = ref.watch(authNotifierProvider).profile;
  if (profile == null) return [];
  return repo.fetchOpenRequests(profile.floatAmount);
});

final riderActiveBookingsProvider =
    FutureProvider.autoDispose<List<BookingBase>>((ref) async {
  final repo = ref.watch(riderRepositoryProvider);
  final profile = ref.watch(authNotifierProvider).profile;
  if (profile == null) return [];
  return repo.fetchAcceptedBookings(profile.id);
});

class RiderRequestsTab extends ConsumerWidget {
  const RiderRequestsTab({super.key});

  IconData _icon(BookingKind kind) {
    switch (kind) {
      case BookingKind.transport:
        return Icons.directions_car_rounded;
      case BookingKind.food:
        return Icons.restaurant_rounded;
      case BookingKind.parcel:
        return Icons.inventory_2_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(riderRequestsProvider);
    final application = ref.watch(authNotifierProvider).riderApplication;
    final approved = application?.status == ApplicationStatus.approved;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(riderRequestsProvider),
      child: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load requests.\n$e',
                  textAlign: TextAlign.center, style: AppTypography.body),
            ),
          ],
        ),
        data: (requests) {
          if (requests.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mark_email_read_outlined,
                          size: 56, color: AppColors.neutral300),
                      const SizedBox(height: 12),
                      Text('No booking requests right now.',
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
            itemCount: requests.length,
            itemBuilder: (_, i) {
              final b = requests[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_icon(b.kind), color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${b.kind.label} • ${Formatters.dateOnly(b.createdAt)}',
                                style: AppTypography.captionDark,
                                overflow: TextOverflow.ellipsis),
                          ),
                          StatusBadge(status: b.status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(b.routeLine,
                          style: AppTypography.bodyMedium.copyWith(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (b.expiresAt != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.hourglass_top_rounded,
                                size: 12, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text(
                              'Expires ${Formatters.timeOnly(b.expiresAt)}',
                              style: AppTypography.caption.copyWith(
                                  color: AppColors.warning, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(b.displayFare,
                              style: AppTypography.bodyBold.copyWith(color: AppColors.primary)),
                          const Spacer(),
                          Tooltip(
                            message: approved
                                ? 'Accept this booking'
                                : 'Wait for admin approval',
                            child: AppButton(
                              text: 'Accept',
                              width: 110,
                              height: 40,
                              icon: Icons.check_circle_outline_rounded,
                              onPressed: approved ? () => _accept(ref, context, b) : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _accept(WidgetRef ref, BuildContext context, BookingBase b) async {
    final profile = ref.read(authNotifierProvider).profile!;
    final repo = ref.read(riderRepositoryProvider);

    // Block double-accepts while a trip is in progress.
    final hasActive = await repo.hasActiveBooking(profile.id);
    if (!context.mounted) return;
    if (hasActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish your current booking before accepting another.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      await repo.acceptBooking(b, profile.id);
      ref.invalidate(riderRequestsProvider);
      ref.invalidate(riderActiveBookingsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${b.kind.label} booking accepted!'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}
