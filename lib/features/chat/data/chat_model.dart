class ChatMessage {
  final String id;
  final String bookingId;
  final String senderId;
  final String text;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'].toString(),
      bookingId: json['booking_id'].toString(),
      senderId: json['sender_id'].toString(),
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}
