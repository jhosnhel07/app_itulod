class ChatMessage {
  final String id;
  final String bookingType;
  final String bookingId;
  final String senderId;
  final String body;
  /// Photo in the private chat-photos bucket (web sql/046), or null.
  final String? imagePath;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.bookingType,
    required this.bookingId,
    required this.senderId,
    required this.body,
    this.imagePath,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'].toString(),
      bookingType: json['booking_type']?.toString() ?? '',
      bookingId: json['booking_id'].toString(),
      senderId: json['sender_id'].toString(),
      body: json['body'] as String? ?? '',
      imagePath: json['image_path'] as String?,
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}

/// One row of the Messages list: a booking that has a rider (web sql/046
/// my_conversations). [otherPhone] is only filled while the trip is active.
class Conversation {
  final String bookingType;
  final String bookingId;
  final String status;
  /// 'customer' or 'rider' — which side of the booking you are.
  final String iAm;
  final String otherId;
  final String otherName;
  final String? otherAvatar;
  final String? otherPhone;
  /// The rider's vehicle and plate (shown to the customer).
  final String? vehicle;
  final String route;
  final String? lastBody;
  final bool lastHasPhoto;
  final bool lastMine;
  final DateTime? lastAt;
  final int unread;
  final DateTime? otherReadAt;
  final bool canSend;
  final DateTime sortAt;

  const Conversation({
    required this.bookingType,
    required this.bookingId,
    required this.status,
    required this.iAm,
    required this.otherId,
    required this.otherName,
    this.otherAvatar,
    this.otherPhone,
    this.vehicle,
    required this.route,
    this.lastBody,
    this.lastHasPhoto = false,
    this.lastMine = false,
    this.lastAt,
    this.unread = 0,
    this.otherReadAt,
    required this.canSend,
    required this.sortAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) {
    DateTime? at(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
    final name = (j['other_name'] as String?)?.trim() ?? '';
    return Conversation(
      bookingType: j['booking_type']?.toString() ?? '',
      bookingId: j['booking_id']?.toString() ?? '',
      status: j['status']?.toString() ?? '',
      iAm: j['i_am']?.toString() ?? 'customer',
      otherId: j['other_id']?.toString() ?? '',
      otherName: name.isEmpty ? 'iTULOD user' : name,
      otherAvatar: j['other_avatar'] as String?,
      otherPhone: j['other_phone'] as String?,
      vehicle: j['vehicle'] as String?,
      route: j['route']?.toString() ?? '',
      lastBody: j['last_body'] as String?,
      lastHasPhoto: j['last_has_photo'] == true,
      lastMine: j['last_mine'] == true,
      lastAt: at(j['last_at']),
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      otherReadAt: at(j['other_read_at']),
      canSend: j['can_send'] == true,
      sortAt: at(j['sort_at']) ?? DateTime.now(),
    );
  }

  /// Preview line in the list.
  String get preview {
    if (lastAt == null) return 'No messages yet — say hello';
    final text = (lastBody ?? '').isEmpty && lastHasPhoto ? '📷 Photo' : (lastBody ?? '');
    return lastMine ? 'You: $text' : text;
  }
}
