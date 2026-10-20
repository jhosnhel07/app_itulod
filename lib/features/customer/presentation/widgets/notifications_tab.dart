import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import '../../../../shared/widgets/empty_state.dart';
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

/// Notifications stay unread until the customer opens them; tapping one
/// marks just that one read and shows it in full (web: openNotification).
class NotificationsTab extends ConsumerWidget {
  /// Switches the dashboard to the Bookings tab — offered in the details of
  /// a booking update.
  final VoidCallback? onOpenBookings;

  const NotificationsTab({super.key, this.onOpenBookings});

  static void _refresh(WidgetRef ref) {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
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
          final hasUnread = items.any((n) => n['is_read'] == false);
          return Column(
            children: [
              if (hasUnread)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final userId = ref.read(authProfileIdProvider);
                        await ref.read(customerRepositoryProvider).markNotificationsRead(userId);
                        _refresh(ref);
                        ref.invalidate(customerHistoryProvider);
                      },
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Mark all as read'),
                    ),
                  ),
                ),
              // One card with divided rows — the same layout as the web's
              // Notifications tab (css .notif-item), in both light and dark.
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, hasUnread ? 4 : 16, 20, 20),
                  children: [
                    Container(
                      clipBehavior: Clip.antiAlias,
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
                            _NotificationRow(items[i], onOpenBookings: onOpenBookings),
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

/// Booking updates get a shortcut to the Bookings tab in their details.
final _bookingRe = RegExp(
  r'\b(ride|delivery|hauling|booking|rider|trip|parcel|food|payment|refund|fee|cod|tip|no-show|expired|cancell?ed)\b',
  caseSensitive: false,
);

IconData _iconFor(Map<String, dynamic> n) {
  final t = '${n['title']} ${n['message']}'.toLowerCase();
  if (RegExp(r'refund|wallet|payment|fee|tip|bonus').hasMatch(t)) return Icons.account_balance_wallet_rounded;
  if (RegExp(r'cancel|expired|no-show|not approved').hasMatch(t)) return Icons.error_outline_rounded;
  if (RegExp(r'completed|approved|accepted').hasMatch(t)) return Icons.check_circle_rounded;
  return Icons.notifications_rounded;
}

/// One notification: icon (blue tint when unread), title, a two-line preview
/// and time, and a status dot — mirrors the web's .notif-item. Tap to open.
class _NotificationRow extends ConsumerWidget {
  final Map<String, dynamic> n;
  final VoidCallback? onOpenBookings;
  const _NotificationRow(this.n, {this.onOpenBookings});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final unread = n['is_read'] == false;
    final id = n['id']?.toString();
    // Mark just this one read, in the background while the details show.
    if (unread && id != null) {
      ref.read(customerRepositoryProvider).markNotificationRead(id).then((_) {
        NotificationsTab._refresh(ref);
      }).catchError((Object _) {});
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NotificationDetails(n: n, onOpenBookings: onOpenBookings),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = n['is_read'] == false;
    final created = DateTime.tryParse(n['created_at']?.toString() ?? '');
    final title = n['title']?.toString() ?? 'Notification';
    return Semantics(
      button: true,
      label: unread ? '$title, unread' : title,
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Padding(
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
                child: Icon(_iconFor(n), size: 19, color: unread ? AppColors.primary : AppColors.neutral500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyBold.copyWith(
                        fontSize: 14,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        color: unread ? null : AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n['message']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionDark.copyWith(fontSize: 13, height: 1.45),
                    ),
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
        ),
      ),
    );
  }
}

/// The whole notification — the web's notification modal.
class _NotificationDetails extends StatelessWidget {
  final Map<String, dynamic> n;
  final VoidCallback? onOpenBookings;
  const _NotificationDetails({required this.n, this.onOpenBookings});

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(n['created_at']?.toString() ?? '')?.toLocal();
    final title = n['title']?.toString() ?? 'Notification';
    final message = n['message']?.toString() ?? '';
    final bookingRelated = onOpenBookings != null && _bookingRe.hasMatch('$title $message');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.neutral200, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.12)),
                child: Icon(_iconFor(n), size: 26, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: AppTypography.h3),
            if (created != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: AppColors.iconMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      DateFormat("EEEE, MMMM d, y 'at' h:mm a").format(created),
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(message, style: AppTypography.body.copyWith(height: 1.55)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (bookingRelated) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onOpenBookings!();
                },
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text('View my bookings'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
