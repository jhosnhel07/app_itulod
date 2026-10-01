import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_model.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository(Supabase.instance.client));

class ChatRepository {
  final SupabaseClient _client;

  ChatRepository(this._client);

  Stream<List<ChatMessage>> watchMessages(String bookingId) {
    return _client
        .from('booking_messages')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true)
        .map((maps) => maps.map((m) => ChatMessage.fromJson(m)).toList());
  }

  Future<void> sendMessage(String bookingId, String senderId, String text) async {
    await _client.from('booking_messages').insert({
      'booking_id': bookingId,
      'sender_id': senderId,
      'text': text,
    });
  }
}
