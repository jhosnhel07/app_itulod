import '../../core/utils/formatters.dart';

enum BookingKind { transport, food, parcel, hauling }

extension BookingKindX on BookingKind {
  String get tableName {
    switch (this) {
      case BookingKind.transport:
        return 'transport_bookings';
      case BookingKind.food:
        return 'food_deliveries';
      case BookingKind.parcel:
        return 'parcel_deliveries';
      case BookingKind.hauling:
        return 'hauling_bookings';
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
      case BookingKind.hauling:
        return 'Hauling';
    }
  }
}

BookingKind bookingKindFromTable(String table) {
  switch (table) {
    case 'food_deliveries':
      return BookingKind.food;
    case 'parcel_deliveries':
      return BookingKind.parcel;
    case 'hauling_bookings':
      return BookingKind.hauling;
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
  final String? vehicleId;
  // pending | accepted | ongoing | completed | cancelled | expired | no_show
  final String status;
  final double? estimatedFare;
  final double? finalFare;
  final String? paymentMethod; // cash | gcash | wallet | card (legacy)
  final String? paymentStatus; // pending | paid | failed | refunded
  /// PayMongo source/session reference — set once a GCash checkout started.
  final String? paymongoReference;
  final int? rating;
  final String? review;
  final String? cancelledReason;
  final DateTime createdAt;
  /// The moment a rider was confirmed onto this booking — the anchor for the
  /// post-acceptance grace period. Null until a rider accepts.
  final DateTime? acceptedAt;
  final double? distanceKm;

  final double? tipAmount;
  final double? cancellationFee;
  final String? promoCode;
  final double? discountAmount;

  const BookingBase({
    required this.id,
    required this.kind,
    required this.customerId,
    this.riderId,
    this.vehicleId,
    required this.status,
    this.estimatedFare,
    this.finalFare,
    this.paymentMethod,
    this.paymentStatus,
    this.paymongoReference,
    this.rating,
    this.review,
    this.cancelledReason,
    required this.createdAt,
    this.acceptedAt,
    this.distanceKm,
    this.tipAmount,
    this.cancellationFee,
    this.promoCode,
    this.discountAmount,
  });

  bool get isActive => status == 'pending' || status == 'accepted' || status == 'ongoing';
  bool get canCancel => status == 'pending' || status == 'accepted';
  bool get canRate => status == 'completed' && rating == null;
  bool get isExpired => status == 'expired';
  bool get isNoShow => status == 'no_show';

  /// Chat opens once a rider is assigned; RLS only accepts new messages while
  /// the booking is accepted/ongoing.
  bool get hasRider => riderId != null && riderId!.isNotEmpty;
  bool get canSendChat => hasRider && (status == 'accepted' || status == 'ongoing');

  /// A booking that can no longer be edited, confirmed, or acted on by
  /// anyone but the system/admin.
  bool get isTerminal =>
      status == 'completed' ||
      status == 'cancelled' ||
      status == 'expired' ||
      status == 'no_show';

  /// What `create-payment` will charge: a ride's fare is known at booking
  /// time; food/parcel only once the rider confirms it (finalize-fare).
  /// Mirrors the web's `paymentDue()` in customer.js.
  double? get payableAmount =>
      kind == BookingKind.transport ? estimatedFare : finalFare;

  /// Still owes a GCash/wallet payment — same rule as the web's
  /// `paymentDue()`. Cash bookings never do.
  bool get needsPayment =>
      (paymentMethod == 'gcash' || paymentMethod == 'wallet') &&
      (paymentStatus == null || paymentStatus == 'pending' || paymentStatus == 'failed') &&
      status != 'cancelled' &&
      status != 'expired' &&
      status != 'no_show' &&
      (payableAmount ?? 0) > 0;

  /// Food/parcel paid online but the rider hasn't confirmed the fare yet —
  /// the customer is told the payment step is coming.
  bool get awaitingFinalFare =>
      kind != BookingKind.transport &&
      (paymentMethod == 'gcash' || paymentMethod == 'wallet') &&
      finalFare == null &&
      !isTerminal;

  String get displayFare => Formatters.currency(finalFare ?? estimatedFare);

  String get pickupLine {
    switch (kind) {
      case BookingKind.transport:
        return (this as TransportBookingModel).pickupAddress;
      case BookingKind.food:
        return (this as FoodDeliveryModel).pickupAddress;
      case BookingKind.parcel:
        return (this as ParcelDeliveryModel).senderAddress;
      case BookingKind.hauling:
        return (this as HaulingBookingModel).pickupAddress;
    }
  }

  String get dropoffLine {
    switch (kind) {
      case BookingKind.transport:
        return (this as TransportBookingModel).destinationAddress;
      case BookingKind.food:
        return (this as FoodDeliveryModel).deliveryAddress;
      case BookingKind.parcel:
        return (this as ParcelDeliveryModel).receiverAddress;
      case BookingKind.hauling:
        return (this as HaulingBookingModel).dropoffAddress;
    }
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
      case BookingKind.hauling:
        final b = this as HaulingBookingModel;
        return '${b.pickupAddress} → ${b.dropoffAddress}';
    }
  }

  /// Proof-of-delivery photo (food/parcel only).
  String? get deliveryProofUrl => null;

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
}

DateTime? _parseTimestamp(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String);

double? _num(Object? v) => (v as num?)?.toDouble();

class TransportBookingModel extends BookingBase {
  final String pickupAddress;
  final String destinationAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final DateTime? scheduledFor;

  const TransportBookingModel({
    required super.id,
    required super.customerId,
    super.vehicleId,
    required this.pickupAddress,
    required this.destinationAddress,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.scheduledFor,
    super.distanceKm,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentMethod,
    super.paymentStatus,
    super.paymongoReference,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.promoCode,
    super.discountAmount,
  }) : super(kind: BookingKind.transport);

  factory TransportBookingModel.fromJson(Map<String, dynamic> json) {
    return TransportBookingModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      vehicleId: json['vehicle_id'] as String?,
      pickupAddress: json['pickup_address'] as String? ?? '',
      destinationAddress: json['destination_address'] as String? ?? '',
      pickupLat: _num(json['pickup_lat']),
      pickupLng: _num(json['pickup_lng']),
      destinationLat: _num(json['destination_lat']),
      destinationLng: _num(json['destination_lng']),
      scheduledFor: _parseTimestamp(json['scheduled_for']),
      distanceKm: _num(json['distance_km']),
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: _num(json['estimated_fare']),
      finalFare: _num(json['final_fare']),
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String?,
      paymongoReference: json['paymongo_reference'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: _num(json['tip_amount']),
      cancellationFee: _num(json['cancellation_fee']),
      promoCode: json['promo_code'] as String?,
      discountAmount: _num(json['discount_amount']),
    );
  }
}

class FoodDeliveryModel extends BookingBase {
  final String restaurantName;
  final String pickupAddress;
  final String deliveryAddress;
  final String instructions;
  final String? restaurantId;
  /// Cart total at checkout (sum of `food_order_items`).
  final double? itemSubtotal;
  /// Distance-based delivery fee at checkout.
  final double? deliveryFee;
  /// What the rider actually paid at the counter (receipt photo).
  final double? actualFoodCost;
  final String? receiptPhotoUrl;
  final String? _deliveryProofUrl;

  const FoodDeliveryModel({
    required super.id,
    required super.customerId,
    required this.restaurantName,
    required this.pickupAddress,
    required this.deliveryAddress,
    this.instructions = '',
    super.vehicleId,
    super.distanceKm,
    this.restaurantId,
    this.itemSubtotal,
    this.deliveryFee,
    this.actualFoodCost,
    this.receiptPhotoUrl,
    String? deliveryProofUrl,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentMethod,
    super.paymentStatus,
    super.paymongoReference,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.promoCode,
    super.discountAmount,
  })  : _deliveryProofUrl = deliveryProofUrl,
        super(kind: BookingKind.food);

  @override
  String? get deliveryProofUrl => _deliveryProofUrl;

  factory FoodDeliveryModel.fromJson(Map<String, dynamic> json) {
    return FoodDeliveryModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      restaurantName: json['restaurant_name'] as String? ?? '',
      pickupAddress: json['pickup_address'] as String? ?? '',
      deliveryAddress: json['delivery_address'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      vehicleId: json['vehicle_id'] as String?,
      distanceKm: _num(json['distance_km']),
      restaurantId: json['restaurant_id'] as String?,
      itemSubtotal: _num(json['item_subtotal']),
      deliveryFee: _num(json['delivery_fee']),
      actualFoodCost: _num(json['actual_food_cost']),
      receiptPhotoUrl: json['receipt_photo_url'] as String?,
      deliveryProofUrl: json['delivery_proof_url'] as String?,
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: _num(json['estimated_fare']),
      finalFare: _num(json['final_fare']),
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String?,
      paymongoReference: json['paymongo_reference'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: _num(json['tip_amount']),
      cancellationFee: _num(json['cancellation_fee']),
      promoCode: json['promo_code'] as String?,
      discountAmount: _num(json['discount_amount']),
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
  final bool isRoundTrip;
  final double codAmount;
  final String? _deliveryProofUrl;

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
    super.vehicleId,
    super.distanceKm,
    this.isRoundTrip = false,
    this.codAmount = 0.0,
    String? deliveryProofUrl,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentMethod,
    super.paymentStatus,
    super.paymongoReference,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.promoCode,
    super.discountAmount,
  })  : _deliveryProofUrl = deliveryProofUrl,
        super(kind: BookingKind.parcel);

  @override
  String? get deliveryProofUrl => _deliveryProofUrl;

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
      parcelWeight: _num(json['parcel_weight']),
      parcelDescription: json['parcel_description'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      vehicleId: json['vehicle_id'] as String?,
      distanceKm: _num(json['distance_km']),
      isRoundTrip: json['is_round_trip'] as bool? ?? false,
      codAmount: _num(json['cod_amount']) ?? 0.0,
      deliveryProofUrl: json['delivery_proof_url'] as String?,
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: _num(json['estimated_fare']),
      finalFare: _num(json['final_fare']),
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String?,
      paymongoReference: json['paymongo_reference'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: _num(json['tip_amount']),
      cancellationFee: _num(json['cancellation_fee']),
      promoCode: json['promo_code'] as String?,
      discountAmount: _num(json['discount_amount']),
    );
  }
}

/// Big / heavy items with a hauling vehicle and optional helpers
/// (`hauling_bookings`, sql/022). Lifecycle mirrors a parcel.
class HaulingBookingModel extends BookingBase {
  final String pickupAddress;
  final String dropoffAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String senderName;
  final String senderPhone;
  final String receiverName;
  final String receiverPhone;
  /// furniture | appliances | moving | construction | goods | other
  final String itemCategory;
  final String itemDescription;
  final double? estimatedWeightKg;
  final int helpers;
  final double helperFee;
  final String instructions;
  final DateTime? scheduledFor;
  final String? _deliveryProofUrl;

  const HaulingBookingModel({
    required super.id,
    required super.customerId,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    required this.senderName,
    this.senderPhone = '',
    required this.receiverName,
    this.receiverPhone = '',
    this.itemCategory = 'other',
    required this.itemDescription,
    this.estimatedWeightKg,
    this.helpers = 0,
    this.helperFee = 0,
    this.instructions = '',
    this.scheduledFor,
    String? deliveryProofUrl,
    super.vehicleId,
    super.distanceKm,
    super.riderId,
    required super.status,
    super.estimatedFare,
    super.finalFare,
    super.paymentMethod,
    super.paymentStatus,
    super.paymongoReference,
    super.rating,
    super.review,
    super.cancelledReason,
    required super.createdAt,
    super.acceptedAt,
    super.tipAmount,
    super.cancellationFee,
    super.promoCode,
    super.discountAmount,
  })  : _deliveryProofUrl = deliveryProofUrl,
        super(kind: BookingKind.hauling);

  @override
  String? get deliveryProofUrl => _deliveryProofUrl;

  String get categoryLabel => haulingCategoryLabel(itemCategory);

  factory HaulingBookingModel.fromJson(Map<String, dynamic> json) {
    return HaulingBookingModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropoffAddress: json['dropoff_address'] as String? ?? '',
      pickupLat: _num(json['pickup_lat']),
      pickupLng: _num(json['pickup_lng']),
      dropoffLat: _num(json['dropoff_lat']),
      dropoffLng: _num(json['dropoff_lng']),
      senderName: json['sender_name'] as String? ?? '',
      senderPhone: json['sender_phone'] as String? ?? '',
      receiverName: json['receiver_name'] as String? ?? '',
      receiverPhone: json['receiver_phone'] as String? ?? '',
      itemCategory: json['item_category'] as String? ?? 'other',
      itemDescription: json['item_description'] as String? ?? '',
      estimatedWeightKg: _num(json['estimated_weight_kg']),
      helpers: (json['helpers'] as num?)?.toInt() ?? 0,
      helperFee: _num(json['helper_fee']) ?? 0,
      instructions: json['instructions'] as String? ?? '',
      scheduledFor: _parseTimestamp(json['scheduled_for']),
      deliveryProofUrl: json['delivery_proof_url'] as String?,
      vehicleId: json['vehicle_id'] as String?,
      distanceKm: _num(json['distance_km']),
      riderId: json['rider_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      estimatedFare: _num(json['estimated_fare']),
      finalFare: _num(json['final_fare']),
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String?,
      paymongoReference: json['paymongo_reference'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      cancelledReason: json['cancelled_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: _parseTimestamp(json['accepted_at']),
      tipAmount: _num(json['tip_amount']),
      cancellationFee: _num(json['cancellation_fee']),
      promoCode: json['promo_code'] as String?,
      discountAmount: _num(json['discount_amount']),
    );
  }
}

const Map<String, String> haulingCategories = {
  'furniture': 'Furniture',
  'appliances': 'Appliances',
  'moving': 'House / office moving',
  'construction': 'Construction materials',
  'goods': 'Business goods / sacks',
  'other': 'Other items',
};

String haulingCategoryLabel(String id) => haulingCategories[id] ?? 'Other items';

/// One stop on a multi-stop ride (`ride_stops`, sql/016).
class RideStop {
  final String id;
  final int stopOrder;
  final String address;
  final double? lat;
  final double? lng;
  final DateTime? arrivedAt;

  const RideStop({
    required this.id,
    required this.stopOrder,
    required this.address,
    this.lat,
    this.lng,
    this.arrivedAt,
  });

  bool get arrived => arrivedAt != null;

  factory RideStop.fromJson(Map<String, dynamic> json) => RideStop(
        id: json['id'] as String,
        stopOrder: json['stop_order'] as int? ?? 0,
        address: json['address'] as String? ?? '',
        lat: _num(json['lat']),
        lng: _num(json['lng']),
        arrivedAt: _parseTimestamp(json['arrived_at']),
      );
}

/// One line of a cart-based food order (`food_order_items`, sql/018).
class FoodOrderItem {
  final String id;
  final String name;
  final double unitPrice;
  final int quantity;
  final double subtotal;
  final bool isOutOfStock;

  const FoodOrderItem({
    required this.id,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
    this.isOutOfStock = false,
  });

  factory FoodOrderItem.fromJson(Map<String, dynamic> json) => FoodOrderItem(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        unitPrice: _num(json['unit_price']) ?? 0,
        quantity: json['quantity'] as int? ?? 0,
        subtotal: _num(json['subtotal']) ?? 0,
        isOutOfStock: json['is_out_of_stock'] as bool? ?? false,
      );
}
