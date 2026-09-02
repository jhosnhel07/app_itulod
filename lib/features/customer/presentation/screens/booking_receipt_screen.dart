import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../data/customer_repository.dart';
import '../widgets/customer_bookings_tab.dart' show authProfileIdProvider;

/// Simple receipt shown right after a transport booking is created.
/// [gcashPaid] is null for cash bookings, or the outcome of the GCash
/// checkout WebView for GCash bookings — the webhook remains the source of
/// truth for the booking's actual `payment_status`.
class BookingReceiptScreen extends ConsumerWidget {
  final TransportBookingModel booking;
  final bool? gcashPaid;

  const BookingReceiptScreen({
    super.key,
    required this.booking,
    this.gcashPaid,
  });

  String get _paymentStatusLabel {
    if (booking.paymentMethod != 'gcash') return 'Pay on arrival';
    if (gcashPaid == true) return 'Submitted — confirming with GCash';
    return 'Pending — pay anytime from your bookings';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppColors.success50,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.25), width: 6),
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.success, size: 46),
              ),
              const SizedBox(height: 20),
              Text('Booking Confirmed!', style: AppTypography.h2),
              const SizedBox(height: 6),
              Text(
                'A rider will accept your ride shortly.',
                style: AppTypography.body.copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Reference', '#${booking.id.substring(0, 8).toUpperCase()}'),
                      _row('From', booking.pickupAddress),
                      _row('To', booking.destinationAddress),
                      _row('Fare', Formatters.currency(booking.estimatedFare)),
                      _row('Payment', _paymentStatusLabel),
                      _row('Booked on', Formatters.date(booking.createdAt)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              AppButton(
                text: 'Done',
                onPressed: () => _finish(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finish(BuildContext context, WidgetRef ref) {
    final userId = ref.read(authProfileIdProvider);
    if (userId.isNotEmpty) {
      ref.read(customerRepositoryProvider).notifyBookingComplete(
            userId: userId,
            title: 'Booking confirmed',
            message: 'Your ride from ${booking.pickupAddress} to ${booking.destinationAddress} is booked.',
          );
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Your booking is confirmed!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: AppTypography.captionDark)),
          Expanded(child: Text(value, style: AppTypography.bodyMedium.copyWith(fontSize: 14))),
        ],
      ),
    );
  }
}
