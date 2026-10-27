import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../data/promo_repository.dart';

const _kindWord = {
  BookingKind.transport: 'rides',
  BookingKind.food: 'food',
  BookingKind.parcel: 'parcels',
  BookingKind.hauling: 'hauling',
};

/// "Promo" on a booking form: the customer's claimed promos that work for
/// this booking (right service, total big enough), with what each saves, plus
/// "Have a code?" to claim one by typing it. Web twin: js/promos.js
/// renderPromoPicker. The booking screen applies the pick after placing the
/// booking ([PromoRepository.redeem]).
class PromoPicker extends ConsumerWidget {
  final BookingKind kind;
  final double fare;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const PromoPicker({super.key, required this.kind, required this.fare, required this.selected, required this.onChanged});

  /// The discount the current pick gives on [fare] (0 for none).
  static double discountOf(List<MyPromo> promos, String? code, BookingKind kind, double fare) {
    if (code == null) return 0;
    for (final p in promos) {
      if (p.code == code && p.usableOn(kind, fare)) return p.discountFor(fare);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(myPromosProvider).valueOrNull ?? const <MyPromo>[];
    final ready = promos.where((p) => p.isReady && p.worksFor(kind)).toList();
    final usable = ready.where((p) => p.usableOn(kind, fare)).toList();
    final chosen = usable.where((p) => p.code == selected).firstOrNull;
    // a pick that no longer fits (total changed) is dropped
    if (selected != null && chosen == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(null));
    }
    final saving = chosen?.discountFor(fare) ?? 0;
    final tooSmall = ready.where((p) => !usable.contains(p)).toList();
    final note = chosen != null
        ? 'You save ${Formatters.currency(saving)} — new total ${Formatters.currency(fare - saving)}. iTULOD pays the discount.'
        : usable.isNotEmpty
            ? '${usable.length} promo${usable.length == 1 ? '' : 's'} you can use on this booking.'
            : tooSmall.isNotEmpty && fare > 0
                ? 'Your ${tooSmall.length == 1 ? 'promo needs' : 'promos need'} a bigger total '
                    '(min ${Formatters.currency(tooSmall.map((p) => p.minFare).reduce((a, b) => a < b ? a : b))}).'
                : 'No promos for ${_kindWord[kind]} yet — new ones arrive in your notifications.';

    return Container(
      key: const Key('promo-picker'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: chosen != null ? AppColors.success : AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.confirmation_number_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('Promo', style: AppTypography.bodyBold)),
              TextButton(
                key: const Key('promo-have-code'),
                onPressed: () => _claimByCode(context, ref),
                child: const Text('Have a code?'),
              ),
            ],
          ),
          DropdownButtonFormField<String?>(
            key: ValueKey('promo-select-${usable.length}-${chosen?.code}'),
            initialValue: chosen?.code,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('No promo')),
              for (final p in usable)
                DropdownMenuItem<String?>(
                  value: p.code,
                  child: Text('${p.title} — save ${Formatters.currency(p.discountFor(fare))}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: usable.isEmpty ? null : onChanged,
          ),
          const SizedBox(height: 6),
          Text(note,
              key: const Key('promo-note'),
              style: AppTypography.caption.copyWith(fontSize: 12, color: chosen != null ? const Color(0xFF157A4D) : null)),
        ],
      ),
    );
  }

  Future<void> _claimByCode(BuildContext context, WidgetRef ref) async {
    final code = await showDialog<String>(context: context, builder: (_) => const _CodeDialog());
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final claimed = await ref.read(promoRepositoryProvider).claim(code: code);
      ref.invalidate(myPromosProvider);
      await ref.read(myPromosProvider.future);
      onChanged(claimed);
      messenger.showSnackBar(SnackBar(content: Text('Promo $claimed claimed.'), backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.danger));
    }
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Have a promo code?'),
        content: TextField(
          key: const Key('promo-code-field'),
          controller: _c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. WELCOME10'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('promo-code-claim'), onPressed: () => Navigator.pop(context, _c.text), child: const Text('Claim')),
        ],
      );
}

/// After a booking is placed: applies the picked promo and says so. Returns
/// the discount (0 when none was picked or it was refused).
Future<double> applyPickedPromo(WidgetRef ref, ScaffoldMessengerState messenger,
    {required String? code, required BookingKind kind, required String bookingId}) async {
  if (code == null) return 0;
  try {
    final saved = await ref.read(promoRepositoryProvider).redeem(code: code, kind: kind, bookingId: bookingId);
    messenger.showSnackBar(SnackBar(content: Text('Promo applied — you saved ${Formatters.currency(saved)}!'), backgroundColor: AppColors.success));
    return saved;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text("Booked, but the promo wasn't applied: ${e.toString().replaceFirst('Exception: ', '')}"),
      backgroundColor: AppColors.warning,
    ));
    return 0;
  } finally {
    ref.invalidate(myPromosProvider);
  }
}
