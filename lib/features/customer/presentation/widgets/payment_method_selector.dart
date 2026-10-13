import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../screens/booking_confirmation_screen.dart' show paymentMethodLabel;

/// Cash / GCash / Wallet picker shared by the food and parcel forms — the
/// same three options as the web's `*-payment` selects.
class PaymentMethodSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  /// Explains when an online payment is actually charged.
  final String? onlineNote;

  const PaymentMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.onlineNote,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment method', style: AppTypography.bodyBold),
            const SizedBox(height: 10),
            RadioGroup<String>(
              groupValue: value,
              onChanged: (v) => onChanged(v ?? 'cash'),
              child: Column(
                children: [
                  for (final method in const ['cash', 'gcash', 'wallet'])
                    RadioListTile<String>(
                      value: method,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      title: Text(paymentMethodLabel(method),
                          style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
                    ),
                ],
              ),
            ),
            if (value != 'cash' && onlineNote != null) ...[
              const SizedBox(height: 4),
              Text(onlineNote!, style: AppTypography.caption),
            ],
          ],
        ),
      ),
    );
  }
}
