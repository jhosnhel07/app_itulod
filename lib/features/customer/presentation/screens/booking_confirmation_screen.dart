import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import 'booking_receipt_screen.dart';
import 'gcash_checkout_screen.dart';

/// Shown after the customer fills out the ride form and before the booking
/// is actually created — a last look at the fare and trip details with a
/// single Pay / Confirm action.
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final String pickupAddress;
  final String destinationAddress;
  final double? distanceKm;
  final double fare;
  final String paymentMethod;

  const BookingConfirmationScreen({
    super.key,
    required this.vehicle,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceKm,
    required this.fare,
    required this.paymentMethod,
  });

  @override
  ConsumerState<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends ConsumerState<BookingConfirmationScreen> {
  bool _processing = false;

  bool get _isGcash => widget.paymentMethod == 'gcash';

  Future<void> _confirmAndPay() async {
    setState(() => _processing = true);
    final repo = ref.read(customerRepositoryProvider);
    try {
      final profile = ref.read(authNotifierProvider).profile!;
      final booking = await repo.createTransportBooking(
        customerId: profile.id,
        vehicle: widget.vehicle,
        pickupAddress: widget.pickupAddress,
        destinationAddress: widget.destinationAddress,
        paymentMethod: widget.paymentMethod,
        distanceKm: widget.distanceKm,
      );

      // Null = cash (no in-app payment step). true/false = the GCash
      // checkout's outcome; the webhook is still the source of truth for
      // whether the booking actually ends up marked paid.
      bool? gcashPaid;
      if (_isGcash) {
        try {
          final checkoutUrl = await repo.createGcashCheckoutUrl(booking.id);
          if (!mounted) return;
          gcashPaid = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => GcashCheckoutScreen(checkoutUrl: checkoutUrl)),
          );
        } catch (e) {
          gcashPaid = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('GCash checkout failed: $e. You can pay later from your bookings.'),
                backgroundColor: AppColors.danger,
              ),
            );
          }
        }
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingReceiptScreen(booking: booking, gcashPaid: gcashPaid),
        ),
      );
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Confirm Booking')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trip details', style: AppTypography.bodyBold),
                    const SizedBox(height: 12),
                    _row('From', widget.pickupAddress),
                    _row('To', widget.destinationAddress),
                    _row('Vehicle', widget.vehicle.name),
                    _row('Distance', Formatters.distance(widget.distanceKm)),
                    _row('Payment method', _methodLabel(widget.paymentMethod)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.elevatedShadow,
              ),
              child: Column(
                children: [
                  Text('TOTAL AMOUNT',
                      style: AppTypography.overline
                          .copyWith(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(Formatters.currency(widget.fare),
                      style: AppTypography.display.copyWith(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              text: _isGcash ? 'Pay ${Formatters.currency(widget.fare)}' : 'Confirm Booking',
              icon: _isGcash ? Icons.account_balance_wallet_rounded : Icons.check_rounded,
              isLoading: _processing,
              onPressed: _confirmAndPay,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: AppTypography.captionDark)),
          Expanded(child: Text(value, style: AppTypography.bodyMedium.copyWith(fontSize: 14))),
        ],
      ),
    );
  }

  String _methodLabel(String method) => method == 'gcash' ? 'GCash' : 'Cash on arrival';
}
