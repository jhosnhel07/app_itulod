import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_model.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository(Supabase.instance.client));

/// Per-booking chat, backed by `booking_messages` (sql/015 in the web repo)
/// and the Messages inbox (sql/046). Messages are keyed by (booking_type,
/// booking_id) because the four booking tables share one messages table.
/// Sending is gated to accepted/ongoing bookings by RLS; a finished booking
/// still shows its thread read-only.
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
    String body = '',
    String? imagePath,
  }) async {
    await _client.from('booking_messages').insert({
      'booking_type': bookingType,
      'booking_id': bookingId,
      'sender_id': senderId,
      'body': body,
      if (imagePath != null) 'image_path': imagePath,
    });
  }

  /// Uploads a photo to chat-photos (`<type>/<booking id>/<file>`) and sends it.
  Future<void> sendPhoto({
    required String bookingType,
    required String bookingId,
    required String senderId,
    required File file,
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    final (type, saveExt) = switch (ext) {
      'png' => ('image/png', 'png'),
      'webp' => ('image/webp', 'webp'),
      _ => ('image/jpeg', 'jpg'),
    };
    final path = '$bookingType/$bookingId/${DateTime.now().millisecondsSinceEpoch}-'
        '${Random().nextInt(1 << 30).toRadixString(36)}.$saveExt';
    await _client.storage.from('chat-photos').upload(path, file, fileOptions: FileOptions(contentType: type));
    await sendMessage(bookingType: bookingType, bookingId: bookingId, senderId: senderId, imagePath: path);
  }

  /// One-hour links for photos (the bucket is private).
  Future<Map<String, String>> signPhotos(List<String> paths) async {
    if (paths.isEmpty) return {};
    final links = await _client.storage.from('chat-photos').createSignedUrlsResult(paths, 3600);
    return {for (final l in links.whereType<SignedUrlSuccess>()) l.path: l.signedUrl};
  }

  /// The Messages list, newest first.
  Future<List<Conversation>> fetchConversations() async {
    final rows = await _client.rpc('my_conversations') as List;
    return rows.map((r) => Conversation.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<void> markRead(String bookingType, String bookingId) async {
    await _client.rpc('mark_conversation_read', params: {'p_type': bookingType, 'p_id': bookingId});
  }

  /// When the other side last read this chat — for "Seen".
  Stream<DateTime?> watchOtherRead(String bookingType, String bookingId, String otherId) {
    return _client
        .from('booking_message_reads')
        .stream(primaryKey: ['user_id', 'booking_type', 'booking_id'])
        .eq('booking_id', bookingId)
        .map((rows) {
          for (final r in rows) {
            if (r['user_id'] == otherId && r['booking_type'] == bookingType) {
              return DateTime.tryParse(r['last_read_at']?.toString() ?? '');
            }
          }
          return null;
        });
  }

  /// Any new message or read receipt of mine — the list refreshes on it.
  RealtimeChannel watchInbox(void Function() onChange) {
    return _client
        .channel('messages-inbox-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert, schema: 'public', table: 'booking_messages',
            callback: (_) => onChange())
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'booking_message_reads',
            callback: (_) => onChange())
        .subscribe();
  }

  Future<void> removeChannel(RealtimeChannel channel) => _client.removeChannel(channel);
}
