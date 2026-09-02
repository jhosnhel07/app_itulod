import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';

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
      onRefresh: () async => ref.invalidate(riderEarningsProvider),
      child: earningsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Today',
                      value: earnings.today,
                      icon: Icons.today_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'This week',
                      value: earnings.week,
                      icon: Icons.date_range_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'This month',
                      value: earnings.month,
                      icon: Icons.calendar_month_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 18),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text('Rating',
                                    style: AppTypography.captionDark,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            earnings.averageRating > 0
                                ? earnings.averageRating.toStringAsFixed(1)
                                : '—',
                            style:
                                AppTypography.h2.copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last 7 days', style: AppTypography.bodyBold),
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
                                          color: AppColors.primary,
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
            ],
          );
        },
      ),
    );
  }

  List<String> _last7DayLabels() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];
    });
  }

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
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    style: AppTypography.captionDark,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '₱${value.toStringAsFixed(2)}',
            style: AppTypography.h2.copyWith(color: AppColors.success),
          ),
        ],
      ),
    );
  }
}
