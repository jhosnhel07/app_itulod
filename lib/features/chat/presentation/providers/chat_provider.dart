import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/chat_model.dart';
import '../../data/chat_repository.dart';

/// Keyed by `(bookingType, bookingId)`.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, (String, String)>((ref, key) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchMessages(key.$1, key.$2);
});
