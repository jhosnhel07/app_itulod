import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_model.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository(Supabase.instance.client));

/// Per-booking chat, backed by `booking_messages` (sql/015 in the web repo).
/// Messages are keyed by (booking_type, booking_id) because the three booking
/// tables share one messages table. Sending is gated to accepted/ongoing
/// bookings by RLS; a finished booking still shows its thread read-only.
class ChatRepository {
  final SupabaseClient _client;

  ChatRepository(this._client);

  Stream<List<ChatMessage>> watchMessages(String bookingType, String bookingId) {
    // Realtime streams take a single filter; booking ids are UUIDs, so the
    // booking_type check is a guard rather than the real filter.
    return _client
        .from('booking_messages')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true)
        .map((maps) => maps
            .where((m) => m['booking_type'] == bookingType)
            .map((m) => ChatMessage.fromJson(m))
            .toList());
  }

  Future<void> sendMessage({
    required String bookingType,
    required String bookingId,
    required String senderId,
    required String body,
  }) async {
    await _client.from('booking_messages').insert({
      'booking_type': bookingType,
      'booking_id': bookingId,
      'sender_id': senderId,
      'body': body,
    });
  }
}
