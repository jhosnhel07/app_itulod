import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../shared/models/booking_models.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/chat_model.dart';
import '../../data/chat_repository.dart';
import '../providers/chat_provider.dart';
import 'messages_screen.dart' show kindOf;

/// One booking's chat (web: js/messages.js): the other person and route on
/// top with Call while the trip is on, quick replies, photos (private
/// chat-photos bucket, signed links), "Seen" under your last message. The
/// chat is marked read while it's open. RLS only accepts messages while the
/// booking is accepted/ongoing; after that it stays readable without the
/// composer.
class ChatScreen extends ConsumerStatefulWidget {
  final BookingKind kind;
  final String bookingId;
  final bool canSend;
  /// From the Messages list; otherwise looked up there by booking id.
  final Conversation? conversation;

  const ChatScreen({
    super.key,
    required this.kind,
    required this.bookingId,
    this.canSend = true,
    this.conversation,
  });

  /// Opens the chat for [booking], read-only once it has left accepted/ongoing.
  static Route<void> route(BookingBase booking) => MaterialPageRoute(
        builder: (_) => ChatScreen(
          kind: booking.kind,
          bookingId: booking.id,
          canSend: booking.status == 'accepted' || booking.status == 'ongoing',
        ),
      );

  static Route<void> forConversation(Conversation c) => MaterialPageRoute(
        builder: (_) => ChatScreen(
          kind: kindOf(c.bookingType),
          bookingId: c.bookingId,
          canSend: c.canSend,
          conversation: c,
        ),
      );

  /// `messages/<type>/<booking id>` — a chat notification's link (sql/046).
  static Route<void>? forLink(String? link) {
    final parts = (link ?? '').split('/');
    if (parts.length != 3 || parts[0] != 'messages' || parts[2].isEmpty) return null;
    if (!BookingKind.values.any((k) => k.name == parts[1])) return null;
    return MaterialPageRoute(
      builder: (_) => ChatScreen(kind: kindOf(parts[1]), bookingId: parts[2], canSend: false),
    );
  }

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

const _quickReplies = {
  'rider': ['On my way', "I'm here", 'Running a bit late, sorry', 'Where exactly are you?', 'Please wait 5 minutes'],
  'customer': ["I'm at the pickup point", 'Please call me', "I'm on my way out", 'Take your time, ride safe', 'Thank you!'],
};

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _photoUrls = {};
  final Set<String> _signing = {};
  String? _lastReadMessageId;
  bool _sending = false;

  String get _type => widget.kind.name;

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Conversation? get _conversation {
    final list = ref.watch(conversationsProvider).valueOrNull;
    final live = list?.where((c) => c.bookingId == widget.bookingId && c.bookingType == _type).firstOrNull;
    return live ?? widget.conversation;
  }

  void _markRead() {
    ref.read(chatRepositoryProvider).markRead(_type, widget.bookingId).catchError((Object e, StackTrace s) {
      AppLog.warn('ChatScreen: mark read failed', e, s);
    });
  }

  void _signMissing(List<ChatMessage> messages) {
    final paths = messages
        .map((m) => m.imagePath)
        .whereType<String>()
        .where((p) => !_photoUrls.containsKey(p) && !_signing.contains(p))
        .toList();
    if (paths.isEmpty) return;
    _signing.addAll(paths);
    ref.read(chatRepositoryProvider).signPhotos(paths).then((urls) {
      if (mounted) setState(() => _photoUrls.addAll(urls));
    }).catchError((Object e, StackTrace s) {
      AppLog.warn('ChatScreen: photo links failed', e, s);
    });
  }

  Future<void> _send({String body = '', File? photo}) async {
    final profile = ref.read(authNotifierProvider).profile;
    if (profile == null || _sending) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      if (photo != null) {
        await repo.sendPhoto(bookingType: _type, bookingId: widget.bookingId, senderId: profile.id, file: photo);
      } else {
        await repo.sendMessage(bookingType: _type, bookingId: widget.bookingId, senderId: profile.id, body: body);
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        final closed = e.toString().contains('row-level security');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(closed ? 'This chat is closed — the booking is no longer active.' : "Couldn't send: $e"),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _sendText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _send(body: text);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (picked == null) return;
    await _send(photo: File(picked.path));
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (_type, widget.bookingId);
    final messagesAsync = ref.watch(chatMessagesProvider(key));
    final me = ref.watch(authNotifierProvider).profile?.id;
    final c = _conversation;
    final canSend = c?.canSend ?? widget.canSend;
    final otherRead = c == null
        ? null
        : ref.watch(otherReadProvider((_type, widget.bookingId, c.otherId))).valueOrNull ?? c.otherReadAt;

    // A new message from the other side while this is open → mark it read.
    ref.listen(chatMessagesProvider(key), (_, next) {
      final list = next.valueOrNull;
      if (list == null || list.isEmpty) return;
      final last = list.last;
      if (last.senderId != me && last.id != _lastReadMessageId) {
        _lastReadMessageId = last.id;
        _markRead();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: c == null
            ? const Text('Chat')
            : Row(
                children: [
                  AvatarWidget(url: c.otherAvatar, name: c.otherName, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.otherName, style: AppTypography.bodyBold.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis),
                        Text(
                          [if (c.vehicle != null) c.vehicle!, '${kindOf(c.bookingType).label} · ${c.route}'].join(' · '),
                          style: AppTypography.caption.copyWith(fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (c?.otherPhone != null && c!.otherPhone!.isNotEmpty)
            IconButton(
              tooltip: 'Call ${c.otherName}',
              icon: const Icon(Icons.call_rounded, color: AppColors.primary),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.otherPhone!.replaceAll(RegExp(r'[^\d+]'), ''))),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                _signMissing(messages);
                if (messages.isEmpty) {
                  return Center(
                    child: EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No messages yet',
                      message: canSend ? 'Say hello — or tap a quick reply below.' : null,
                    ),
                  );
                }
                final lastMine = messages.lastWhere((m) => m.senderId == me, orElse: () => messages.first);
                final seen = lastMine.senderId == me && otherRead != null && !otherRead.isBefore(lastMine.createdAt);
                final reversed = messages.reversed.toList();
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: reversed.length,
                  itemBuilder: (context, index) {
                    final m = reversed[index];
                    final older = index + 1 < reversed.length ? reversed[index + 1] : null;
                    final newDay = older == null || !_sameDay(older.createdAt, m.createdAt);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (newDay) _DayDivider(m.createdAt),
                        _Bubble(message: m, mine: m.senderId == me, photoUrl: m.imagePath == null ? null : _photoUrls[m.imagePath]),
                        if (seen && m.id == lastMine.id)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Icon(Icons.done_all_rounded, size: 14, color: AppColors.primary),
                                const SizedBox(width: 3),
                                Text('Seen', style: AppTypography.caption.copyWith(fontSize: 11)),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
              loading: () => const SkeletonList(count: 3),
              error: (e, st) => Center(child: Text('Could not load messages.', style: AppTypography.body)),
            ),
          ),
          if (!canSend)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.neutral500),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('This booking has ended — the chat is read-only now.',
                          style: AppTypography.caption, textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.neutral200)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final q in _quickReplies[c?.iAm ?? 'customer']!)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(q, style: AppTypography.caption.copyWith(
                                    color: AppColors.primaryDark, fontWeight: FontWeight.w600, fontSize: 12)),
                                backgroundColor: AppColors.primary50,
                                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
                                shape: const StadiumBorder(),
                                visualDensity: VisualDensity.compact,
                                onPressed: _sending ? null : () => _send(body: q),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Send a photo',
                          onPressed: _sending ? null : _pickPhoto,
                          icon: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: AppTypography.caption,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              fillColor: AppColors.neutral100,
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            maxLength: 1000, // booking_messages.body check constraint
                            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendText(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _sending ? null : _sendText,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: _sending
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _DayDivider extends StatelessWidget {
  final DateTime at;
  const _DayDivider(this.at);

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = at.toLocal();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: Text('${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}',
            style: AppTypography.caption.copyWith(fontSize: 11)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final String? photoUrl;
  const _Bubble({required this.message, required this.mine, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : AppColors.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : AppColors.surface,
            border: mine ? null : Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: mine ? const Radius.circular(4) : null,
              bottomLeft: mine ? null : const Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.imagePath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: photoUrl == null
                        ? Container(
                            width: 200,
                            height: 140,
                            color: AppColors.neutral100,
                            alignment: Alignment.center,
                            child: Icon(Icons.image_outlined, color: AppColors.neutral500),
                          )
                        : GestureDetector(
                            onTap: () => launchUrl(Uri.parse(photoUrl!), mode: LaunchMode.externalApplication),
                            child: Image.network(
                              photoUrl!,
                              width: 220,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text('Photo unavailable', style: TextStyle(color: fg)),
                            ),
                          ),
                  ),
                ),
              if (message.body.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(message.body, style: AppTypography.body.copyWith(color: fg, fontSize: 14.5)),
                ),
              const SizedBox(height: 2),
              Text(_clock(message.createdAt), style: TextStyle(color: fg.withValues(alpha: 0.72), fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(DateTime at) {
    final d = at.toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}
