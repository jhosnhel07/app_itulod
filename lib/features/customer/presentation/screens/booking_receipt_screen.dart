import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../data/customer_repository.dart';
import '../widgets/customer_bookings_tab.dart' show customerHistoryProvider;
import '../widgets/customer_home_tab.dart' show customerHomeSummaryProvider;

/// Live payment receipt shown after a transport booking's GCash checkout —
/// a Flutter port of the web app's `payment-return.html`.
///
/// [gcashPaid] is:
///  * `null` for cash bookings — the screen just confirms the booking.
///  * `true` when PayMongo redirected through its success URL.
///  * `false` when PayMongo redirected through its failed URL.
///
/// For GCash the screen polls `transport_bookings` for a few seconds because
/// the `paymongo-webhook` function — not the redirect — is the source of truth
/// for `payment_status`, and it can land a moment after the customer returns.
class BookingReceiptScreen extends ConsumerStatefulWidget {
  final TransportBookingModel booking;
  final bool? gcashPaid;

  /// The post-booking flow drops a "booking confirmed" notification; the
  /// pay-later retry flow does not.
  final bool notifyOnDone;

  /// False right after placing a GCash booking, before any checkout was
  /// ever opened — the screen then shows a plain "booking placed, pay later"
  /// confirmation instead of polling for a payment that was never started.
  final bool checkoutAttempted;

  const BookingReceiptScreen({
    super.key,
    required this.booking,
    this.gcashPaid,
    this.notifyOnDone = true,
    this.checkoutAttempted = true,
  });

  @override
  ConsumerState<BookingReceiptScreen> createState() =>
      _BookingReceiptScreenState();
}

class _BookingReceiptScreenState extends ConsumerState<BookingReceiptScreen> {
  static const _maxPolls = 14;
  static const _pollGap = Duration(milliseconds: 700);

  bool get _isCash => widget.booking.paymentMethod == null || widget.booking.paymentMethod == 'cash';
  String get _methodName => widget.booking.paymentMethod == 'wallet' ? 'your wallet' : 'GCash';

  /// GCash was chosen but checkout was never opened yet (booking just
  /// placed) — nothing to poll for, so show a plain confirmation instead.
  bool get _payLater =>
      !_isCash && !widget.checkoutAttempted && widget.gcashPaid == null;

  late String _status; // paid | failed | pending
  TransportPaymentRow? _row;
  bool _polling = false;
  Timer? _pollTimer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _status = widget.gcashPaid == false
        ? 'failed'
        : (widget.booking.paymentStatus ?? 'pending');

    if (!_isCash && !_payLater) {
      _row = TransportPaymentRow(
        paymentStatus: _status,
        paymentMethod: 'gcash',
        paymentSourceId: null,
        estimatedFare: widget.booking.estimatedFare,
        finalFare: widget.booking.finalFare,
        createdAt: widget.booking.createdAt,
        pickupAddress: widget.booking.pickupAddress,
        destinationAddress: widget.booking.destinationAddress,
      );
      // A "failed" redirect has nothing left to wait for.
      if (widget.gcashPaid != false) _startPolling();
      // Even on failure, one read picks up the reference number / real status.
      _refreshOnce();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    setState(() => _polling = true);
    _pollTimer = Timer.periodic(_pollGap, (timer) async {
      _polls++;
      final settled = await _refreshOnce();
      if (settled || _polls >= _maxPolls) {
        timer.cancel();
        if (mounted) setState(() => _polling = false);
      }
    });
  }

  /// Returns true once the payment has reached a terminal state.
  Future<bool> _refreshOnce() async {
    final row = await ref
        .read(customerRepositoryProvider)
        .fetchTransportPaymentRow(widget.booking.id);
    if (!mounted) return true;
    if (row == null) return false;

    setState(() {
      _row = row;
      // A "failed" redirect wins until the row explicitly says "paid".
      if (widget.gcashPaid == false && row.paymentStatus != 'paid') {
        _status = 'failed';
      } else {
        _status = row.paymentStatus ?? 'pending';
      }
    });
    return _status == 'paid' || _status == 'failed';
  }

  // ── Presentation ──────────────────────────────────────────────────────

  ({IconData icon, Color color, String title, String sub}) get _heading {
    if (_isCash) {
      return (
        icon: Icons.check_rounded,
        color: AppColors.success,
        title: 'Booking Confirmed!',
        sub: 'A rider will accept your ride shortly. Pay in cash on arrival.',
      );
    }
    if (_payLater) {
      return (
        icon: Icons.check_rounded,
        color: AppColors.success,
        title: 'Booking Placed!',
        sub: 'A rider will accept your ride shortly. Pay with $_methodName anytime from Home or My Bookings.',
      );
    }
    switch (_status) {
      case 'paid':
        return (
          icon: Icons.check_rounded,
          color: AppColors.success,
          title: 'Payment successful!',
          sub: 'Your booking is confirmed — a rider will accept your ride shortly.',
        );
      case 'failed':
        return (
          icon: Icons.close_rounded,
          color: AppColors.danger,
          title: 'Payment didn\'t go through',
          sub: 'No charge was made. You can retry anytime from My Bookings.',
        );
      default:
        return (
          icon: Icons.hourglass_top_rounded,
          color: AppColors.warning,
          title: 'Still confirming your payment…',
          sub: 'This can take a minute. We\'ll update My Bookings as soon as GCash confirms.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _heading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _StatusIcon(icon: h.icon, color: h.color, spinning: _polling),
                    const SizedBox(height: 20),
                    Text(h.title,
                        style: AppTypography.h2, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      h.sub,
                      style: AppTypography.body
                          .copyWith(color: AppColors.neutral500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _receiptCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: AppButton(
                text: _polling ? 'Done' : 'Back to Home',
                onPressed: () => _finish(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptCard() {
    final b = widget.booking;
    final rows = <(String, Widget)>[];

    if (_isCash) {
      rows.addAll([
        ('Reference', _text('#${b.id.substring(0, 8).toUpperCase()}')),
        ('From', _text(b.pickupAddress)),
        ('To', _text(b.destinationAddress)),
        ('Payment', _text('Cash on arrival')),
        ('Booked', _text(Formatters.date(b.createdAt))),
      ]);
    } else if (_payLater) {
      rows.addAll([
        ('Booking', _text('#${b.id.substring(0, 8).toUpperCase()}')),
        ('Route', _text('${b.pickupAddress} → ${b.destinationAddress}')),
        ('Booked', _text(Formatters.date(b.createdAt))),
        ('Payment', _text('${widget.booking.paymentMethod == 'wallet' ? 'Wallet' : 'GCash'} — pay from Home or My Bookings')),
      ]);
    } else {
      final ref = _row?.paymentSourceId;
      if (ref != null && ref.isNotEmpty) {
        rows.add(('Reference', _text(ref, mono: true)));
      }
      rows.addAll([
        ('Booking', _text('#${b.id.substring(0, 8).toUpperCase()}')),
        ('Route', _text('${b.pickupAddress} → ${b.destinationAddress}')),
        ('Booked', _text(Formatters.date(_row?.createdAt ?? b.createdAt))),
        ('Method', _text('GCash')),
        (
          'Status',
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              status: _status == 'pending' ? 'pending' : _status,
            ),
          ),
        ),
      ]);
    }

    final amount = _row?.fare ?? b.finalFare ?? b.estimatedFare;

    return Container(
      decoration: AppDecorations.softCard(),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Column(
        children: [
          for (final (label, value) in rows) _row2(label, value),
          const Divider(height: 22),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text('Amount',
                    style: AppTypography.bodyBold.copyWith(fontSize: 15)),
                const Spacer(),
                Text(Formatters.currency(amount),
                    style: AppTypography.h3
                        .copyWith(color: AppColors.primaryDark, fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row2(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: AppTypography.captionDark),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _text(String value, {bool mono = false}) {
    return Text(
      value,
      style: mono
          ? AppTypography.caption.copyWith(
              fontFamily: 'monospace',
              color: AppColors.neutral700,
              fontSize: 12.5,
            )
          : AppTypography.bodyMedium.copyWith(fontSize: 13.5),
    );
  }

  void _finish(BuildContext context) {
    // Booking-lifecycle notifications ("Rider assigned", "Completed", …) are
    // now written server-side by the notify_on_booking_change trigger.
    ref.invalidate(customerHistoryProvider);
    ref.invalidate(customerHomeSummaryProvider);

    Navigator.of(context).popUntil((route) => route.isFirst);

    final msg = _isCash
        ? 'Your booking is confirmed!'
        : _payLater
            ? 'Booking placed! Pay with $_methodName anytime from Home or My Bookings.'
            : switch (_status) {
            'paid' => 'Payment received — your booking is confirmed!',
            'failed' => 'Payment did not go through. You can retry from My Bookings.',
            _ => 'We\'ll confirm your GCash payment shortly.',
          };
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            _status == 'failed' ? AppColors.danger : AppColors.success,
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool spinning;

  const _StatusIcon({
    required this.icon,
    required this.color,
    required this.spinning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.25), width: 6),
      ),
      child: spinning
          ? Padding(
              padding: const EdgeInsets.all(26),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            )
          : Icon(icon, color: color, size: 44),
    );
  }
}
