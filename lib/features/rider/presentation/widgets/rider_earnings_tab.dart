import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';
import 'rider_balance_card.dart';
import 'rider_earnings_breakdown.dart';

final riderEarningsProvider = FutureProvider.autoDispose<RiderEarnings>((ref) async {
  final repo = ref.watch(riderRepositoryProvider);
  final profile = ref.watch(authNotifierProvider).profile;
  if (profile == null) return const RiderEarnings();
  return repo.fetchEarnings(profile.id);
});

class RiderEarningsTab extends ConsumerWidget {
  const RiderEarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(riderEarningsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(riderEarningsProvider);
        ref.invalidate(riderBalanceProvider);
      },
      child: earningsAsync.when(
        loading: () => const SkeletonList(count: 3),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load earnings.\n$e',
                  textAlign: TextAlign.center, style: AppTypography.body),
            ),
          ],
        ),
        data: (earnings) {
          final labels = _last7DayLabels();
          // Your share of paid trips, with how many (web: loadEarnings).
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day);
          final periods = [
            ('Today', Icons.today_rounded, day),
            ('This week', Icons.date_range_rounded, day.subtract(Duration(days: now.weekday % 7))),
            ('This month', Icons.calendar_month_rounded, DateTime(now.year, now.month, 1)),
            ('All time', Icons.savings_rounded, null),
          ];
          final weekTotal = earnings.last7Days.fold<double>(0, (a, v) => a + v);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              // 1. What you earned
              GridView.count(
                key: const Key('earn-summary'),
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  for (final (label, icon, from) in periods)
                    () {
                      final rows = earnings.records.where((r) => from == null || !r.createdAt.isBefore(from)).toList();
                      return _StatCard(
                        label: label,
                        value: rows.fold<double>(0, (a, r) => a + r.payout),
                        trips: rows.length,
                        icon: icon,
                      );
                    }(),
                ],
              ),
              const SizedBox(height: 20),
              // 2. Balance with iTULOD
              _heading(Icons.balance_rounded, 'Balance with iTULOD'),
              const RiderBalanceCard(),
              // 3. Last 7 days
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last 7 days', style: AppTypography.bodyBold),
                      const SizedBox(height: 2),
                      Text('${Formatters.currency(weekTotal)} in the last 7 days · your share, day by day',
                          key: const Key('earn-week-total'), style: AppTypography.caption),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: earnings.last7Days.every((v) => v == 0)
                            ? Center(
                                child: Text('No earnings in the past week.',
                                    style: AppTypography.captionDark))
                            : BarChart(
                                BarChartData(
                                  gridData: const FlGridData(show: false),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false)),
                                    leftTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) =>
                                            _chartLabel(labels[value.toInt().clamp(0, 6)]),
                                      ),
                                    ),
                                  ),
                                  barGroups: List.generate(7, (i) {
                                    return BarChartGroupData(
                                      x: i,
                                      barRods: [
                                        BarChartRodData(
                                          toY: earnings.last7Days[i],
                                          // today in green, like the web
                                          color: i == 6 ? AppColors.success : AppColors.primary,
                                          width: 18,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 4. By payment method, 5. every paid trip
              PaymentSplitCard(records: earnings.records),
              const SizedBox(height: 16),
              EarningRecordsCard(records: earnings.records),
            ],
          );
        },
      ),
    );
  }

  List<String> _last7DayLabels() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      if (i == 6) return 'Today';
      final d = now.subtract(Duration(days: 6 - i));
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
    });
  }

  Widget _heading(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(text, style: AppTypography.bodyBold.copyWith(fontSize: 15.5)),
          ],
        ),
      );

  Widget _chartLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label,
          style: AppTypography.caption.copyWith(fontSize: 11)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final int trips;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.trips, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    style: AppTypography.captionDark,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.currency(value),
              style: AppTypography.h2.copyWith(color: AppColors.success),
            ),
          ),
          Text('$trips trip${trips == 1 ? '' : 's'}', style: AppTypography.caption.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}
