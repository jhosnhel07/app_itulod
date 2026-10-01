import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/models/rider_application_model.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';
import 'rider_earnings_tab.dart' show riderEarningsProvider;
import 'rider_requests_tab.dart'
    show riderActiveBookingsProvider, riderRequestsProvider;

/// "Your day at a glance" — the rider's landing tab, mirroring the web
/// dashboard's rider home view.
final riderHomeSnapshotProvider =
    FutureProvider.autoDispose<RiderHomeSnapshot>((ref) async {
  final repo = ref.watch(riderRepositoryProvider);
  final profile = ref.watch(authNotifierProvider).profile;
  if (profile == null) return const RiderHomeSnapshot();
  return repo.fetchHomeSnapshot(profile.id, profile.floatAmount);
});

class RiderHomeTab extends ConsumerWidget {
  final void Function(int tabIndex) onGoToTab;

  /// Nav indices on the rider dashboard, so the CTAs land on the right tab.
  final int requestsTabIndex;
  final int tripTabIndex;

  const RiderHomeTab({
    super.key,
    required this.onGoToTab,
    required this.requestsTabIndex,
    required this.tripTabIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(riderHomeSnapshotProvider);
    final application = ref.watch(authNotifierProvider).riderApplication;
    final approved = application?.status == ApplicationStatus.approved;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(riderHomeSnapshotProvider);
        await ref.read(riderHomeSnapshotProvider.future);
      },
      child: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load your day.\n$e',
                  textAlign: TextAlign.center, style: AppTypography.body),
            ),
          ],
        ),
        data: (s) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _FloatCard(),
            const SizedBox(height: 18),
            // ── Snapshot stats ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: "Today's earnings",
                    value: Formatters.currency(s.earningsToday),
                    icon: Icons.payments_rounded,
                    tint: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: 'Trips today',
                    value: '${s.tripsToday}',
                    icon: Icons.route_rounded,
                    tint: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Rating',
                    value: s.averageRating > 0
                        ? s.averageRating.toStringAsFixed(1)
                        : '—',
                    icon: Icons.star_rounded,
                    tint: const Color(0xFFF6B73C),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: 'Open requests',
                    value: '${s.openRequests}',
                    icon: Icons.inbox_rounded,
                    tint: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Active booking / hero CTA ───────────────────────
            Builder(
              builder: (context) {
                final active = s.primaryActive;
                if (active != null) {
                  return _ActiveJobCard(
                    booking: active,
                    approved: approved,
                    onOpenTrip: () => onGoToTab(tripTabIndex),
                  );
                }
                return _HeroCta(
                  openRequests: s.openRequests,
                  onViewRequests: () => onGoToTab(requestsTabIndex),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCta extends StatelessWidget {
  final int openRequests;
  final VoidCallback onViewRequests;

  const _HeroCta({required this.openRequests, required this.onViewRequests});

  @override
  Widget build(BuildContext context) {
    final waiting = openRequests > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: AppDecorations.hero(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            waiting
                ? '$openRequests request${openRequests > 1 ? 's' : ''} waiting'
                : 'No active booking',
            style: AppTypography.h3.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            waiting
                ? 'Grab one before another rider does.'
                : 'New requests appear here the moment a customer books.',
            style: AppTypography.body
                .copyWith(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onViewRequests,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size(0, 46),
            ),
            icon: const Icon(Icons.inbox_rounded, size: 18),
            label: const Text('View requests'),
          ),
        ],
      ),
    );
  }
}

class _ActiveJobCard extends ConsumerWidget {
  final BookingBase booking;
  final bool approved;
  final VoidCallback onOpenTrip;

  const _ActiveJobCard({
    required this.booking,
    required this.approved,
    required this.onOpenTrip,
  });

  bool get _paymentBlocked =>
      booking.kind == BookingKind.transport &&
      booking.paymentMethod != null &&
      booking.paymentMethod != 'cash' &&
      booking.paymentStatus != 'paid';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOngoing = booking.status == 'ongoing';

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
                Icon(
                  isOngoing
                      ? Icons.directions_rounded
                      : Icons.flag_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isOngoing ? 'Trip in progress' : 'Navigate to pickup',
                  style: AppTypography.bodyBold
                      .copyWith(color: Colors.white, fontSize: 13.5),
                ),
                const Spacer(),
                StatusBadge(status: booking.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.routeLine,
                    style: AppTypography.bodyMedium.copyWith(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(
                  'Fare: ${Formatters.currency(booking.finalFare ?? booking.estimatedFare)}',
                  style: AppTypography.captionDark,
                ),
                if (booking.expiresAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          size: 12, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        'Start before ${Formatters.timeOnly(booking.expiresAt)} (15-min grace period)',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.warning, fontSize: 11),
                      ),
                    ],
                  ),
                ],
                if (_paymentBlocked) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: AppColors.warning, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Waiting for the online payment to clear before the trip can start.',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.warmInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOpenTrip,
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text('Open trip'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (!approved || _paymentBlocked)
                            ? null
                            : () => _advance(context, ref, isOngoing),
                        icon: Icon(
                          isOngoing
                              ? Icons.task_alt_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(isOngoing ? 'Complete' : 'Start'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _advance(
      BuildContext context, WidgetRef ref, bool isOngoing) async {
    final profile = ref.read(authNotifierProvider).profile;
    if (profile == null) return;
    
    final repo = ref.read(riderRepositoryProvider);
    try {
      await repo.updateStatus(
        booking,
        isOngoing ? 'completed' : 'ongoing',
        riderId: profile.id,
      );
      ref.invalidate(riderHomeSnapshotProvider);
      ref.invalidate(riderActiveBookingsProvider);
      ref.invalidate(riderRequestsProvider);
      ref.invalidate(riderEarningsProvider);
      if (context.mounted && isOngoing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip completed! Earnings updated.'),
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
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.softCard(borderRadius: AppDecorations.radiusSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppTypography.h2.copyWith(fontSize: 20)),
          ),
        ],
      ),
    );
  }
}

class _FloatCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FloatCard> createState() => _FloatCardState();
}

class _FloatCardState extends ConsumerState<_FloatCard> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authNotifierProvider).profile;
    if (profile == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.softCard(borderRadius: AppDecorations.radiusLg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cash on Hand (Float)', style: AppTypography.captionDark),
                const SizedBox(height: 4),
                Text(
                  Formatters.currency(profile.floatAmount),
                  style: AppTypography.h2.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _isLoading ? null : () => _updateFloat(context, profile.floatAmount),
            child: _isLoading 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateFloat(BuildContext context, double currentFloat) async {
    final controller = TextEditingController(text: currentFloat > 0 ? currentFloat.toStringAsFixed(0) : '');
    
    final newAmount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Cash on Hand'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How much cash do you currently have to buy food and parcels for customers?',
              style: AppTypography.body,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '₱ ',
                hintText: 'e.g., 1500',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newAmount != null && mounted) {
      setState(() => _isLoading = true);
      try {
        final profile = ref.read(authNotifierProvider).profile;
        if (profile == null) return;
        await ref.read(riderRepositoryProvider).updateFloatAmount(profile.id, newAmount);
        await ref.read(authNotifierProvider.notifier).refreshProfile();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppColors.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }
}

