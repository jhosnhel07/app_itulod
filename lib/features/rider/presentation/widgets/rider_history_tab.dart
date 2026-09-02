import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/screens/booking_details_sheet.dart';
import '../../../../shared/widgets/booking_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/rider_repository.dart';

final riderHistoryProvider = FutureProvider.autoDispose
    .family<List<BookingBase>, BookingKind>((ref, kind) async {
  final repo = ref.watch(riderRepositoryProvider);
  final profile = ref.watch(authNotifierProvider).profile;
  if (profile == null) return [];
  return repo.fetchHistory(kind, profile.id);
});

class RiderHistoryTab extends ConsumerStatefulWidget {
  const RiderHistoryTab({super.key});

  @override
  ConsumerState<RiderHistoryTab> createState() => _RiderHistoryTabState();
}

class _RiderHistoryTabState extends ConsumerState<RiderHistoryTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.neutral500,
            indicatorColor: AppColors.primary,
            labelStyle: AppTypography.bodyBold.copyWith(fontSize: 14),
            tabs: const [
              Tab(text: 'Rides'),
              Tab(text: 'Food'),
              Tab(text: 'Parcels'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: BookingKind.values.map((kind) => _RiderHistoryList(kind: kind)).toList(),
          ),
        ),
      ],
    );
  }
}

class _RiderHistoryList extends ConsumerWidget {
  final BookingKind kind;

  const _RiderHistoryList({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(riderHistoryProvider(kind));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load history.\n$e',
              textAlign: TextAlign.center, style: AppTypography.body),
        ),
      ),
      data: (bookings) {
        if (bookings.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(riderHistoryProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded, size: 56, color: AppColors.neutral300),
                      const SizedBox(height: 12),
                      Text('No completed ${kind.label.toLowerCase()} jobs yet',
                          style: AppTypography.captionDark),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(riderHistoryProvider),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: bookings.length,
            itemBuilder: (_, i) => BookingCard(
              booking: bookings[i],
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => BookingDetailsSheet(booking: bookings[i]),
              ),
            ),
          ),
        );
      },
    );
  }
}
