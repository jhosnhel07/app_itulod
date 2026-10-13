import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../data/customer_repository.dart';
import 'customer_home_tab.dart' show customerHomeSummaryProvider;
import 'customer_bookings_tab.dart' show customerHistoryProvider;

const List<String> _cancellationReasons = [
  'Wait time is too long',
  'Driver asked me to cancel',
  'Changed my mind',
  'Selected wrong pickup/dropoff',
  'Price is too high',
  'Other',
];

/// Shows a dialog for the user to pick a cancellation reason, and if confirmed, cancels the booking.
///
/// Cancelling after a rider accepted records platform_config's cancellation
/// fee (the DB trigger sets it — never the client); the dialog warns with the
/// real configured amount, like the web's cancelBooking().
Future<void> showCancellationDialog(
  BuildContext context,
  WidgetRef ref,
  BookingBase booking,
) async {
  final repo = ref.read(customerRepositoryProvider);
  final riderAccepted = booking.status == 'accepted';
  final fee = riderAccepted ? await repo.fetchCancellationFee() : null;
  if (!context.mounted) return;

  String? selectedReason;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Cancel this booking?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    !riderAccepted
                        ? 'Please let us know why you are cancelling.'
                        : (fee != null && fee > 0)
                            ? 'A rider has already accepted — cancelling now may incur a ${Formatters.currency(fee)} cancellation fee.'
                            : 'A rider has already accepted this booking.',
                    style: riderAccepted
                        ? AppTypography.captionDark.copyWith(color: AppColors.danger)
                        : AppTypography.captionDark,
                  ),
                ),
                RadioGroup<String>(
                  groupValue: selectedReason,
                  onChanged: (val) => setDialogState(() => selectedReason = val),
                  child: Column(
                    children: [
                      for (final reason in _cancellationReasons)
                        RadioListTile<String>(
                          title: Text(reason, style: AppTypography.bodyMedium),
                          value: reason,
                          activeColor: AppColors.primary,
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Cancel booking'),
            ),
          ],
        );
      },
    ),
  );

  if (confirmed != true || selectedReason == null) return;

  try {
    await repo.cancelBooking(booking, reason: selectedReason!);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not cancel — this booking may have already changed status.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  ref.invalidate(customerHomeSummaryProvider);
  ref.invalidate(customerHistoryProvider);
}
