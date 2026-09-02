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
  final String id;
  final BookingKind kind;
  final String customerId;
  final String? riderId;
  final String status; // pending | accepted | ongoing | completed | cancelled
  final double? estimatedFare;
  final double? finalFare;
  final String? paymentMethod; // cash | gcash | card
  final String? paymentStatus; // pending | paid | failed | refunded
  final int? rating;
  final String? review;
  final String? cancelledReason;
  final DateTime createdAt;

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
  });

  bool get isActive => status == 'pending' || status == 'accepted' || status == 'ongoing';
  bool get canCancel => status == 'pending' || status == 'accepted';
  bool get canRate => status == 'completed' && rating == null;
  bool get needsPayment =>
      kind == BookingKind.transport &&
      paymentMethod != null &&
      paymentMethod != 'cash' &&
      (paymentStatus == 'pending' || paymentStatus == 'failed') &&
      status != 'cancelled';

  String get displayFare => Formatters.currency(finalFare ?? estimatedFare);

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
      };
}

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

  const FoodDeliveryModel({
    required super.id,
    required super.customerId,
    required this.restaurantName,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.instructions = '',
    required this.vehicleId,
    this.distanceKm,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentStatus,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
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
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
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
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentStatus,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
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
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      paymentStatus: json['payment_status'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
