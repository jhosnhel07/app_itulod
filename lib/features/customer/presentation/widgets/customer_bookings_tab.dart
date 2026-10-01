import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/screens/booking_details_sheet.dart';
import '../../../../shared/widgets/booking_card.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import 'cancellation_dialog.dart';
import 'gcash_pay_action.dart';

final customerHistoryProvider = FutureProvider.autoDispose
    .family<List<BookingBase>, BookingKind>((ref, kind) async {
  final repo = ref.watch(customerRepositoryProvider);
  final profile = ref.watch(authProfileIdProvider);
  return repo.fetchHistory(kind, profile);
});

/// Lightweight provider exposing the signed-in user's id.
final authProfileIdProvider = Provider<String>((ref) {
  final profile = ref.watch(authNotifierProvider).profile;
  return profile?.id ?? '';
});

class CustomerBookingsTab extends ConsumerStatefulWidget {
  const CustomerBookingsTab({super.key});

  @override
  ConsumerState<CustomerBookingsTab> createState() => _CustomerBookingsTabState();
}

class _CustomerBookingsTabState extends ConsumerState<CustomerBookingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openDetails(BookingBase booking) async {
    final repo = ref.read(customerRepositoryProvider);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Widget? cancelAction;
        if (booking.canCancel) {
          cancelAction = AppButton(
            text: 'Cancel booking',
            type: AppButtonType.danger,
            onPressed: () async {
              Navigator.pop(sheetContext);
              await showCancellationDialog(context, ref, booking);
            },
          );
        }
        Widget? rateAction;
        if (booking.canRate) {
          rateAction = AppButton(
            text: 'Rate this booking',
            onPressed: () => _showRatingDialog(booking),
          );
        }
        Widget? payAction;
        if (booking.needsPayment) {
          payAction = AppButton(
            text: 'Pay with GCash',
            icon: Icons.account_balance_wallet_rounded,
            onPressed: () {
              Navigator.pop(sheetContext);
              payBookingWithGcash(context, ref, booking);
            },
          );
        }
        Widget? disputeAction;
        if (booking.status == 'completed' || booking.status == 'cancelled') {
          disputeAction = AppButton(
            text: 'Report Issue / Dispute',
            icon: Icons.report_problem_outlined,
            type: AppButtonType.secondary,
            onPressed: () {
              Navigator.pop(sheetContext);
              _showDisputeDialog(booking);
            },
          );
        }
        return BookingDetailsSheet(
          booking: booking,
          actions: [
            if (payAction != null) ...[payAction, const SizedBox(height: 8)],
            if (cancelAction != null) cancelAction,
            if (rateAction != null) ...[
              const SizedBox(height: 8),
              rateAction,
            ],
            if (disputeAction != null) ...[
              const SizedBox(height: 8),
              disputeAction,
            ],
          ],
        );
      },
    );
    ref.invalidate(customerHistoryProvider);
  }

  Future<void> _showDisputeDialog(BookingBase booking) async {
    final reasonController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report an Issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please describe the issue with this booking:', style: AppTypography.captionDark),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Driver was late, item damaged, overcharged, etc.',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Submit Dispute'),
          ),
        ],
      ),
    );

    if (submitted == true && reasonController.text.trim().isNotEmpty) {
      try {
        await ref.read(customerRepositoryProvider).createDispute(
          bookingId: booking.id,
          bookingType: booking.kind.name, // e.g. transport, food, parcel
          reason: reasonController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your dispute has been submitted for review.'), backgroundColor: AppColors.success),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not submit dispute: $e'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  Future<void> _showRatingDialog(BookingBase booking) async {
    int stars = 5;
    final commentController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate your ride'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    iconSize: 34,
                    icon: Icon(
                      i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Colors.amber,
                    ),
                    onPressed: () => setDialogState(() => stars = i + 1),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Leave a comment (optional)',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit')),
          ],
        ),
      ),
    );

    if (submitted == true) {
      try {
        await ref.read(customerRepositoryProvider).submitRating(
              booking,
              stars: stars,
              comment: commentController.text,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thanks for your feedback!'), backgroundColor: AppColors.success),
          );
        }
      } catch (e, s) {
        AppLog.warn('submitRating failed', e, s);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save your rating. Please try again.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
      if (mounted) setState(() {});
    }
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    ref.invalidate(customerHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.neutral500,
            indicatorColor: AppColors.primary,
            labelStyle: AppTypography.bodyBold.copyWith(fontSize: 14),
            tabs: const [
              Tab(text: 'Rides'),
              Tab(text: 'Food'),
              Tab(text: 'Parcels'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: BookingKind.values.map((kind) {
              return _HistoryList(kind: kind, onOpen: _openDetails);
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _HistoryList extends ConsumerWidget {
  final BookingKind kind;
  final void Function(BookingBase) onOpen;

  const _HistoryList({required this.kind, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(customerHistoryProvider(kind));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load bookings.\n$e',
              textAlign: TextAlign.center, style: AppTypography.body),
        ),
      ),
      data: (bookings) {
        if (bookings.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(customerHistoryProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_rounded, size: 56, color: AppColors.neutral300),
                        const SizedBox(height: 12),
                        Text('No ${kind.label.toLowerCase()} bookings yet',
                            style: AppTypography.captionDark),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(customerHistoryProvider),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: bookings.length,
            itemBuilder: (_, i) => BookingCard(
              booking: bookings[i],
              onTap: () => onOpen(bookings[i]),
            ),
          ),
        );
      },
    );
  }
}
