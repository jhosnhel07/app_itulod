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

/// Shown after the customer fills out the ride form and before the booking
/// is actually created — a last look at the fare and trip details with a
/// single Confirm action.
///
/// This screen only places the booking. GCash payment (when chosen) happens
/// afterwards, from the Home tab's active booking card or My Bookings — it is
/// never started inline here.
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final String pickupAddress;
  final String destinationAddress;
  final double? distanceKm;
  final double fare;
  final String paymentMethod;
  final DateTime? scheduledFor;

  final List<String>? stops;
  final String? promoCode;

  const BookingConfirmationScreen({
    super.key,
    required this.vehicle,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceKm,
    required this.fare,
    required this.paymentMethod,
    this.scheduledFor,
    this.stops,
    this.promoCode,
  });

  @override
  ConsumerState<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends ConsumerState<BookingConfirmationScreen> {
  bool _processing = false;
  double _tipAmount = 0.0;
  final _promoController = TextEditingController();
  bool _validatingPromo = false;
  bool _promoApplied = false;
  double _promoDiscount = 0.0;
  String? _appliedPromoCode;

  bool get _isGcash => widget.paymentMethod == 'gcash';
  double get _total => (widget.fare - _promoDiscount).clamp(0, double.infinity) + _tipAmount;

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() => _validatingPromo = true);
    final repo = ref.read(customerRepositoryProvider);
    final promo = await repo.validatePromoCode(code);
    
    if (!mounted) return;
    if (promo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or expired promo code'), backgroundColor: AppColors.warning),
      );
      setState(() => _validatingPromo = false);
      return;
    }

    double discount = 0.0;
    if (promo['discount_amount'] != null) {
      discount = (promo['discount_amount'] as num).toDouble();
    } else if (promo['discount_percent'] != null) {
      final percent = (promo['discount_percent'] as num).toDouble();
      discount = widget.fare * (percent / 100);
      if (promo['max_discount'] != null) {
        final maxD = (promo['max_discount'] as num).toDouble();
        if (discount > maxD) discount = maxD;
      }
    }

    setState(() {
      _validatingPromo = false;
      _promoApplied = true;
      _promoDiscount = discount;
      _appliedPromoCode = promo['code'] as String;
    });
  }

  Future<void> _confirm() async {
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
        tipAmount: _tipAmount,
        scheduledFor: widget.scheduledFor,
        promoCode: _appliedPromoCode,
        stops: widget.stops,
      );

      // The booking is placed only — GCash checkout (when chosen) is started
      // later from Home or My Bookings, not inline here.
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
                    if (widget.scheduledFor != null)
                      _row('Scheduled For', Formatters.date(widget.scheduledFor!)),
                    _row('Payment method', _methodLabel(widget.paymentMethod)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add a tip for your rider', style: AppTypography.bodyBold),
                    const SizedBox(height: 4),
                    Text('100% of tips go to the rider', style: AppTypography.caption),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [0.0, 20.0, 50.0, 100.0].map((amount) {
                        final selected = _tipAmount == amount;
                        return InkWell(
                          onTap: () => setState(() => _tipAmount = amount),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected ? AppColors.primary : AppColors.cardBorder,
                              ),
                            ),
                            child: Text(
                              amount == 0 ? 'No tip' : '₱\${amount.toInt()}',
                              style: AppTypography.bodyBold.copyWith(
                                color: selected ? Colors.white : AppColors.neutral700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Promo code', style: AppTypography.bodyBold),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _promoController,
                            decoration: const InputDecoration(
                              hintText: 'Enter promo code',
                              contentPadding: EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onChanged: (v) {
                              if (_promoApplied) {
                                setState(() {
                                  _promoApplied = false;
                                  _promoDiscount = 0.0;
                                  _appliedPromoCode = null;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _validatingPromo || _promoApplied ? null : _applyPromo,
                          child: _validatingPromo 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_promoApplied ? 'Applied' : 'Apply'),
                        ),
                      ],
                    ),
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
                  if (_promoApplied) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Base Fare', style: AppTypography.caption.copyWith(color: Colors.white70)),
                        Text(Formatters.currency(widget.fare), style: AppTypography.caption.copyWith(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Promo Discount', style: AppTypography.caption.copyWith(color: Colors.white70)),
                        Text('-${Formatters.currency(_promoDiscount)}', style: AppTypography.caption.copyWith(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('TOTAL AMOUNT',
                      style: AppTypography.overline
                          .copyWith(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(Formatters.currency(_total),
                      style: AppTypography.display.copyWith(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_isGcash) ...[
              const SizedBox(height: 4),
              Text(
                'You\'ll pay via GCash after booking — from Home or My Bookings.',
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

  String _methodLabel(String method) => method == 'gcash' ? 'GCash' : 'Cash on arrival';
}
