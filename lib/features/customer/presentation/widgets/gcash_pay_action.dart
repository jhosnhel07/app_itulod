import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/customer_repository.dart';
import '../providers/wallet_provider.dart';
import 'payment_receipt_dialog.dart';
import '../screens/gcash_checkout_screen.dart';
import 'customer_bookings_tab.dart' show customerHistoryProvider;
import 'customer_home_tab.dart' show customerHomeSummaryProvider;

/// Starts (or retries) online checkout for a booking that still needs payment —
/// shared by the Home tab's active booking card and My Bookings.
Future<void> payBookingOnline(
  BuildContext context,
  WidgetRef ref,
  BookingBase booking,
) async {
  final repo = ref.read(customerRepositoryProvider);

  // Confirm the amount before handing off
  final method = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _GcashConfirmSheet(booking: booking),
  );
  if (method == null || !context.mounted) return;

  // create-payment charges whichever table booking_type names — final_fare
  // for food/parcel once the rider confirmed it, the estimate for rides.
  final bookingType = booking.kind.name;
  try {
    if (method == 'wallet') {
      await repo.payWithWallet(booking.id, bookingType: bookingType);
      ref.invalidate(walletProvider);
      if (!context.mounted) return;
      await showPaymentReceipt(context, type: bookingType, id: booking.id);
    } else if (method == 'gcash') {
      final checkoutUrl = await repo.createGcashCheckoutUrl(booking.id, bookingType: bookingType);
      if (!context.mounted) return;
      final back = await Navigator.of(context).push<GcashReturn>(
        MaterialPageRoute(builder: (_) => GcashCheckoutScreen(checkoutUrl: checkoutUrl)),
      );
      // Back from PayMongo (Authorize or Fail): the receipt, like the web's
      // payment-return page — it settles the payment while it shows.
      if (context.mounted && back != null) {
        await showPaymentReceipt(context, type: bookingType, id: booking.id, failed: !back.success);
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
  ref.invalidate(customerHistoryProvider);
  ref.invalidate(customerHomeSummaryProvider);
}

/// "You're about to be charged ₱X with GCash" — the confirm step before the
/// PayMongo hand-off, matching the web app's `openGcashConfirm` modal.
class _GcashConfirmSheet extends ConsumerWidget {
  final BookingBase booking;

  const _GcashConfirmSheet({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = booking.payableAmount ?? 0.0;
    final b = booking;
    final rows = <(String, String)>[
      ('Payment method', 'GCash / Wallet'),
      if (b is TransportBookingModel) ...[
        ('Pickup', b.pickupAddress),
        ('Destination', b.destinationAddress),
      ] else if (b is FoodDeliveryModel) ...[
        ('Restaurant', b.restaurantName),
        ('Deliver to', b.deliveryAddress),
      ] else if (b is ParcelDeliveryModel) ...[
        ('To', b.receiverName),
        ('Drop-off', b.receiverAddress),
      ] else if (b is HaulingBookingModel) ...[
        ('Pickup', b.pickupAddress),
        ('Drop-off', b.dropoffAddress),
        ('Items', b.categoryLabel),
      ],
    ];

    final walletAsync = ref.watch(walletProvider);
    final walletBalance = walletAsync.valueOrNull?.balance ?? 0.0;
    final canUseWallet = walletBalance >= amount;

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
              'Choose your payment method for this booking.',
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
              text: 'Pay with GCash',
              icon: Icons.account_balance_wallet_rounded,
              onPressed: () => Navigator.pop(context, 'gcash'),
            ),
            if (canUseWallet) ...[
              const SizedBox(height: 8),
              AppButton(
                text: 'Pay from Wallet (${Formatters.currency(walletBalance)})',
                icon: Icons.account_balance_wallet_rounded,
                onPressed: () => Navigator.pop(context, 'wallet'),
              ),
            ],
            const SizedBox(height: 8),
            AppButton(
              text: 'Cancel',
              type: AppButtonType.ghost,
              onPressed: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
  }
}
