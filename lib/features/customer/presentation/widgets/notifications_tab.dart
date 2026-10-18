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
              // One card with divided rows — the same layout as the web's
              // Notifications tab (css .notif-item), in both light and dark.
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: AppColors.divider, indent: 16, endIndent: 16),
                            _NotificationRow(items[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One notification: round bell (blue tint when unread), title, message and
/// time, and a status dot on the right — mirrors the web's .notif-item.
class _NotificationRow extends StatelessWidget {
  final Map<String, dynamic> n;
  const _NotificationRow(this.n);

  @override
  Widget build(BuildContext context) {
    final unread = n['is_read'] == false;
    final created = DateTime.tryParse(n['created_at']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unread ? AppColors.primary.withValues(alpha: 0.12) : AppColors.neutral100,
            ),
            child: Icon(
              unread ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
              size: 19,
              color: unread ? AppColors.primary : AppColors.neutral500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n['title']?.toString() ?? 'Notification',
                  style: AppTypography.bodyBold.copyWith(
                    fontSize: 14,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(n['message']?.toString() ?? '',
                    style: AppTypography.captionDark.copyWith(fontSize: 13, height: 1.45)),
                const SizedBox(height: 4),
                Text(Formatters.date(created), style: AppTypography.caption.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unread ? AppColors.primary : AppColors.cardBorder,
            ),
          ),
        ],
      ),
    );
  }
}
