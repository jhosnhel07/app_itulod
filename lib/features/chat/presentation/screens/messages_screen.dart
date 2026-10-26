import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import '../../data/chat_model.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';

/// Messages (web: js/messages.js): one conversation per booking that has a
/// rider, newest first, with unread counts. Active = the trip is still on
/// (you can type); Past = finished, read-only. The customer has it as a
/// bottom-bar tab; the rider opens [MessagesScreen] from the top bar.
class MessagesView extends ConsumerStatefulWidget {
  const MessagesView({super.key});

  @override
  ConsumerState<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends ConsumerState<MessagesView> {
  bool _past = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(conversationsProvider);
    final isRider = async.valueOrNull?.any((c) => c.iAm == 'rider') ?? false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Active')),
              ButtonSegment(value: true, label: Text('Past')),
            ],
            selected: {_past},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _past = s.first),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(conversationsProvider),
            child: async.when(
              loading: () => const SkeletonList(count: 4),
              error: (e, _) => ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load your messages.', textAlign: TextAlign.center, style: AppTypography.body),
                ),
              ]),
              data: (all) {
                final list = all.where((c) => c.canSend != _past).toList();
                if (list.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 40),
                      EmptyState(
                        icon: _past ? Icons.archive_outlined : Icons.forum_outlined,
                        title: _past ? 'No past chats' : 'No active chats',
                        message: _past
                            ? 'Finished trips keep their messages here, read-only.'
                            : isRider
                                ? 'Accept a booking to message the customer here.'
                                : 'When a rider takes your booking, you can message each other here.',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 120),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) => _ConversationTile(list[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The rider's Messages, opened from the top-bar chat icon.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Messages')),
      body: const MessagesView(),
    );
  }
}

String messageTime(DateTime? at) {
  if (at == null) return '';
  final d = at.toLocal(), now = DateTime.now();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return time;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}';
}

BookingKind kindOf(String type) =>
    BookingKind.values.firstWhere((k) => k.name == type, orElse: () => BookingKind.transport);

class _ConversationTile extends StatelessWidget {
  final Conversation c;
  const _ConversationTile(this.c);

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(c.bookingType);
    final unread = c.unread > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(ChatScreen.forConversation(c)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              AvatarWidget(url: c.otherAvatar, name: c.otherName, radius: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.otherName,
                              style: AppTypography.bodyBold.copyWith(fontSize: 14.5),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(messageTime(c.lastAt ?? c.sortAt), style: AppTypography.caption.copyWith(fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        FaIcon(AppIcons.forKind(kind), size: 11, color: AppColors.primary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text('${kind.label} · ${c.route}',
                              style: AppTypography.caption.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionDark.copyWith(
                        fontSize: 13,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
                  child: Text(c.unread > 99 ? '99+' : '${c.unread}',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
