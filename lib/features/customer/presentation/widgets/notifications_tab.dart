import 'package:flutter/material.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import '../../../../shared/widgets/empty_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/customer_repository.dart';
import 'customer_bookings_tab.dart'
    show authProfileIdProvider, customerHistoryProvider;

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final userId = ref.watch(authProfileIdProvider);
  if (userId.isEmpty) return [];
  return repo.fetchNotifications(userId);
});

final unreadNotificationsProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final userId = ref.watch(authProfileIdProvider);
  if (userId.isEmpty) return 0;
  return repo.unreadNotificationsCount(userId);
});

class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadNotificationsProvider);
      },
      child: notificationsAsync.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Could not load notifications.\n$e',
                  textAlign: TextAlign.center, style: AppTypography.body)),
            ),
          ],
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'No notifications yet',
                        message: "Updates about your bookings will show up here.",
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final userId = ref.read(authProfileIdProvider);
                      await ref
                          .read(customerRepositoryProvider)
                          .markNotificationsRead(userId);
                      ref.invalidate(notificationsProvider);
                      ref.invalidate(unreadNotificationsProvider);
                      ref.invalidate(customerHistoryProvider);
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Mark all read'),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final isUnread = n['is_read'] == false;
                    final created = DateTime.tryParse(n['created_at']?.toString() ?? '');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: isUnread ? AppColors.primary50 : Colors.white,
                      child: ListTile(
                        leading: Icon(
                          isUnread
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          color: isUnread ? AppColors.primary : AppColors.neutral400,
                        ),
                        title: Text(n['title']?.toString() ?? 'Notification',
                            style: AppTypography.bodyBold.copyWith(fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n['message']?.toString() ?? '',
                                style: AppTypography.captionDark),
                            const SizedBox(height: 2),
                            Text(Formatters.date(created), style: AppTypography.caption),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
