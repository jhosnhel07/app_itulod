import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/fare_estimator.dart';
import '../../../shared/models/booking_models.dart';
import '../../../shared/models/profile_model.dart';
import '../../../shared/models/vehicle_model.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(SupabaseConfig.client);
});

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
    }).select().single();

    return TransportBookingModel.fromJson(row);
  }

  /// Best-effort: drops a row into the customer's notifications feed. Never
  /// throws — a missing notification shouldn't fail a completed booking.
  Future<void> notifyBookingComplete({
    required String userId,
    required String title,
    required String message,
  }) async {
    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'is_read': false,
      });
    } catch (_) {}
  }

  Future<void> createFoodBooking({
    required String customerId,
    required VehicleModel vehicle,
    required String restaurantName,
    required String pickupAddress,
    required String deliveryAddress,
    String instructions = '',
  }) async {
    final distanceKm = FareEstimator.simulateDistanceKm(pickupAddress, deliveryAddress);
    final fare = FareEstimator.estimateFare(vehicle, distanceKm);

    await _supabase.from('food_deliveries').insert({
      'customer_id': customerId,
      'restaurant_name': restaurantName.trim(),
      'pickup_address': pickupAddress.trim(),
      'delivery_address': deliveryAddress.trim(),
      'instructions': instructions.trim(),
      'vehicle_id': vehicle.id,
      'distance_km': distanceKm,
      'estimated_fare': double.parse(fare.toStringAsFixed(2)),
      'status': 'pending',
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
  }) async {
    final fare = FareEstimator.estimateFare(
        vehicle, FareEstimator.simulateDistanceKm(senderAddress, receiverAddress));

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
      'estimated_fare': double.parse(fare.toStringAsFixed(2)),
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

  Future<void> cancelBooking(BookingBase booking, {String reason = 'Cancelled by customer'}) async {
    await _supabase.from(booking.kind.tableName).update({
      'status': 'cancelled',
      'cancelled_reason': reason,
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
}
