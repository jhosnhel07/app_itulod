import '../../core/utils/formatters.dart';

enum BookingKind { transport, food, parcel }

extension BookingKindX on BookingKind {
  String get tableName {
    switch (this) {
      case BookingKind.transport:
        return 'transport_bookings';
      case BookingKind.food:
        return 'food_deliveries';
      case BookingKind.parcel:
        return 'parcel_deliveries';
    }
  }

  String get label {
    switch (this) {
      case BookingKind.transport:
        return 'Ride';
      case BookingKind.food:
        return 'Food';
      case BookingKind.parcel:
        return 'Parcel';
    }
  }
}

BookingKind bookingKindFromTable(String table) {
  switch (table) {
    case 'food_deliveries':
      return BookingKind.food;
    case 'parcel_deliveries':
      return BookingKind.parcel;
    default:
      return BookingKind.transport;
  }
}

/// Common fields shared by all booking tables.
class BookingBase {
  /// How long a booking has to be accepted (from [createdAt]) or completed
  /// (from [acceptedAt]) before the server auto-expires it. Mirrors the
  /// `expire_stale_bookings()` grace period in migration 010b — keep both in
  /// sync if this ever changes.
  static const int gracePeriodMinutes = 15;

  final String id;
  final BookingKind kind;
  final String customerId;
  final String? riderId;
  // pending | accepted | ongoing | completed | cancelled | expired | no_show
  final String status;
  final double? estimatedFare;
  final double? finalFare;
  final String? paymentMethod; // cash | gcash | card
  final String? paymentStatus; // pending | paid | failed | refunded
  final int? rating;
  final String? review;
  final String? cancelledReason;
  final DateTime createdAt;
  /// The moment a rider was confirmed onto this booking — the anchor for the
  /// post-acceptance grace period. Null until a rider accepts.
  final DateTime? acceptedAt;

  final double? tipAmount;
  final double? cancellationFee;
  final DateTime? scheduledFor;
  final String? promoCode;

  const BookingBase({
    required this.id,
    required this.kind,
    required this.customerId,
    this.riderId,
    required this.status,
    this.estimatedFare,
    this.finalFare,
    this.paymentMethod,
    this.paymentStatus,
    this.rating,
    this.review,
    this.cancelledReason,
    required this.createdAt,
    this.acceptedAt,
    this.tipAmount,
    this.cancellationFee,
    this.scheduledFor,
    this.promoCode,
  });

  bool get isActive => status == 'pending' || status == 'accepted' || status == 'ongoing';
  bool get canCancel => status == 'pending' || status == 'accepted';
  bool get canRate => status == 'completed' && rating == null;
  bool get isExpired => status == 'expired';
  bool get isNoShow => status == 'no_show';

  /// A booking that can no longer be edited, confirmed, or acted on by
  /// anyone but the system/admin.
  bool get isTerminal =>
      status == 'completed' ||
      status == 'cancelled' ||
      status == 'expired' ||
      status == 'no_show';

  bool get needsPayment =>
      kind == BookingKind.transport &&
      paymentMethod != null &&
      paymentMethod != 'cash' &&
      (paymentStatus == 'pending' || paymentStatus == 'failed') &&
      status != 'cancelled' &&
      status != 'expired';

  /// When this booking is due to auto-expire under the 15-minute grace
  /// period, or null once it's moved past the pending/accepted stages.
  DateTime? get expiresAt {
    if (status == 'pending') {
      return createdAt.add(const Duration(minutes: gracePeriodMinutes));
    }
    if (status == 'accepted' && acceptedAt != null) {
      return acceptedAt!.add(const Duration(minutes: gracePeriodMinutes));
    }
    return null;
  }

  String get displayFare {
    if (kind == BookingKind.food) {
      final b = this as FoodDeliveryModel;
      final foodTotal = b.actualFoodCost ?? b.totalItemsPrice ?? 0.0;
      final deliveryFee = finalFare ?? estimatedFare ?? 0.0;
      return Formatters.currency(foodTotal + deliveryFee);
    }
    return Formatters.currency(finalFare ?? estimatedFare);
  }

  String get routeLine {
    switch (kind) {
      case BookingKind.transport:
        final b = this as TransportBookingModel;
        return '${b.pickupAddress} → ${b.destinationAddress}';
      case BookingKind.food:
        final b = this as FoodDeliveryModel;
        return '${b.restaurantName} → ${b.deliveryAddress}';
      case BookingKind.parcel:
        final b = this as ParcelDeliveryModel;
        return '${b.senderAddress} → ${b.receiverAddress}';
    }
  }

  Map<String, dynamic> baseJson() => {
        'id': id,
        'customer_id': customerId,
        'rider_id': riderId,
        'status': status,
        'estimated_fare': estimatedFare,
        'final_fare': finalFare,
        'payment_method': paymentMethod,
        'payment_status': paymentStatus,
        'rating': rating,
        'review': review,
        'cancelled_reason': cancelledReason,
        'created_at': createdAt.toIso8601String(),
        'accepted_at': acceptedAt?.toIso8601String(),
        'tip_amount': tipAmount,
        'cancellation_fee': cancellationFee,
        'scheduled_for': scheduledFor?.toIso8601String(),
        'promo_code': promoCode,
      };
}

DateTime? _parseTimestamp(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String);

class TransportBookingModel extends BookingBase {
  final String vehicleId;
  final String pickupAddress;
  final String destinationAddress;
  final double? distanceKm;

  const TransportBookingModel({
    required super.id,
    required super.customerId,
    required this.vehicleId,
    required this.pickupAddress,
    required this.destinationAddress,
    this.distanceKm,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentMethod,
    super.paymentStatus,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.scheduledFor,
    super.promoCode,
  }) : super(kind: BookingKind.transport);

  factory TransportBookingModel.fromJson(Map<String, dynamic> json) {
    return TransportBookingModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      vehicleId: json['vehicle_id'] as String? ?? '',
      pickupAddress: json['pickup_address'] as String? ?? '',
      destinationAddress: json['destination_address'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: (json['tip_amount'] as num?)?.toDouble(),
      cancellationFee: (json['cancellation_fee'] as num?)?.toDouble(),
      scheduledFor: _parseTimestamp(json['scheduled_for']),
      promoCode: json['promo_code'] as String?,
    );
  }
}

class FoodDeliveryModel extends BookingBase {
  final String restaurantName;
  final String pickupAddress;
  final String deliveryAddress;
  final String instructions;
  final String vehicleId;
  final double? distanceKm;
  final String? restaurantId;
  final List<dynamic>? items;
  final double? totalItemsPrice;
  final double? actualFoodCost;
  final String? receiptPhotoUrl;

  const FoodDeliveryModel({
    required super.id,
    required super.customerId,
    required this.restaurantName,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.instructions = '',
    required this.vehicleId,
    this.distanceKm,
    this.restaurantId,
    this.items,
    this.totalItemsPrice,
    this.actualFoodCost,
    this.receiptPhotoUrl,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentStatus,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.scheduledFor,
    super.promoCode,
  }) : super(kind: BookingKind.food);

  factory FoodDeliveryModel.fromJson(Map<String, dynamic> json) {
    return FoodDeliveryModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      restaurantName: json['restaurant_name'] as String? ?? '',
      pickupAddress: json['pickup_address'] as String? ?? '',
      deliveryAddress: json['delivery_address'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      vehicleId: json['vehicle_id'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      restaurantId: json['restaurant_id'] as String?,
      items: json['items'] as List<dynamic>?,
      totalItemsPrice: (json['total_items_price'] as num?)?.toDouble(),
      actualFoodCost: (json['actual_food_cost'] as num?)?.toDouble(),
      receiptPhotoUrl: json['receipt_photo_url'] as String?,
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: (json['tip_amount'] as num?)?.toDouble(),
      cancellationFee: (json['cancellation_fee'] as num?)?.toDouble(),
      scheduledFor: _parseTimestamp(json['scheduled_for']),
      promoCode: json['promo_code'] as String?,
    );
  }
}

class ParcelDeliveryModel extends BookingBase {
  final String senderName;
  final String senderPhone;
  final String senderAddress;
  final String receiverName;
  final String receiverPhone;
  final String receiverAddress;
  final String parcelSize;
  final double? parcelWeight;
  final String parcelDescription;
  final String instructions;
  final String vehicleId;
  final bool isRoundTrip;
  final double codAmount;

  const ParcelDeliveryModel({
    required super.id,
    required super.customerId,
    required this.senderName,
    this.senderPhone = '',
    required this.senderAddress,
    required this.receiverName,
    this.receiverPhone = '',
    required this.receiverAddress,
    this.parcelSize = 'Small (fits a shoebox)',
    this.parcelWeight,
    this.parcelDescription = '',
    this.instructions = '',
    required this.vehicleId,
    this.isRoundTrip = false,
    this.codAmount = 0.0,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentStatus,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.scheduledFor,
    super.promoCode,
  }) : super(kind: BookingKind.parcel);

  factory ParcelDeliveryModel.fromJson(Map<String, dynamic> json) {
    return ParcelDeliveryModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      senderName: json['sender_name'] as String? ?? '',
      senderPhone: json['sender_phone'] as String? ?? '',
      senderAddress: json['sender_address'] as String? ?? '',
      receiverName: json['receiver_name'] as String? ?? '',
      receiverPhone: json['receiver_phone'] as String? ?? '',
      receiverAddress: json['receiver_address'] as String? ?? '',
      parcelSize: json['parcel_size'] as String? ?? 'Small (fits a shoebox)',
      parcelWeight: (json['parcel_weight'] as num?)?.toDouble(),
      parcelDescription: json['parcel_description'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      vehicleId: json['vehicle_id'] as String? ?? '',
      isRoundTrip: json['is_round_trip'] as bool? ?? false,
      codAmount: (json['cod_amount'] as num?)?.toDouble() ?? 0.0,
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: (json['tip_amount'] as num?)?.toDouble(),
      cancellationFee: (json['cancellation_fee'] as num?)?.toDouble(),
      scheduledFor: _parseTimestamp(json['scheduled_for']),
      promoCode: json['promo_code'] as String?,
    );
  }
}
