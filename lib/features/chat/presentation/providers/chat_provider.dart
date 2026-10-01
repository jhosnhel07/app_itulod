import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/chat_model.dart';
import '../../data/chat_repository.dart';

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((ref, bookingId) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.watchMessages(bookingId);
});
