import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/customer_repository.dart';
import '../screens/booking_receipt_screen.dart';
import '../screens/gcash_checkout_screen.dart';
import 'customer_bookings_tab.dart' show customerHistoryProvider;
import 'customer_home_tab.dart' show customerHomeSummaryProvider;

/// Starts (or retries) GCash checkout for a booking that still needs payment —
/// shared by the Home tab's active booking card and My Bookings, the only two
/// places a customer can pay for a booking after placing it.
Future<void> payBookingWithGcash(
  BuildContext context,
  WidgetRef ref,
  BookingBase booking,
) async {
  final repo = ref.read(customerRepositoryProvider);

  // Confirm the amount before handing off to GCash — the same "here's what
  // you're about to be charged" step the web app shows.
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _GcashConfirmSheet(booking: booking),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final checkoutUrl = await repo.createGcashCheckoutUrl(booking.id);
    if (!context.mounted) return;
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GcashCheckoutScreen(checkoutUrl: checkoutUrl)),
    );
    // Only transport bookings can be paid online, so this cast is safe.
    if (context.mounted && success != null && booking is TransportBookingModel) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingReceiptScreen(
            booking: booking,
            gcashPaid: success,
            notifyOnDone: false,
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start GCash payment: $e'), backgroundColor: AppColors.danger),
      );
    }
  }
  ref.invalidate(customerHistoryProvider);
  ref.invalidate(customerHomeSummaryProvider);
}

/// "You're about to be charged ₱X with GCash" — the confirm step before the
/// PayMongo hand-off, matching the web app's `openGcashConfirm` modal.
class _GcashConfirmSheet extends StatelessWidget {
  final BookingBase booking;

  const _GcashConfirmSheet({required this.booking});

  @override
  Widget build(BuildContext context) {
    final amount = booking.finalFare ?? booking.estimatedFare;
    final rows = <(String, String)>[
      ('Payment method', 'GCash'),
      if (booking is TransportBookingModel) ...[
        ('Pickup', (booking as TransportBookingModel).pickupAddress),
        ('Destination', (booking as TransportBookingModel).destinationAddress),
      ] else
        ('Booking', booking.routeLine),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Confirm payment', style: AppTypography.h3),
            const SizedBox(height: 4),
            Text(
              'You will be redirected to GCash to authorise this payment.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text('AMOUNT DUE',
                      style: AppTypography.overline
                          .copyWith(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(Formatters.currency(amount),
                      style: AppTypography.h1.copyWith(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration:
                  AppDecorations.flatCard(borderRadius: AppDecorations.radiusSm),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final (label, value) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(label, style: AppTypography.captionDark),
                          ),
                          Expanded(
                            child: Text(value,
                                style: AppTypography.bodyMedium
                                    .copyWith(fontSize: 13.5)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              text: 'Pay ${Formatters.currency(amount)}',
              icon: Icons.account_balance_wallet_rounded,
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
            AppButton(
              text: 'Cancel',
              type: AppButtonType.ghost,
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}
