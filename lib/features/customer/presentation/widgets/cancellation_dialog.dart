import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
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
Future<void> showCancellationDialog(
  BuildContext context,
  WidgetRef ref,
  BookingBase booking,
) async {
  final hasRider = booking.status == 'accepted' || booking.status == 'ongoing';
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
                if (hasRider)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      'A rider is already on their way. Cancelling now will incur a ₱50.00 cancellation fee.',
                      style: AppTypography.captionDark.copyWith(color: AppColors.danger),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      'Please let us know why you are cancelling.',
                      style: AppTypography.captionDark,
                    ),
                  ),
                ..._cancellationReasons.map((reason) => RadioListTile<String>(
                      title: Text(reason, style: AppTypography.bodyMedium),
                      value: reason,
                      groupValue: selectedReason,
                      activeColor: AppColors.primary,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setDialogState(() {
                          selectedReason = val;
                        });
                      },
                    )),
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
    await ref.read(customerRepositoryProvider).cancelBooking(booking, reason: selectedReason!);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not cancel — this booking may have already changed status.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  ref.invalidate(customerHomeSummaryProvider);
  ref.invalidate(customerHistoryProvider);
}
