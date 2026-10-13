class ChatMessage {
  final String id;
  final String bookingType;
  final String bookingId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.bookingType,
    required this.bookingId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'].toString(),
      bookingType: json['booking_type']?.toString() ?? '',
      bookingId: json['booking_id'].toString(),
      senderId: json['sender_id'].toString(),
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}
