import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Snapshot shown on the customer home tab — lifetime stats plus whatever
/// booking is currently in flight. Mirrors the web dashboard's "home" view.
class CustomerHomeSummary {
  final int completedTrips;
  final double totalSpent;
  final int tripsThisMonth;
  final BookingBase? activeBooking;
  final String? activeRiderName;
  final String? activeRiderPhone;

  const CustomerHomeSummary({
    this.completedTrips = 0,
    this.totalSpent = 0,
    this.tripsThisMonth = 0,
    this.activeBooking,
    this.activeRiderName,
    this.activeRiderPhone,
  });
}

class CustomerRepository {
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

  Future<TransportBookingModel> createTransportBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String pickupAddress,
    required String destinationAddress,
    required String paymentMethod,
    /// Real kilometres measured from the map pins. Falls back to the
    /// address-hash estimate when the customer typed addresses by hand.
    double? distanceKm,
    double? tipAmount,
    DateTime? scheduledFor,
    String? promoCode,
    List<String>? stops,
  }) async {
    final km = distanceKm ??
        FareEstimator.simulateDistanceKm(pickupAddress, destinationAddress);
    final fare = FareEstimator.estimateFare(vehicle, km);

    final row = await _supabase.from('transport_bookings').insert({
      'customer_id': customerId,
      'vehicle_id': vehicle.id,
      'pickup_address': pickupAddress.trim(),
      'destination_address': destinationAddress.trim(),
      'distance_km': double.parse(km.toStringAsFixed(2)),
      'estimated_fare': double.parse(fare.toStringAsFixed(2)),
      'status': 'pending',
      'payment_method': paymentMethod,
      if (tipAmount != null && tipAmount > 0) 'tip_amount': tipAmount,
      if (scheduledFor != null) 'scheduled_for': scheduledFor.toIso8601String(),
      if (promoCode != null) 'promo_code': promoCode,
    }).select().single();

    if (stops != null && stops.isNotEmpty) {
      final stopRows = [];
      for (var i = 0; i < stops.length; i++) {
        stopRows.add({
          'booking_id': row['id'],
          'stop_order': i + 1,
          'address': stops[i].trim(),
        });
      }
      try {
        await _supabase.from('ride_stops').insert(stopRows);
      } catch (e, s) {
        AppLog.warn('Failed to insert ride stops', e, s);
      }
    }

    if (promoCode != null && promoCode.isNotEmpty) {
      try {
        await _supabase.functions.invoke('redeem-promo', body: {
          'code': promoCode,
          'booking_type': 'transport',
          'booking_id': row['id'],
        });
        final updatedRow = await _supabase.from('transport_bookings').select().eq('id', row['id']).single();
        return TransportBookingModel.fromJson(updatedRow);
      } catch (e, s) {
        AppLog.warn('Failed to redeem promo on new booking', e, s);
      }
    }

    return TransportBookingModel.fromJson(row);
  }

  Future<void> createFoodBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String restaurantName,
    required String pickupAddress,
    required String deliveryAddress,
    String instructions = '',
    /// Real kilometres from the map pins; falls back to the address-hash
    /// estimate when unavailable.
    double? distanceKm,
    double? tipAmount,
    DateTime? scheduledFor,
    String? promoCode,
    String? restaurantId,
    List<dynamic>? items,
    double? totalItemsPrice,
  }) async {
    final km = distanceKm ??
        FareEstimator.simulateDistanceKm(pickupAddress, deliveryAddress);
    final fare = FareEstimator.estimateFare(vehicle, km);

    await _supabase.from('food_deliveries').insert({
      'customer_id': customerId,
      'restaurant_name': restaurantName.trim(),
      'pickup_address': pickupAddress.trim(),
      'delivery_address': deliveryAddress.trim(),
      'instructions': instructions.trim(),
      'vehicle_id': vehicle.id,
      'distance_km': double.parse(km.toStringAsFixed(2)),
      'estimated_fare': double.parse(fare.toStringAsFixed(2)),
      'status': 'pending',
      if (tipAmount != null && tipAmount > 0) 'tip_amount': tipAmount,
      if (scheduledFor != null) 'scheduled_for': scheduledFor.toIso8601String(),
      if (promoCode != null) 'promo_code': promoCode,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (items != null) 'items': items,
      if (totalItemsPrice != null) 'total_items_price': totalItemsPrice,
    });
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
    /// Real kilometres from the map pins; falls back to the address-hash
    /// estimate when unavailable.
    double? distanceKm,
    double? tipAmount,
    DateTime? scheduledFor,
    bool isRoundTrip = false,
    double codAmount = 0.0,
    String? promoCode,
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
      'is_round_trip': isRoundTrip,
      'cod_amount': codAmount,
      if (tipAmount != null && tipAmount > 0) 'tip_amount': tipAmount,
      if (scheduledFor != null) 'scheduled_for': scheduledFor.toIso8601String(),
      if (promoCode != null) 'promo_code': promoCode,
    });
  }

  Future<Map<String, dynamic>?> validatePromoCode(String code) async {
    try {
      final res = await _supabase
          .from('promo_codes')
          .select()
          .eq('code', code.trim().toUpperCase())
          .eq('is_active', true)
          .maybeSingle();
      if (res == null) return null;
      
      final expiresAtStr = res['expires_at'] as String?;
      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) return null;
      }
      return res;
    } catch (e) {
      return null;
    }
  }

  Future<void> applyReferralCode(String code) async {
    final response = await _supabase.functions.invoke(
      'apply-referral-code',
      body: {'code': code},
    );
    final data = response.data;
    if (response.status != 200 || (data is Map && data['error'] != null)) {
      throw Exception(data is Map ? data['error'] : 'Could not apply referral code');
    }
  }

  Future<void> createDispute({
    required String bookingId,
    required String bookingType,
    required String reason,
  }) async {
    final uid = _supabase.auth.currentUser!.id;
    await _supabase.from('disputes').insert({
      'booking_id': bookingId,
      'booking_type': bookingType,
      'customer_id': uid,
      'reason': reason,
      'status': 'pending',
    });
  }

  // ── Payments ──────────────────────────────────────────────────────────

  /// Calls the `paymongo-create-gcash-source` Edge Function and returns the
  /// PayMongo hosted checkout URL for the given transport booking.
  Future<String> createGcashCheckoutUrl(String bookingId) async {
    final response = await _supabase.functions.invoke(
      'paymongo-create-gcash-source',
      body: {'booking_id': bookingId},
    );

    final data = response.data;
    if (response.status != 200 || data is! Map || data['checkout_url'] == null) {
      final error = data is Map ? data['error'] : null;
      throw Exception(error ?? 'Could not start GCash checkout');
    }
    return data['checkout_url'] as String;
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

    return (response as List).map((json) {
      switch (kind) {
        case BookingKind.transport:
          return TransportBookingModel.fromJson(json) as BookingBase;
        case BookingKind.food:
          return FoodDeliveryModel.fromJson(json);
        case BookingKind.parcel:
          return ParcelDeliveryModel.fromJson(json);
      }
    }).toList();
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
    }
  }

  Future<void> cancelBooking(BookingBase booking, {String reason = 'Cancelled by customer'}) async {
    final bool riderAccepted = booking.status == 'accepted' || booking.status == 'ongoing';
    final double cancelFee = riderAccepted ? 50.0 : 0.0; // 50 PHP if already accepted

    await _supabase.from(booking.kind.tableName).update({
      'status': 'cancelled',
      'cancelled_reason': reason,
      if (cancelFee > 0) 'cancellation_fee': cancelFee,
    }).eq('id', booking.id);
  }

  Future<void> submitRating(
    BookingBase booking, {
    required int stars,
    String? comment,
  }) async {
    final updates = <String, dynamic>{
      'rating': stars,
      'review': comment?.trim().isNotEmpty == true ? comment!.trim() : null,
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

  Future<ProfileModel> setAvatarUrl(ProfileModel profile, String url) async {
    await _supabase.from('profiles').update({
      'avatar_url': url,
    }).eq('id', profile.id);
    return profile.copyWith(avatarUrl: url);
  }

  // ── Saved Addresses ───────────────────────────────────────────────────

  Future<List<SavedAddressModel>> getSavedAddresses(String userId) async {
    final response = await _supabase
        .from('saved_addresses')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (response as List).map((json) => SavedAddressModel.fromJson(json)).toList();
  }

  Future<SavedAddressModel> addSavedAddress({
    required String userId,
    required String label,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _supabase.from('saved_addresses').insert({
      'user_id': userId,
      'label': label.trim(),
      'address': address.trim(),
      'latitude': latitude,
      'longitude': longitude,
    }).select().single();
    return SavedAddressModel.fromJson(response);
  }

  Future<void> deleteSavedAddress(String id) async {
    await _supabase.from('saved_addresses').delete().eq('id', id);
  }

  // ── Wallet ────────────────────────────────────────────────────────────

  Future<WalletModel?> getWallet(String userId) async {
    final response = await _supabase.from('wallets').select().eq('user_id', userId).maybeSingle();
    if (response == null) return null;
    return WalletModel.fromJson(response);
  }

  Future<WalletModel> createWallet(String userId) async {
    final response = await _supabase.from('wallets').insert({
      'user_id': userId,
      'balance': 0,
    }).select().single();
    return WalletModel.fromJson(response);
  }

  Future<List<WalletTransactionModel>> getWalletTransactions(String userId) async {
    final response = await _supabase
        .from('wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (response as List).map((json) => WalletTransactionModel.fromJson(json)).toList();
  }
}
