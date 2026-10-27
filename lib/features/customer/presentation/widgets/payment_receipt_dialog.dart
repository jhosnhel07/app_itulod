import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/customer_repository.dart';

/// The receipt that pops up after paying — the same as the web's
/// payment-return.html: a heading (successful / didn't go through / still
/// confirming) and Reference, Booking, Route, Booked, Method, Status, Amount.
/// While it says pending it asks the server to settle the payment (after
/// GCash "Authorize" that charges it), so it turns Paid within seconds.
///
/// [type] is a booking kind name ('transport', 'food', 'parcel', 'hauling')
/// or 'wallet' for a top-up; [failed] when PayMongo sent the shopper back
/// through the failed URL.
Future<void> showPaymentReceipt(BuildContext context, {required String type, required String id, bool failed = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PaymentReceiptDialog(type: type, id: id, failed: failed),
  );
}

class PaymentReceiptDialog extends ConsumerStatefulWidget {
  final String type;
  final String id;
  final bool failed;
  const PaymentReceiptDialog({super.key, required this.type, required this.id, this.failed = false});

  @override
  ConsumerState<PaymentReceiptDialog> createState() => _PaymentReceiptDialogState();
}

class _PaymentReceiptDialogState extends ConsumerState<PaymentReceiptDialog> {
  Map<String, dynamic>? _row;
  String? _status; // paid | failed | pending; null while the first look is running
  bool _checking = true;

  /// A rider paying what they owe iTULOD (web sql/051) — read like a top-up.
  bool get _isRider => widget.type == 'rider';
  bool get _isWallet => widget.type == 'wallet' || _isRider;

  @override
  void initState() {
    super.initState();
    _settle();
  }

  /// Like payment-return.html: show the receipt right away, then ask the
  /// server up to 10 times (it charges an authorized GCash payment).
  Future<void> _settle() async {
    final repo = ref.read(customerRepositoryProvider);
    var row = await repo.fetchPaymentReceipt(widget.type, widget.id);
    if (!mounted) return;
    setState(() {
      _row = row;
      _status = row?['payment_status'] as String?;
    });
    if (widget.failed) {
      setState(() {
        _status = 'failed';
        _checking = false;
      });
      return;
    }
    for (var attempt = 0; _status == 'pending' && attempt < 10; attempt++) {
      final next = await repo.syncPayment(widget.type, widget.id);
      row = await repo.fetchPaymentReceipt(widget.type, widget.id);
      if (!mounted) return;
      setState(() {
        _row = row ?? _row;
        _status = next ?? row?['payment_status'] as String? ?? _status;
      });
      if (_status == 'pending') await Future<void>.delayed(Duration(milliseconds: attempt < 3 ? 800 : 1500));
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final (icon, color, title, sub) = switch (status) {
      'paid' => (
          Icons.check_circle_rounded,
          AppColors.success,
          'Payment successful!',
          _isRider
              ? 'iTULOD received it — your balance is updated on Earnings.'
              : _isWallet ? "It's in your wallet — ready to spend on your next ride." : 'Your booking is confirmed. See you soon!',
        ),
      'failed' => (
          Icons.cancel_rounded,
          AppColors.danger,
          'Payment did not go through',
          _isRider
              ? 'Your balance is unchanged. You can try again.'
              : _isWallet ? 'Your wallet was not topped up. You can try again.' : 'You can retry from My Bookings.',
        ),
      _ when _checking => (Icons.hourglass_top_rounded, AppColors.primary, 'Checking your payment…', 'This only takes a moment.'),
      _ => (
          Icons.schedule_rounded,
          AppColors.neutral500,
          'Still confirming…',
          "This can take a minute — we'll update My Bookings as soon as PayMongo confirms.",
        ),
    };
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: status == null || (_checking && status == 'pending')
                  ? const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3))
                  : Icon(icon, size: 52, color: color),
            ),
            const SizedBox(height: 12),
            Text(title, key: const Key('receipt-title'), style: AppTypography.h3, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(sub, style: AppTypography.caption, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_row != null) _receipt(_row!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receipt(Map<String, dynamic> b) {
    final route = switch (widget.type) {
      'transport' => (b['pickup_address'], b['destination_address']),
      'food' => (b['restaurant_name'], b['delivery_address']),
      'parcel' => (b['sender_address'], b['receiver_address']),
      'hauling' => (b['pickup_address'], b['dropoff_address']),
      _ => (null, null),
    };
    final amount = (b['final_fare'] ?? b['estimated_fare']) as num?;
    final method = b['payment_method']?.toString();
    final rows = <(String, Widget)>[
      if (b['paymongo_reference'] != null) ('Reference', _value(b['paymongo_reference'].toString())),
      _isRider
          ? ('Paid to', _value('iTULOD (commission)'))
          : (_isWallet ? 'Top-up' : 'Booking', _value('#${widget.id.substring(0, 8)}')),
      if (route.$1 != null && route.$2 != null) ('Route', _value('${route.$1} → ${route.$2}')),
      (_isWallet ? 'Date' : 'Booked', _value(Formatters.date(DateTime.tryParse(b['created_at']?.toString() ?? '')))),
      ('Method', _value(method == 'gcash' ? 'GCash' : method == 'wallet' ? 'iTULOD Wallet' : (method ?? '—'))),
      ('Status', _statusChip(_status ?? 'pending')),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 84, child: Text(label, style: AppTypography.caption)),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: value)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.neutral50,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(top: BorderSide(color: AppColors.cardBorder)),
            ),
            child: Row(
              children: [
                Text('Amount', style: AppTypography.caption),
                const Spacer(),
                Text(Formatters.currency(amount ?? 0), key: const Key('receipt-amount'), style: AppTypography.h3.copyWith(fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _value(String text) =>
      Text(text, textAlign: TextAlign.right, style: AppTypography.bodyBold.copyWith(fontSize: 13));

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'paid' => ('Paid', AppColors.success),
      'failed' => ('Failed', AppColors.danger),
      _ => ('Awaiting confirmation', AppColors.warning),
    };
    return Container(
      key: const Key('receipt-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
