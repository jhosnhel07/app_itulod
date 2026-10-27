import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/booking_models.dart';
import '../../data/promo_repository.dart';

const _state = {
  'ready': ('Ready to use', Color(0xFF157A4D)),
  'unclaimed': ('New — claim it', AppColors.warning),
  'used': ('Used', Color(0xFF6B7280)),
  'expired': ('Expired', AppColors.danger),
  'ended': ('Ended', AppColors.danger),
  'full': ('Fully used', AppColors.danger),
};

/// My promos (web: the My promos tab, js/promos.js): claim one by code or
/// from the list, see which are ready, used or expired. [focusId] highlights
/// the promo a notification pointed to.
class MyPromosScreen extends ConsumerStatefulWidget {
  final String? focusId;
  const MyPromosScreen({super.key, this.focusId});

  static Route<void> route({String? focusId}) =>
      MaterialPageRoute(builder: (_) => MyPromosScreen(focusId: focusId));

  /// A promo notification's link (`promo/<id>`, web sql/053) → My promos on it.
  static Route<void>? forLink(String? link) {
    final m = RegExp(r'^promo/([\w-]+)$').firstMatch(link ?? '');
    return m == null ? null : route(focusId: m.group(1));
  }

  @override
  ConsumerState<MyPromosScreen> createState() => _MyPromosScreenState();
}

class _MyPromosScreenState extends ConsumerState<MyPromosScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _claim({String? id, String? code}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final claimed = await ref.read(promoRepositoryProvider).claim(id: id, code: code);
      _code.clear();
      ref.invalidate(myPromosProvider);
      messenger.showSnackBar(SnackBar(content: Text('Promo $claimed claimed — pick it when you book.'), backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final promos = ref.watch(myPromosProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My promos')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myPromosProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Claim a promo, then pick it when you book. iTULOD pays the discount — your rider still earns the full fare.',
                style: AppTypography.caption),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('my-promos-code'),
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'Have a code?', isDense: true),
                    onSubmitted: (v) => _claim(code: v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('my-promos-claim'),
                  onPressed: _busy ? null : () => _claim(code: _code.text),
                  child: const Text('Claim'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...promos.when(
              loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [Text('Could not load your promos.\n$e', style: AppTypography.caption)],
              data: (list) => list.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(Icons.confirmation_number_outlined, size: 48, color: AppColors.neutral300),
                            const SizedBox(height: 10),
                            Text('No promos yet', style: AppTypography.bodyBold),
                            const SizedBox(height: 4),
                            Text('New promos arrive in your notifications.', style: AppTypography.caption, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ]
                  : [for (final p in list) _card(p)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(MyPromo p) {
    final (label, color) = _state[p.status] ?? (p.status, AppColors.neutral500);
    final faded = !(p.status == 'ready' || p.status == 'unclaimed');
    final focused = p.id == widget.focusId;
    final used = p.status == 'used' && p.usedAt != null
        ? ' on ${BookingKind.values.firstWhere((k) => k.name == p.usedBookingType, orElse: () => BookingKind.transport).label} · ${Formatters.date(p.usedAt!)}'
        : '';
    return Container(
      key: Key('promo-${p.code}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: focused ? AppColors.primary : AppColors.cardBorder, width: focused ? 2 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: faded ? null : AppColors.primaryGradient,
              color: faded ? AppColors.neutral300 : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Text(p.badge, style: AppTypography.bodyBold.copyWith(color: Colors.white, fontSize: 17)),
                ),
                Text('off', style: AppTypography.caption.copyWith(color: Colors.white70, fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title, style: AppTypography.bodyBold),
                const SizedBox(height: 2),
                Text(p.summary, style: AppTypography.caption.copyWith(fontSize: 12)),
                const SizedBox(height: 4),
                Text(p.code, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 6),
                Text('$label$used', key: Key('promo-state-${p.code}'), style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (p.status == 'unclaimed')
            FilledButton(
              key: Key('promo-claim-${p.code}'),
              onPressed: _busy ? null : () => _claim(id: p.id),
              child: const Text('Claim'),
            ),
        ],
      ),
    );
  }
}
