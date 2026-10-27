import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/rider_repository.dart';

// Rider → Earnings: what the rider earned split by how the customer paid, and
// every paid trip (web: rider.js renderPaySplit / renderPayRecords).

class _Method {
  final String key, label, hint;
  final IconData icon;
  final Color Function() color;
  const _Method(this.key, this.label, this.icon, this.hint, this.color);
}

final _methods = <_Method>[
  _Method('cash', 'Cash', Icons.payments_rounded, 'Collected by you', () => AppColors.success),
  _Method('gcash', 'GCash', Icons.phone_iphone_rounded, 'Paid out by iTULOD', () => AppColors.primary),
  _Method('wallet', 'Wallet', Icons.account_balance_wallet_rounded, 'Paid out by iTULOD', () => AppColors.secondaryDark),
];
_Method? _methodOf(String key) {
  for (final m in _methods) {
    if (m.key == key) return m;
  }
  return null;
}

const _kindLabel = {'transport': 'Ride', 'food': 'Food', 'parcel': 'Parcel', 'hauling': 'Hauling'};

class _Pills extends StatelessWidget {
  final List<(String, String)> options; // (value, label)
  final String selected;
  final ValueChanged<String> onChanged;
  const _Pills({required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(o.$2),
                selected: o.$1 == selected,
                onSelected: (_) => onChanged(o.$1),
                showCheckmark: false,
                selectedColor: AppColors.primary,
                labelStyle: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: o.$1 == selected ? Colors.white : AppColors.neutral700,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const _Section({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.bodyBold),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTypography.caption),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Cash / GCash / Wallet totals for a period, with trip counts and shares.
class PaymentSplitCard extends StatefulWidget {
  final List<EarningRecord> records;
  const PaymentSplitCard({super.key, required this.records});

  @override
  State<PaymentSplitCard> createState() => _PaymentSplitCardState();
}

class _PaymentSplitCardState extends State<PaymentSplitCard> {
  String _range = 'month';

  DateTime? _from() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case 'day':
        return day;
      case 'week':
        return day.subtract(Duration(days: now.weekday % 7));
      case 'month':
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _from();
    final inRange = widget.records.where((r) => from == null || !r.createdAt.isBefore(from)).toList();
    final total = inRange.fold<double>(0, (a, r) => a + r.payout);
    return _Section(
      title: 'Earnings by payment method',
      subtitle: 'What you earned, split by how the customer paid',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pills(
            options: const [('day', 'Today'), ('week', 'This week'), ('month', 'This month'), ('all', 'All time')],
            selected: _range,
            onChanged: (v) => setState(() => _range = v),
          ),
          const SizedBox(height: 12),
          for (final m in _methods) _splitRow(m, inRange, total),
          const SizedBox(height: 4),
          Text(
            'Cash: you collected it and owe iTULOD the commission. GCash and Wallet: iTULOD received it and pays your share out to you.',
            style: AppTypography.caption.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _splitRow(_Method m, List<EarningRecord> inRange, double total) {
    final rows = inRange.where((r) => r.method == m.key).toList();
    final earned = rows.fold<double>(0, (a, r) => a + r.payout);
    final share = total > 0 ? earned / total : 0.0;
    final color = m.color();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neutral50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(m.icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.label, style: AppTypography.bodyMedium),
                    Text(m.hint, style: AppTypography.caption.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Formatters.currency(earned), style: AppTypography.bodyBold),
                  Text('${rows.length} trip${rows.length == 1 ? '' : 's'} · ${(share * 100).round()}%',
                      style: AppTypography.caption.copyWith(fontSize: 11.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              backgroundColor: AppColors.neutral200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every paid trip, newest first, filterable by payment method.
class EarningRecordsCard extends StatefulWidget {
  final List<EarningRecord> records;
  const EarningRecordsCard({super.key, required this.records});

  @override
  State<EarningRecordsCard> createState() => _EarningRecordsCardState();
}

class _EarningRecordsCardState extends State<EarningRecordsCard> {
  String _filter = 'all';
  /// 20 at a time; "Show more" adds the next 20 (web: showMorePayRecords).
  static const _page = 20;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final all = widget.records.where((r) => _filter == 'all' || r.method == _filter).toList();
    final shown = all.take(_shown).toList();
    return _Section(
      title: 'Earnings records',
      subtitle: 'Every paid trip, newest first — what the customer paid, the commission and your share',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pills(
            options: const [('all', 'All'), ('cash', 'Cash'), ('gcash', 'GCash'), ('wallet', 'Wallet')],
            selected: _filter,
            onChanged: (v) => setState(() {
              _filter = v;
              _shown = _page;
            }),
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  _filter == 'all' ? 'Completed trips show up here with what you earned.' : 'No trips paid this way yet.',
                  style: AppTypography.captionDark,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (var i = 0; i < shown.length; i++) _recordRow(shown[i], last: i == shown.length - 1),
          if (all.length > shown.length)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.cardBorder))),
              child: Row(
                children: [
                  Expanded(child: Text('Showing ${shown.length} of ${all.length}', style: AppTypography.caption)),
                  OutlinedButton.icon(
                    key: const Key('records-more'),
                    onPressed: () => setState(() => _shown += _page),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: const Text('Show more'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recordRow(EarningRecord r, {required bool last}) {
    final m = _methodOf(r.method);
    final color = m?.color() ?? AppColors.neutral500;
    final what = r.isFee ? 'Fee from customer' : (_kindLabel[r.bookingType] ?? 'Trip');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(m?.icon ?? Icons.receipt_long_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(what, style: AppTypography.bodyMedium),
                Text(Formatters.date(r.createdAt),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(fontSize: 11.5)),
                Text(m?.label ?? r.method, style: AppTypography.caption.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+${Formatters.currency(r.payout)}',
                  style: AppTypography.bodyBold.copyWith(color: AppColors.success)),
              Text('Paid ${Formatters.currency(r.amount)}', style: AppTypography.caption.copyWith(fontSize: 11)),
              if (r.promo > 0)
                Text('+${Formatters.currency(r.promo)} promo by iTULOD', style: AppTypography.caption.copyWith(fontSize: 11)),
              if (r.commission > 0)
                Text('−${Formatters.currency(r.commission)} commission', style: AppTypography.caption.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
