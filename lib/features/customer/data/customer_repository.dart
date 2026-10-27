import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/fare_estimator.dart';
import '../../../shared/models/booking_models.dart';
import '../../../shared/models/profile_model.dart';
import '../../../shared/models/saved_address_model.dart';
import '../../../shared/models/vehicle_model.dart';
import '../../../shared/models/wallet_models.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(SupabaseConfig.client);
});

/// Payment-relevant slice of a transport booking, read by the receipt screen
/// while it waits for the PayMongo webhook to settle `payment_status`.
class TransportPaymentRow {
  final String? paymentStatus; // pending | paid | failed | refunded | null
  final String? paymentMethod; // cash | gcash
  final String? paymentSourceId; // PayMongo source id (the reference number)
  final String? paymentId; // PayMongo payment id, once charged
  final double? estimatedFare;
  final double? finalFare;
  final DateTime? createdAt;
  final String? pickupAddress;
  final String? destinationAddress;

  const TransportPaymentRow({
    this.paymentStatus,
    this.paymentMethod,
    this.paymentSourceId,
    this.paymentId,
    this.estimatedFare,
    this.finalFare,
    this.createdAt,
    this.pickupAddress,
    this.destinationAddress,
  });

  factory TransportPaymentRow.fromJson(Map<String, dynamic> json) {
    return TransportPaymentRow(
      paymentStatus: json['payment_status'] as String?,
      paymentMethod: json['payment_method'] as String?,
      paymentSourceId: json['payment_source_id'] as String?,
      paymentId: json['payment_id'] as String?,
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      pickupAddress: json['pickup_address'] as String?,
      destinationAddress: json['destination_address'] as String?,
    );
  }

  /// Whether the receipt screen should keep polling.
  bool get isSettling => paymentStatus == null || paymentStatus == 'pending';
  double? get fare => finalFare ?? estimatedFare;
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Result of [CustomerRepository.previewPromo].
class PromoPreview {
  final String? code;
  final double discount;
  final String? error;

  const PromoPreview({required this.code, required this.discount}) : error = null;
  const PromoPreview.invalid(this.error)
      : code = null,
        discount = 0;

  bool get isValid => error == null;
}

/// Snapshot shown on the customer home tab — lifetime stats plus whatever
/// booking is currently in flight. Mirrors the web dashboard's "home" view.
/// One online rider on the customer's "riders near you" map.
class NearbyRider {
  final LatLng point;
  final String? vehicleType;
  const NearbyRider(this.point, this.vehicleType);
}

class CustomerHomeSummary {
  final int completedTrips;
  final double totalSpent;
  final int tripsThisMonth;
  final BookingBase? activeBooking;
  /// Every booking still going (pending / accepted / ongoing), newest first —
  /// the banner on the booking screens.
  final List<BookingBase> activeBookings;
  final String? activeRiderName;
  final String? activeRiderPhone;

  const CustomerHomeSummary({
    this.completedTrips = 0,
    this.totalSpent = 0,
    this.tripsThisMonth = 0,
    this.activeBooking,
    this.activeBookings = const [],
    this.activeRiderName,
    this.activeRiderPhone,
  });
}

class CustomerRepository {
  /// Your newest booking of [kind] that is still going, checked fresh before
  /// booking the same service again (web: okToBookAgain).
  Future<BookingBase?> findActiveBooking(String customerId, BookingKind kind) async {
    final rows = await _supabase
        .from(kind.tableName)
        .select()
        .eq('customer_id', customerId)
        .inFilter('status', const ['pending', 'accepted', 'ongoing'])
        .order('created_at', ascending: false)
        .limit(1);
    final list = rows as List;
    return list.isEmpty ? null : _bookingFromRow(kind, Map<String, dynamic>.from(list.first as Map));
  }

  final SupabaseClient _supabase;

  CustomerRepository(this._supabase);

  // ── Vehicles ──────────────────────────────────────────────────────────

  Future<List<VehicleModel>> getAvailableVehicles() async {
    final response = await _supabase
        .from('vehicles')
        .select()
        .eq('is_available', true)
        .order('base_fare');
    return (response as List)
        .map((json) => VehicleModel.fromJson(json))
        .toList();
  }

  VehicleModel? vehicleById(List<VehicleModel> vehicles, String id) {
    for (final v in vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  // ── Create bookings ───────────────────────────────────────────────────

  /// Places a ride. Mirrors the web's ride form (customer.js wireRideForm):
  /// GCash/wallet payment is a separate later step, and a promo code is
  /// applied afterwards through [redeemPromo] — the `redeem-promo` function
  /// rejects a booking that already carries a promo_code, so it must never be
  /// written on insert.
  Future<TransportBookingModel> createTransportBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String pickupAddress,
    required String destinationAddress,
    required String paymentMethod,
    LatLng? pickupPoint,
    LatLng? destinationPoint,
    /// Real kilometres measured from the map pins. Falls back to the
    /// address-hash estimate when the customer typed addresses by hand.
    double? distanceKm,
    DateTime? scheduledFor,
    List<({String address, LatLng? point})> stops = const [],
    /// Group size; the server checks it against the vehicle's range and
    /// prices the ride with it (sql/044 vehicle_fare).
    int passengers = 1,
  }) async {
    final km = distanceKm ??
        FareEstimator.simulateDistanceKm(pickupAddress, destinationAddress);
    final fare = FareEstimator.estimateRideFare(vehicle, km, passengers);

    final row = await _supabase.from('transport_bookings').insert({
      'customer_id': customerId,
      'vehicle_id': vehicle.id,
      'pickup_address': pickupAddress.trim(),
      'destination_address': destinationAddress.trim(),
      'pickup_lat': pickupPoint?.latitude,
      'pickup_lng': pickupPoint?.longitude,
      'destination_lat': destinationPoint?.latitude,
      'destination_lng': destinationPoint?.longitude,
      'distance_km': double.parse(km.toStringAsFixed(2)),
      'estimated_fare': double.parse(fare.toStringAsFixed(2)),
      'passengers': passengers,
      'status': 'pending',
      'payment_method': paymentMethod,
      if (scheduledFor != null) 'scheduled_for': scheduledFor.toUtc().toIso8601String(),
    }).select().single();

    final filled = stops.where((s) => s.address.trim().isNotEmpty).toList();
    if (filled.isNotEmpty) {
      try {
        await _supabase.from('ride_stops').insert([
          for (var i = 0; i < filled.length; i++)
            {
              'booking_id': row['id'],
              'stop_order': i + 1,
              'address': filled[i].address.trim(),
              'lat': filled[i].point?.latitude,
              'lng': filled[i].point?.longitude,
            },
        ]);
      } catch (e, s) {
        AppLog.warn('Failed to insert ride stops', e, s);
        throw Exception("Ride booked, but the stops didn't save: $e");
      }
    }

    return TransportBookingModel.fromJson(row);
  }

  /// Applies a promo code to a just-placed ride via the `redeem-promo` Edge
  /// Function (rides only, one use per customer per code). Returns the
  /// discount in pesos; throws with the server's message on rejection.
  Future<double> redeemPromo({
    required String code,
    required String bookingId,
  }) async {
    final data = await _invoke('redeem-promo', {
      'code': code,
      'booking_type': 'transport',
      'booking_id': bookingId,
    }, fallbackError: 'That promo code could not be applied.');
    return (data['discount_amount'] as num?)?.toDouble() ?? 0;
  }

  /// Client-side preview of a promo before the ride is placed, using the
  /// same rules `redeem-promo` enforces. The server stays authoritative —
  /// this only shows the customer what to expect.
  Future<PromoPreview> previewPromo(String code, double fare) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return const PromoPreview.invalid('Enter a promo code.');
    final row = await _supabase
        .from('promo_codes')
        .select()
        .ilike('code', normalized)
        .maybeSingle();
    if (row == null || row['active'] != true) {
      return const PromoPreview.invalid('That promo code is not valid.');
    }
    final expires = DateTime.tryParse(row['expires_at'] as String? ?? '');
    if (expires != null && DateTime.now().isAfter(expires)) {
      return const PromoPreview.invalid('That promo code has expired.');
    }
    final maxUses = row['max_uses'] as int?;
    final used = row['uses_count'] as int? ?? 0;
    if (maxUses != null && used >= maxUses) {
      return const PromoPreview.invalid('That promo code has been fully used.');
    }
    final minFare = (row['min_fare'] as num?)?.toDouble();
    if (minFare != null && fare < minFare) {
      return PromoPreview.invalid(
          'This code needs a fare of at least ₱${minFare.toStringAsFixed(2)}.');
    }
    final value = (row['discount_value'] as num?)?.toDouble() ?? 0;
    var discount = row['discount_type'] == 'percent' ? fare * value / 100 : value;
    if (discount > fare) discount = fare;
    return PromoPreview(
        code: normalized, discount: double.parse(discount.toStringAsFixed(2)));
  }

  /// Places a cart-based food order exactly like the web checkout
  /// (customer.js wireFoodForm): the order row, then one
  /// `food_order_items` row per cart line. estimated_fare is items +
  /// delivery fee; final_fare is left for the rider to confirm at pickup,
  /// which is also when a GCash/wallet payment becomes due.
  Future<FoodDeliveryModel> createFoodBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String restaurantId,
    required String restaurantName,
    required String restaurantAddress,
    required String deliveryAddress,
    required List<({String menuItemId, String name, double unitPrice, int quantity})> items,
    required String paymentMethod,
    String instructions = '',
    /// Real kilometres from the map pins; falls back to the address-hash
    /// estimate when unavailable.
    double? distanceKm,
  }) async {
    final km = distanceKm ??
        FareEstimator.simulateDistanceKm(restaurantAddress, deliveryAddress);
    final subtotal = _round2(items.fold<double>(0, (s, i) => s + i.unitPrice * i.quantity));
    final deliveryFee = _round2(FareEstimator.estimateFare(vehicle, km));

    final row = await _supabase.from('food_deliveries').insert({
      'customer_id': customerId,
      'restaurant_id': restaurantId,
      'restaurant_name': restaurantName.trim(),
      'pickup_address': restaurantAddress.trim(),
      'delivery_address': deliveryAddress.trim(),
      'instructions': instructions.trim(),
      'vehicle_id': vehicle.id,
      'item_subtotal': subtotal,
      'delivery_fee': deliveryFee,
      'estimated_fare': _round2(subtotal + deliveryFee),
      'distance_km': double.parse(km.toStringAsFixed(2)),
      'status': 'pending',
      'payment_method': paymentMethod,
    }).select().single();

    try {
      await _supabase.from('food_order_items').insert([
        for (final i in items)
          {
            'food_delivery_id': row['id'],
            'menu_item_id': i.menuItemId,
            'name': i.name,
            'unit_price': i.unitPrice,
            'quantity': i.quantity,
            'subtotal': _round2(i.unitPrice * i.quantity),
          },
      ]);
    } catch (e, s) {
      AppLog.warn('Failed to insert food order items', e, s);
      throw Exception("Order placed, but the item list didn't save: $e");
    }

    return FoodDeliveryModel.fromJson(row);
  }

  Future<void> createParcelBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String senderName,
    String? senderPhone,
    required String senderAddress,
    required String receiverName,
    String? receiverPhone,
    required String receiverAddress,
    required String parcelSize,
    double? parcelWeight,
    String parcelDescription = '',
    String instructions = '',
    required String paymentMethod,
    /// Real kilometres from the map pins; falls back to the address-hash
    /// estimate when unavailable.
    double? distanceKm,
    bool isRoundTrip = false,
    double codAmount = 0.0,
  }) async {
    final km = distanceKm ??
        FareEstimator.simulateDistanceKm(senderAddress, receiverAddress);
    
    // For round trip, double the distance for the fare estimate
    final effectiveKm = isRoundTrip ? (km * 2) : km;
    final fare = FareEstimator.estimateFare(vehicle, effectiveKm);

    await _supabase.from('parcel_deliveries').insert({
      'customer_id': customerId,
      'sender_name': senderName.trim(),
      'sender_phone': senderPhone?.trim(),
      'sender_address': senderAddress.trim(),
      'receiver_name': receiverName.trim(),
      'receiver_phone': receiverPhone?.trim(),
      'receiver_address': receiverAddress.trim(),
      'parcel_size': parcelSize,
      'parcel_weight': parcelWeight,
      'parcel_description': parcelDescription.trim(),
      'instructions': instructions.trim(),
      'vehicle_id': vehicle.id,
      'distance_km': double.parse(km.toStringAsFixed(2)),
      'estimated_fare': double.parse(fare.toStringAsFixed(2)),
      'status': 'pending',
      'payment_method': paymentMethod,
      'is_round_trip': isRoundTrip,
      'cod_amount': codAmount,
    });
  }

  /// Books a hauling job (sql/022). Same trust model as the other kinds:
  /// the estimate (vehicle fare + helpers) is computed here, and the driver
  /// confirms the real fare at pickup — that's when GCash/wallet is charged.
  Future<HaulingBookingModel> createHaulingBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String pickupAddress,
    required String dropoffAddress,
    LatLng? pickupPoint,
    LatLng? dropoffPoint,
    required String senderName,
    String? senderPhone,
    required String receiverName,
    String? receiverPhone,
    required String itemCategory,
    required String itemDescription,
    double? estimatedWeightKg,
    int helpers = 0,
    required double helperFee,
    String instructions = '',
    DateTime? scheduledFor,
    required String paymentMethod,
    double? distanceKm,
  }) async {
    final km = distanceKm ?? FareEstimator.simulateDistanceKm(pickupAddress, dropoffAddress);
    final fare = FareEstimator.estimateFare(vehicle, km) + helpers * helperFee;
    final row = await _supabase.from('hauling_bookings').insert({
      'customer_id': customerId,
      'vehicle_id': vehicle.id,
      'pickup_address': pickupAddress.trim(),
      'dropoff_address': dropoffAddress.trim(),
      'pickup_lat': pickupPoint?.latitude,
      'pickup_lng': pickupPoint?.longitude,
      'dropoff_lat': dropoffPoint?.latitude,
      'dropoff_lng': dropoffPoint?.longitude,
      'sender_name': senderName.trim(),
      'sender_phone': senderPhone?.trim(),
      'receiver_name': receiverName.trim(),
      'receiver_phone': receiverPhone?.trim(),
      'item_category': itemCategory,
      'item_description': itemDescription.trim(),
      'estimated_weight_kg': estimatedWeightKg,
      'helpers': helpers,
      'helper_fee': helperFee,
      'instructions': instructions.trim(),
      if (scheduledFor != null) 'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'distance_km': double.parse(km.toStringAsFixed(2)),
      'estimated_fare': _round2(fare),
      'status': 'pending',
      'payment_method': paymentMethod,
    }).select().single();
    return HaulingBookingModel.fromJson(row);
  }

  /// Hauling drivers on iTULOD and how many are online now (sql/025).
  Future<({int drivers, int onlineNow})?> fetchHaulingAvailability() async {
    try {
      final rows = await _supabase.rpc('hauling_availability');
      if (rows is! List || rows.isEmpty) return null;
      final r = rows.first as Map;
      return (drivers: (r['drivers'] as num?)?.toInt() ?? 0, onlineNow: (r['online_now'] as num?)?.toInt() ?? 0);
    } catch (e, s) {
      AppLog.warn('hauling_availability failed', e, s);
      return null;
    }
  }

  /// Price of one hauling helper (platform_config.hauling_helper_fee).
  /// Unpaid cancellation / no-show fees the signed-in customer still owes
  /// (web sql/036 my_unpaid_fees). New bookings are refused until they're
  /// taken from the wallet, which happens automatically on a top-up.
  Future<double> fetchUnpaidFees() async {
    final owed = await _supabase.rpc('my_unpaid_fees');
    return (owed as num?)?.toDouble() ?? 0;
  }

  Future<double> fetchHaulingHelperFee() async {
    try {
      final row = await _supabase.from('platform_config').select('hauling_helper_fee').maybeSingle();
      return (row?['hauling_helper_fee'] as num?)?.toDouble() ?? 250;
    } catch (e, s) {
      AppLog.warn('fetchHaulingHelperFee failed', e, s);
      return 250;
    }
  }

  Future<void> applyReferralCode(String code) async {
    await _invoke('apply-referral-code', {'code': code},
        fallbackError: 'Could not redeem that code.');
  }

  /// "Report an issue" — refund, dispute, or anything else — optionally tied
  /// to a booking. Same `support_requests` table the web and the admin
  /// Support tab use.
  Future<void> createSupportRequest({
    required String category, // refund | dispute | other
    required String subject,
    required String message,
    BookingBase? booking,
  }) async {
    final uid = _supabase.auth.currentUser!.id;
    await _supabase.from('support_requests').insert({
      'customer_id': uid,
      'booking_type': booking?.kind.name,
      'booking_id': booking?.id,
      'category': category,
      'subject': subject.trim(),
      'message': message.trim(),
    });
  }

  // ── Booking details extras ────────────────────────────────────────────

  Future<List<RideStop>> fetchRideStops(String bookingId) async {
    final rows = await _supabase
        .from('ride_stops')
        .select()
        .eq('booking_id', bookingId)
        .order('stop_order');
    return (rows as List).map((r) => RideStop.fromJson(r)).toList();
  }

  Future<List<FoodOrderItem>> fetchFoodOrderItems(String foodDeliveryId) async {
    final rows = await _supabase
        .from('food_order_items')
        .select()
        .eq('food_delivery_id', foodDeliveryId)
        .order('created_at');
    return (rows as List).map((r) => FoodOrderItem.fromJson(r)).toList();
  }

  /// Latest rider application (vehicle, plate, licence, document links) —
  /// what the web's booking-details modal shows under Vehicle / Documents.
  Future<Map<String, dynamic>?> fetchRiderApplication(String riderId) async {
    try {
      return await _supabase
          .from('rider_applications')
          .select('vehicle_type, vehicle_plate, license_number, license_url, or_cr_url, status')
          .eq('rider_id', riderId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (e, s) {
      AppLog.warn('fetchRiderApplication failed', e, s);
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchVehicle(String vehicleId) async {
    try {
      return await _supabase
          .from('vehicles')
          .select('name, capacity, base_fare, per_km_rate, ride_base_fare, ride_per_km_rate, ride_base_km, extra_passenger_fee, fare_per_passenger, min_passengers, max_passengers')
          .eq('id', vehicleId)
          .maybeSingle();
    } catch (e, s) {
      AppLog.warn('fetchVehicle failed', e, s);
      return null;
    }
  }

  /// The configured fee for cancelling after a rider accepted
  /// (platform_config.cancellation_fee). The DB trigger records it; the
  /// client only uses it to warn before confirming.
  Future<double?> fetchCancellationFee() async {
    try {
      final row = await _supabase
          .from('platform_config')
          .select('cancellation_fee')
          .maybeSingle();
      return (row?['cancellation_fee'] as num?)?.toDouble();
    } catch (e, s) {
      AppLog.warn('fetchCancellationFee failed', e, s);
      return null;
    }
  }

  // ── Live rider location ───────────────────────────────────────────────

  /// Online, approved, idle riders with coarse (~110 m) coordinates — the
  /// only way rider positions reach a customer before booking (sql/017).
  Future<List<NearbyRider>> fetchNearbyRiders() async {
    final rows = await _supabase.rpc('get_nearby_riders');
    return [
      for (final r in (rows as List))
        NearbyRider(
          LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
          r['vehicle_type'] as String?,
        ),
    ];
  }

  /// The assigned rider's live position while a trip is accepted/ongoing.
  Stream<LatLng?> watchRiderLocation(String riderId) {
    return _supabase
        .from('rider_locations')
        .stream(primaryKey: ['rider_id'])
        .eq('rider_id', riderId)
        .map((rows) {
      if (rows.isEmpty) return null;
      final r = rows.first;
      final lat = (r['lat'] as num?)?.toDouble();
      final lng = (r['lng'] as num?)?.toDouble();
      return (lat == null || lng == null) ? null : LatLng(lat, lng);
    });
  }

  // ── Payments ──────────────────────────────────────────────────────────

  /// Calls the `create-payment` Edge Function and returns the
  /// PayMongo hosted checkout URL for the given booking.
  Future<String> createGcashCheckoutUrl(String bookingId, {String bookingType = 'transport'}) async {
    final data = await _invoke(
      'create-payment',
      {'booking_id': bookingId, 'booking_type': bookingType, 'method': 'gcash'},
      fallbackError: 'Could not start GCash checkout',
    );
    final url = data['checkout_url'];
    if (url is! String) throw Exception('Could not start GCash checkout');
    return url;
  }

  /// Asks the server to settle a GCash payment now: after Authorize it
  /// charges the payment (web sync-payment-status) and returns
  /// 'paid' / 'failed' / 'pending'. [type] is a booking kind or 'wallet'.
  Future<String?> syncPayment(String type, String id) async {
    try {
      final res = await _supabase.functions.invoke('sync-payment-status', body: {'booking_type': type, 'booking_id': id});
      final data = res.data;
      return data is Map ? data['payment_status'] as String? : null;
    } catch (e, s) {
      AppLog.warn('syncPayment($type, $id) failed', e, s);
      return null;
    }
  }

  /// The receipt row for a booking or wallet top-up (web payment-return.html):
  /// payment_status, payment_method, paymongo_reference, amount, created_at,
  /// route — wallet top-ups use their own column names, mapped here.
  Future<Map<String, dynamic>?> fetchPaymentReceipt(String type, String id) async {
    const routeCols = {
      'transport': ', pickup_address, destination_address',
      'food': ', restaurant_name, delivery_address',
      'parcel': ', sender_address, receiver_address',
      'hauling': ', pickup_address, dropoff_address',
    };
    try {
      if (type == 'wallet') {
        final row = await _supabase.from('wallet_topups').select('status, paymongo_reference, amount, created_at').eq('id', id).maybeSingle();
        if (row == null) return null;
        return {...row, 'payment_status': row['status'], 'estimated_fare': row['amount'], 'payment_method': 'gcash'};
      }
      final kind = BookingKind.values.firstWhere((k) => k.name == type);
      return await _supabase
          .from(kind.tableName)
          .select('payment_status, payment_method, paymongo_reference, estimated_fare, final_fare, created_at${routeCols[type] ?? ''}')
          .eq('id', id)
          .maybeSingle();
    } catch (e, s) {
      AppLog.warn('fetchPaymentReceipt($type, $id) failed', e, s);
      return null;
    }
  }

  /// Calls the `create-payment` Edge Function to pay for a booking using the wallet balance.
  Future<void> payWithWallet(String bookingId, {String bookingType = 'transport'}) async {
    final data = await _invoke(
      'create-payment',
      {'booking_id': bookingId, 'booking_type': bookingType, 'method': 'wallet'},
      fallbackError: 'Could not pay with wallet',
    );
    if (data['paid_from_wallet'] != true) throw Exception('Could not pay with wallet');
  }

  /// Invokes an Edge Function and returns its JSON body. A non-2xx reply
  /// throws [FunctionException]; this surfaces the function's own `error`
  /// message (e.g. "Insufficient wallet balance") instead of a raw status.
  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> body, {
    required String fallbackError,
  }) async {
    try {
      final response = await _supabase.functions.invoke(name, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      throw Exception(message ?? fallbackError);
    }
  }

  /// The PayMongo webhook is the source of truth but arrives asynchronously;
  /// nudge `sync-payment-status` (read-only on PayMongo's side) for any
  /// booking still waiting on a GCash payment so a customer who comes back
  /// early isn't stuck on "pending". Fire-and-forget, like the web's
  /// syncPendingPayments() — realtime re-renders once the row changes.
  void syncPendingPayments(Iterable<BookingBase> bookings) {
    for (final b in bookings) {
      if (b.paymentMethod == 'gcash' &&
          b.paymentStatus == 'pending' &&
          b.paymongoReference != null) {
        _supabase.functions.invoke('sync-payment-status', body: {
          'booking_type': b.kind.name,
          'booking_id': b.id,
        }).catchError((Object e) {
          AppLog.warn('sync-payment-status failed for ${b.id}', e);
          return FunctionResponse(status: 0);
        });
      }
    }
  }

  /// The payment-relevant columns of a transport booking, for the receipt
  /// screen. Mirrors the web app's `payment-return.html` fetch.
  Future<TransportPaymentRow?> fetchTransportPaymentRow(String bookingId) async {
    try {
      final row = await _supabase
          .from('transport_bookings')
          .select(
              'payment_status, payment_method, payment_source_id, payment_id, '
              'estimated_fare, final_fare, created_at, pickup_address, destination_address')
          .eq('id', bookingId)
          .maybeSingle();
      if (row == null) return null;
      return TransportPaymentRow.fromJson(row);
    } catch (e, s) {
      AppLog.warn('fetchTransportPaymentRow($bookingId) failed', e, s);
      return null;
    }
  }

  // ── History ───────────────────────────────────────────────────────────

  Future<List<BookingBase>> fetchHistory(
    BookingKind kind,
    String customerId,
  ) async {
    final response = await _supabase
        .from(kind.tableName)
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);

    final bookings = (response as List)
        .map((json) => _bookingFromRow(kind, json))
        .toList();
    syncPendingPayments(bookings);
    return bookings;
  }

  /// Pulls every booking the customer has ever made (all three kinds) and
  /// reduces it to the home-tab summary in one round of queries.
  Future<CustomerHomeSummary> fetchHomeSummary(String customerId) async {
    if (customerId.isEmpty) return const CustomerHomeSummary();

    final all = <BookingBase>[];
    for (final kind in BookingKind.values) {
      final rows = await _supabase
          .from(kind.tableName)
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      for (final json in (rows as List)) {
        all.add(_bookingFromRow(kind, json));
      }
    }
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    syncPendingPayments(all);

    final completed = all.where((b) => b.status == 'completed').toList();
    final spent = completed.fold<double>(
        0, (sum, b) => sum + (b.finalFare ?? b.estimatedFare ?? 0));

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final thisMonth = completed
        .where((b) => !b.createdAt.toLocal().isBefore(monthStart))
        .length;

    BookingBase? active;
    for (final b in all) {
      if (b.status == 'pending' ||
          b.status == 'accepted' ||
          b.status == 'ongoing') {
        active = b;
        break;
      }
    }

    String? riderName;
    String? riderPhone;
    if (active?.riderId != null && active!.riderId!.isNotEmpty) {
      try {
        final rider = await _supabase
            .from('profiles')
            .select('full_name, phone')
            .eq('id', active.riderId!)
            .maybeSingle();
        riderName = rider?['full_name'] as String?;
        riderPhone = rider?['phone'] as String?;
      } catch (e, s) {
        AppLog.warn('fetchHomeSummary: rider profile lookup failed', e, s);
      }
    }

    return CustomerHomeSummary(
      completedTrips: completed.length,
      totalSpent: spent,
      tripsThisMonth: thisMonth,
      activeBooking: active,
      activeBookings: [
        for (final b in all)
          if (b.status == 'pending' || b.status == 'accepted' || b.status == 'ongoing') b,
      ],
      activeRiderName: riderName,
      activeRiderPhone: riderPhone,
    );
  }

  BookingBase _bookingFromRow(BookingKind kind, Map<String, dynamic> json) {
    switch (kind) {
      case BookingKind.transport:
        return TransportBookingModel.fromJson(json);
      case BookingKind.food:
        return FoodDeliveryModel.fromJson(json);
      case BookingKind.parcel:
        return ParcelDeliveryModel.fromJson(json);
      case BookingKind.hauling:
        return HaulingBookingModel.fromJson(json);
    }
  }

  /// The booking_before_update trigger records platform_config's
  /// cancellation fee itself when an accepted booking is cancelled — the
  /// client must never write cancellation_fee (the trigger rejects it).
  Future<void> cancelBooking(BookingBase booking, {String reason = 'Cancelled by customer'}) async {
    await _supabase.from(booking.kind.tableName).update({
      'status': 'cancelled',
      'cancelled_reason': reason,
    }).eq('id', booking.id);
  }

  /// Rates the rider and optionally tips them. A tip can only be recorded
  /// once the trip is completed (the trigger adds it to the rider's payout
  /// then) — same flow as the web's rating modal.
  Future<void> submitRating(
    BookingBase booking, {
    required int stars,
    String? comment,
    double? tip,
  }) async {
    final updates = <String, dynamic>{
      'rating': stars,
      'review': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
      // Omitted entirely without a tip — the trigger rejects tip_amount <= 0.
      if (tip != null && tip > 0) 'tip_amount': _round2(tip),
    };
    await _supabase.from(booking.kind.tableName).update(updates).eq('id', booking.id);

    if (booking.riderId != null && booking.riderId!.isNotEmpty) {
      await _supabase.from('reviews').insert({
        'customer_id': booking.customerId,
        'rider_id': booking.riderId,
        'booking_type': booking.kind.name,
        'booking_id': booking.id,
        'rating': stars,
        'comment': comment?.trim(),
      });
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final response = await _supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(30);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<int> unreadNotificationsCount(String userId) async {
    final response = await _supabase
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return (response as List).length;
  }

  /// Marks one notification read (opened from the Notifications tab).
  Future<void> markNotificationRead(String id) async {
    await _supabase.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markNotificationsRead(String userId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  // ── Profile ───────────────────────────────────────────────────────────

  Future<ProfileModel> updateProfile({
    required ProfileModel profile,
    required String fullName,
    required String phone,
  }) async {
    await _supabase.from('profiles').update({
      'full_name': fullName.trim(),
      'phone': phone.trim(),
    }).eq('id', profile.id);

    return profile.copyWith(fullName: fullName.trim(), phone: phone.trim());
  }

  Future<String> uploadAvatar({
    required String userId,
    required String filePath,
    required List<int> bytes,
  }) async {
    final ext = filePath.split('.').last.toLowerCase();
    final path = '$userId/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage.from('avatars').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );

    return _supabase.storage.from('avatars').getPublicUrl(path);
  }

  /// Saves a new profile photo. For an approved rider the database holds it
  /// back for admin review (sql/030): the current photo stays in avatar_url
  /// and the new one lands in avatar_pending_url — so read back what stuck.
  Future<ProfileModel> setAvatarUrl(ProfileModel profile, String url) async {
    final row = await _supabase
        .from('profiles')
        .update({'avatar_url': url})
        .eq('id', profile.id)
        .select('avatar_url, avatar_pending_url')
        .single();
    final pending = row['avatar_pending_url'] as String?;
    return profile.copyWith(
      avatarUrl: row['avatar_url'] as String?,
      avatarPendingUrl: pending,
      clearAvatarPending: pending == null,
    );
  }

  // ── Saved Addresses ───────────────────────────────────────────────────

  Future<List<SavedAddressModel>> getSavedAddresses(String userId) async {
    final effectiveUserId = userId.isNotEmpty
        ? userId
        : (_supabase.auth.currentUser?.id ?? '');
    if (effectiveUserId.isEmpty) return [];

    final response = await _supabase
        .from('saved_addresses')
        .select()
        .eq('customer_id', effectiveUserId)
        .order('created_at', ascending: false);
    return response
        .map((json) => SavedAddressModel.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<SavedAddressModel> addSavedAddress({
    required String userId,
    required String label,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final effectiveUserId = userId.isNotEmpty
        ? userId
        : (_supabase.auth.currentUser?.id ?? '');
    if (effectiveUserId.isEmpty) {
      throw const AuthException('User must be signed in to save an address');
    }

    final response = await _supabase.from('saved_addresses').insert({
      'customer_id': effectiveUserId,
      'label': label.trim(),
      'address': address.trim(),
      'lat': latitude,
      'lng': longitude,
    }).select().single();
    return SavedAddressModel.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> deleteSavedAddress(String id) async {
    await _supabase.from('saved_addresses').delete().eq('id', id);
  }

  // ── Wallet ────────────────────────────────────────────────────────────

  Future<WalletModel?> getWallet(String userId) async {
    final response = await _supabase.from('wallets').select().eq('customer_id', userId).maybeSingle();
    if (response == null) return null;
    return WalletModel.fromJson(response);
  }

  Future<List<WalletTransactionModel>> getWalletTransactions(String userId) async {
    final response = await _supabase
        .from('wallet_transactions')
        .select()
        .eq('customer_id', userId)
        .order('created_at', ascending: false);
    return (response as List).map((json) => WalletTransactionModel.fromJson(json)).toList();
  }
}
