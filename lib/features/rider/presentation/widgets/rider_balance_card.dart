import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../customer/presentation/screens/gcash_checkout_screen.dart';
import '../../../customer/presentation/widgets/payment_receipt_dialog.dart';
import '../../data/rider_repository.dart';

final riderBalanceProvider = FutureProvider.autoDispose<RiderBalance?>((ref) {
  return ref.watch(riderRepositoryProvider).fetchBalance();
});

/// The latest "I paid the admin" and the payments with iTULOD (web sql/051).
final riderSettlingProvider = FutureProvider.autoDispose<RiderSettling>((ref) {
  final id = ref.watch(authNotifierProvider).profile?.id;
  if (id == null) return const RiderSettling();
  return ref.watch(riderRepositoryProvider).fetchSettling(id);
});

/// PayMongo's smallest GCash payment.
const gcashMinimum = 20.0;

/// "Pay with GCash" for exactly what the rider owes: checkout, then the
/// receipt (which confirms it), then the balance and debt banner refresh.
/// Web twin: payDuesWithGcash() in rider.js.
Future<void> payRiderDues(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final start = await ref.read(riderRepositoryProvider).startDuesPayment();
    final result = await navigator.push<GcashReturn>(
      MaterialPageRoute(builder: (_) => GcashCheckoutScreen(checkoutUrl: start.checkoutUrl)),
    );
    if (result != null && navigator.mounted) {
      await showPaymentReceipt(navigator.context, type: 'rider', id: start.id, failed: !result.success);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.toString().replaceFirst('Exception: ', '')),
      backgroundColor: AppColors.danger,
    ));
  } finally {
    ref
      ..invalidate(riderBalanceProvider)
      ..invalidate(riderSettlingProvider);
  }
}

/// "iTULOD owes you ₱X" / "You owe iTULOD ₱Y" with Pay with GCash and
/// I paid the admin, the payments history, and COD still to hand over —
/// the app twin of the web's loadRiderBalance() on the Earnings tab.
class RiderBalanceCard extends ConsumerWidget {
  const RiderBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(riderBalanceProvider).valueOrNull;
    if (b == null) return const SizedBox.shrink();
    final settling = ref.watch(riderSettlingProvider).valueOrNull ?? const RiderSettling();

    final net = (b.net * 100).round() / 100;
    final owed = net > 0;
    final due = net < 0;
    final owes = due ? -net : 0.0;
    final headline = owed
        ? 'iTULOD owes you ${Formatters.currency(net)}'
        : due
            ? 'You owe iTULOD ${Formatters.currency(owes)}'
            : '${Formatters.currency(0)} · All settled';
    final detail = [
      '${Formatters.currency(b.onlineEarnings)} from GCash/wallet trips',
      '${Formatters.currency(b.cashCommission)} commission on cash trips',
      if (b.payoutsMade > 0) '${Formatters.currency(b.payoutsMade)} paid out',
      if (b.collectionsMade > 0) '${Formatters.currency(b.collectionsMade)} paid in',
    ].join(' · ');
    final pending = settling.pending;
    final rejected = settling.rejected;

    return Column(
      children: [
        Container(
          key: const Key('balance-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(
                icon: Icons.balance_rounded,
                bg: owed
                    ? AppColors.success50
                    : due
                        ? AppColors.blush
                        : AppColors.primary50,
                fg: owed
                    ? const Color(0xFF157A4D)
                    : due
                        ? AppColors.secondaryDark
                        : AppColors.primary,
                title: headline,
                body: detail,
              ),
              if (due && pending != null)
                _note(
                    Icons.schedule_rounded,
                    AppColors.warning,
                    'Waiting for the admin to confirm your ${Formatters.currency(pending.amount)} '
                    '${pending.method == 'gcash' ? 'GCash' : 'cash'} payment'
                    '${pending.reference != null ? ' (ref. ${pending.reference})' : ''}.')
              else if (due) ...[
                const SizedBox(height: 12),
                if (owes >= gcashMinimum)
                  FilledButton.icon(
                    key: const Key('pay-dues'),
                    onPressed: () => payRiderDues(context, ref),
                    icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                    label: Text('Pay ${Formatters.currency(owes)} with GCash'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('claim-payment'),
                  onPressed: () => _openClaim(context, ref, owes),
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                  label: const Text('I paid the admin'),
                ),
                if (owes < gcashMinimum)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'GCash needs at least ${Formatters.currency(gcashMinimum)} — pay this to the admin, then tap "I paid the admin".',
                      style: AppTypography.caption.copyWith(fontSize: 11.5),
                    ),
                  ),
              ] else if (owed)
                _note(Icons.info_outline_rounded, AppColors.primary,
                    'The admin sends this to you and marks it sent — your balance then goes back to ${Formatters.currency(0)}.'),
              if (rejected != null)
                _note(Icons.error_outline_rounded, AppColors.danger,
                    "Your ${Formatters.currency(rejected.amount)} payment wasn't confirmed: ${rejected.rejectReason ?? ''}"),
              if (settling.history.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  // its own Material so the tap ripple shows on the card
                  child: Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      key: const Key('settle-history'),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text('Payments with iTULOD (${settling.history.length})',
                          style: AppTypography.bodyBold.copyWith(fontSize: 13, color: AppColors.primary)),
                      children: [
                        for (final s in settling.history)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.label, style: AppTypography.bodyMedium.copyWith(fontSize: 13)),
                                      Text(Formatters.date(s.createdAt), style: AppTypography.caption.copyWith(fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Text('${s.payout ? '+' : '−'}${Formatters.currency(s.amount)}',
                                    style: AppTypography.bodyBold
                                        .copyWith(fontSize: 13, color: s.payout ? const Color(0xFF157A4D) : AppColors.ink)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (b.codUnremitted > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: _head(
              icon: Icons.payments_rounded,
              bg: AppColors.blush,
              fg: AppColors.secondaryDark,
              title: '${Formatters.currency(b.codUnremitted)} COD to hand over',
              body: 'Cash you collected for senders. Open each parcel in History and tap "COD handed over".',
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _openClaim(BuildContext context, WidgetRef ref, double owes) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ClaimSheet(owes: owes),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sent — the admin will confirm your payment.'),
        backgroundColor: AppColors.success,
      ));
    }
    ref.invalidate(riderSettlingProvider);
  }

  Widget _head({required IconData icon, required Color bg, required Color fg, required String title, required String body}) {
    return Row(
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
              Text(title, key: const Key('balance-headline'), style: AppTypography.bodyBold.copyWith(fontSize: 15.5)),
              const SizedBox(height: 2),
              Text(body, style: AppTypography.caption.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _note(IconData icon, Color color, String text) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppTypography.caption.copyWith(fontSize: 12, color: AppColors.ink))),
          ],
        ),
      );
}

/// "I paid the admin": amount (up to what's owed), cash or GCash, reference.
class _ClaimSheet extends ConsumerStatefulWidget {
  final double owes;
  const _ClaimSheet({required this.owes});

  @override
  ConsumerState<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<_ClaimSheet> {
  late final _amount = TextEditingController(text: widget.owes.toStringAsFixed(2));
  final _reference = TextEditingController();
  String _method = 'cash';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount you paid.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(riderRepositoryProvider).claimPayment(amount: amount, method: _method, reference: _reference.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('I paid the admin', style: AppTypography.h3),
          const SizedBox(height: 4),
          Text(
            'You owe ${Formatters.currency(widget.owes)}. The admin checks your payment and confirms it — '
            'then your balance goes back to ${Formatters.currency(0)}.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('claim-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: const InputDecoration(labelText: 'Amount you paid', prefixText: '₱ '),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Cash to the admin')),
              ButtonSegment(value: 'gcash', label: Text('GCash sent')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('claim-reference'),
            controller: _reference,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Reference number (optional)', hintText: 'e.g. the GCash reference no.'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.danger)),
            ),
          FilledButton.icon(
            key: const Key('claim-send'),
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send to the admin'),
          ),
        ],
      ),
    );
  }
}
