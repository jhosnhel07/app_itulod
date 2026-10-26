import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/chat_model.dart';
import '../../data/chat_repository.dart';

/// Keyed by `(bookingType, bookingId)`.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, (String, String)>((ref, key) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchMessages(key.$1, key.$2);
});

/// The Messages list (web sql/046 my_conversations). Reloads itself on any
/// new message or read receipt, so unread counts stay live.
final conversationsProvider = StreamProvider.autoDispose<List<Conversation>>((ref) {
  final userId = ref.watch(authNotifierProvider.select((s) => s.profile?.id));
  if (userId == null) return Stream.value(const <Conversation>[]);
  final repo = ref.watch(chatRepositoryProvider);
  final controller = StreamController<List<Conversation>>();
  Timer? debounce;

  Future<void> load() async {
    try {
      final list = await repo.fetchConversations();
      if (!controller.isClosed) controller.add(list);
    } catch (e, s) {
      if (!controller.isClosed) controller.addError(e, s);
    }
  }

  load();
  final channel = repo.watchInbox(() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), load);
  });
  ref.onDispose(() {
    debounce?.cancel();
    repo.removeChannel(channel);
    controller.close();
  });
  return controller.stream;
});

/// Unread messages across all conversations — the badge on Messages.
final unreadMessagesProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(conversationsProvider).valueOrNull ?? const <Conversation>[];
  return list.fold<int>(0, (sum, c) => sum + c.unread);
});

/// When the other side last read a chat — for "Seen". Keyed by
/// `(bookingType, bookingId, otherId)`.
final otherReadProvider = StreamProvider.autoDispose
    .family<DateTime?, (String, String, String)>((ref, key) {
  return ref.watch(chatRepositoryProvider).watchOtherRead(key.$1, key.$2, key.$3);
});
