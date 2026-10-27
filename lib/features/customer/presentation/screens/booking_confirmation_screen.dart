import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/booking_stepper.dart';
import '../../../../shared/widgets/success_moment.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_repository.dart';
import 'booking_receipt_screen.dart';

/// Shown after the customer fills out the ride form and before the booking
/// is actually created — a last look at the fare and trip details with a
/// single Confirm action.
///
/// This screen only places the booking. GCash/wallet payment (when chosen)
/// happens afterwards, from the Home tab's active booking card or My
/// Bookings — it is never started inline here. Tips are given after the trip
/// from the rating dialog (the server only credits a tip once the booking is
/// completed).
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final String pickupAddress;
  final String destinationAddress;
  final LatLng? pickupPoint;
  final LatLng? destinationPoint;
  final double? distanceKm;
  final int passengers;
  /// The ride was placed — the booking screen drops its draft (LastPlace).
  final VoidCallback? onBooked;
  final double fare;
  final String paymentMethod;
  final DateTime? scheduledFor;
  final List<({String address, LatLng? point})> stops;

  const BookingConfirmationScreen({
    super.key,
    required this.vehicle,
    required this.pickupAddress,
    required this.destinationAddress,
    this.pickupPoint,
    this.destinationPoint,
    required this.distanceKm,
    this.passengers = 1,
    this.onBooked,
    required this.fare,
    required this.paymentMethod,
    this.scheduledFor,
    this.stops = const [],
  });

  @override
  ConsumerState<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends ConsumerState<BookingConfirmationScreen> {
  bool _processing = false;

  bool get _paysOnline => widget.paymentMethod == 'gcash' || widget.paymentMethod == 'wallet';
  double get _total => widget.fare;

  Future<void> _confirm() async {
    setState(() => _processing = true);
    final repo = ref.read(customerRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = ref.read(authNotifierProvider).profile!;
      final booking = await repo.createTransportBooking(
        customerId: profile.id,
        vehicle: widget.vehicle,
        pickupAddress: widget.pickupAddress,
        destinationAddress: widget.destinationAddress,
        pickupPoint: widget.pickupPoint,
        destinationPoint: widget.destinationPoint,
        paymentMethod: widget.paymentMethod,
        distanceKm: widget.distanceKm,
        scheduledFor: widget.scheduledFor,
        stops: widget.stops,
        passengers: widget.passengers,
      );
      widget.onBooked?.call();

      // The booking is placed only — online payment (when chosen) is started
      // later from Home or My Bookings, not inline here.
      if (!mounted) return;
      await showSuccessMoment(
        context,
        title: widget.scheduledFor != null ? 'Ride scheduled' : 'Ride booked!',
        message: widget.scheduledFor != null
            ? 'For ${Formatters.date(widget.scheduledFor!)}. We\'ll line up a rider closer to the time.'
            : 'Waiting for a rider to accept.',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingReceiptScreen(
            booking: booking,
            checkoutAttempted: false,
          ),
        ),
      );
      return;
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Booking failed: ${_clean(e)}'), backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  static String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

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
            // Last step of BookRideScreen's Where → Vehicle → Payment.
            BookingStepsHeader(
              titles: const ['Where', 'Vehicle', 'Payment', 'Confirm'],
              current: 3,
              fare: Formatters.currency(_total),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trip details', style: AppTypography.bodyBold),
                    const SizedBox(height: 12),
                    _row('From', widget.pickupAddress),
                    for (var i = 0; i < widget.stops.length; i++)
                      _row('Stop ${i + 1}', widget.stops[i].address),
                    _row('To', widget.destinationAddress),
                    _row('Passengers', '${widget.passengers}'),
                    _row('Vehicle', widget.vehicle.name),
                    _row('Distance', Formatters.distance(widget.distanceKm)),
                    if (widget.scheduledFor != null)
                      _row('Scheduled for', Formatters.date(widget.scheduledFor!)),
                    _row('Payment method', paymentMethodLabel(widget.paymentMethod)),
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
                      style: AppTypography.overline.copyWith(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(Formatters.currency(_total),
                      style: AppTypography.display.copyWith(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_paysOnline) ...[
              Text(
                'You\'ll pay with ${paymentMethodLabel(widget.paymentMethod)} after booking — from Home or My Bookings.',
                style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            AppButton(
              text: 'Confirm Booking',
              icon: Icons.check_rounded,
              isLoading: _processing,
              onPressed: _confirm,
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
}

/// Human label for a booking's payment method — shared by the booking forms,
/// confirmation, and details screens.
String paymentMethodLabel(String? method) {
  switch (method) {
    case 'gcash':
      return 'GCash';
    case 'wallet':
      return 'Wallet';
    case 'card':
      return 'Card';
    default:
      return 'Cash';
  }
}
