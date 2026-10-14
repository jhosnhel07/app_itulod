import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/rider_repository.dart';

final riderBalanceProvider = FutureProvider.autoDispose<RiderBalance?>((ref) {
  return ref.watch(riderRepositoryProvider).fetchBalance();
});

/// "iTULOD owes you ₱X" / "You owe iTULOD ₱Y" plus COD still to hand over —
/// the app twin of the web's loadRiderBalance() on the Earnings tab.
class RiderBalanceCard extends ConsumerWidget {
  const RiderBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(riderBalanceProvider).valueOrNull;
    if (b == null) return const SizedBox.shrink();

    final owed = b.net > 0;
    final due = b.net < 0;
    final headline = owed
        ? 'iTULOD owes you ${Formatters.currency(b.net)}'
        : due
            ? 'You owe iTULOD ${Formatters.currency(-b.net)}'
            : 'All settled';
    final detail = [
      '${Formatters.currency(b.onlineEarnings)} from GCash/wallet trips',
      '${Formatters.currency(b.cashCommission)} commission on cash trips',
      if (b.payoutsMade > 0) '${Formatters.currency(b.payoutsMade)} paid out',
      if (b.collectionsMade > 0) '${Formatters.currency(b.collectionsMade)} paid in',
    ].join(' · ');

    return Column(
      children: [
        _tile(
          icon: Icons.balance_rounded,
          bg: owed ? AppColors.success50 : due ? AppColors.blush : AppColors.primary50,
          fg: owed ? const Color(0xFF157A4D) : due ? AppColors.secondaryDark : AppColors.primary,
          title: headline,
          body: detail,
        ),
        if (b.codUnremitted > 0) ...[
          const SizedBox(height: 10),
          _tile(
            icon: Icons.payments_rounded,
            bg: AppColors.blush,
            fg: AppColors.secondaryDark,
            title: '${Formatters.currency(b.codUnremitted)} COD to hand over',
            body: 'Cash you collected for senders. Open each parcel in History and tap "COD handed over".',
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required Color bg,
    required Color fg,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: fg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyBold.copyWith(fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(body, style: AppTypography.caption.copyWith(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
