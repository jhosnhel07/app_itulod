import 'dart:io' as dart_io;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_log.dart';
import '../../../shared/models/booking_models.dart';

final riderRepositoryProvider = Provider<RiderRepository>((ref) {
  return RiderRepository(SupabaseConfig.client);
});

class RiderEarnings {
  final double today;
  final double week;
  final double month;
  final double averageRating;
  final List<double> last7Days; // oldest → newest

  const RiderEarnings({
    this.today = 0,
    this.week = 0,
    this.month = 0,
    this.averageRating = 0,
    this.last7Days = const [0, 0, 0, 0, 0, 0, 0],
  });
}

/// "Your day at a glance" snapshot for the rider home tab — mirrors the web
/// dashboard's rider home view.
class RiderHomeSnapshot {
  final double earningsToday;
  final int tripsToday;
  final double averageRating;
  final int openRequests;
  final List<BookingBase> activeBookings;

  const RiderHomeSnapshot({
    this.earningsToday = 0,
    this.tripsToday = 0,
    this.averageRating = 0,
    this.openRequests = 0,
    this.activeBookings = const [],
  });

  BookingBase? get primaryActive {
    if (activeBookings.isEmpty) return null;
    return activeBookings.firstWhere(
      (b) => b.status == 'ongoing',
      orElse: () => activeBookings.first,
    );
  }
}

class RiderRepository {
  final SupabaseClient _supabase;

  RiderRepository(this._supabase);

  // ── Online presence ───────────────────────────────────────────────────

  Future<bool> fetchOnlineStatus(String riderId) async {
    try {
      final response = await _supabase
          .from('rider_locations')
          .select('is_online')
          .eq('rider_id', riderId)
          .maybeSingle();
      return (response?['is_online'] as bool?) ?? false;
    } catch (e, s) {
      AppLog.warn('fetchOnlineStatus failed', e, s);
      return false;
    }
  }

  Future<void> setOnlineStatus(String riderId, bool isOnline) async {
    await _supabase
        .from('rider_locations')
        .upsert({'rider_id': riderId, 'is_online': isOnline});
  }

  // ── Home snapshot ─────────────────────────────────────────────────────

  Future<RiderHomeSnapshot> fetchHomeSnapshot(String riderId, double floatAmount) async {
    if (riderId.isEmpty) return const RiderHomeSnapshot();

    final startOfDay = () {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }();

    // Today's payouts.
    var earningsToday = 0.0;
    var tripsToday = 0;
    try {
      final payments = await _supabase
          .from('payments')
          .select('rider_payout, created_at')
          .eq('rider_id', riderId);
      for (final row in (payments as List)) {
        final created =
            DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
        if (created == null || created.isBefore(startOfDay)) continue;
        earningsToday += (row['rider_payout'] as num?)?.toDouble() ?? 0;
        tripsToday++;
      }
    } catch (e, s) {
      AppLog.warn('fetchHomeSnapshot: payments query failed', e, s);
    }

    // Average rating.
    var ratingSum = 0.0;
    var ratingCount = 0;
    try {
      final reviews = await _supabase
          .from('reviews')
          .select('rating')
          .eq('rider_id', riderId);
      for (final row in (reviews as List)) {
        ratingSum += (row['rating'] as num?)?.toDouble() ?? 0;
        ratingCount++;
      }
    } catch (e, s) {
      AppLog.warn('rider reviews query failed', e, s);
    }

    // Open (unassigned, pending) request count + this rider's active bookings.
    var openRequests = 0;
    final active = <BookingBase>[];
    for (final kind in BookingKind.values) {
      var query = _supabase
          .from(kind.tableName)
          .select('id')
          .filter('rider_id', 'is', null)
          .eq('status', 'pending');
          
      if (kind == BookingKind.food) {
        query = query.lte('total_items_price', floatAmount);
      }

      final open = await query;
      openRequests += (open as List).length;

      final mine = await _supabase
          .from(kind.tableName)
          .select()
          .eq('rider_id', riderId)
          .inFilter('status', ['accepted', 'ongoing'])
          .order('created_at', ascending: false);
      active.addAll((mine as List).map((json) => _fromRow(kind, json)));
    }

    return RiderHomeSnapshot(
      earningsToday: earningsToday,
      tripsToday: tripsToday,
      averageRating: ratingCount > 0 ? ratingSum / ratingCount : 0,
      openRequests: openRequests,
      activeBookings: active,
    );
  }

  // ── Requests ──────────────────────────────────────────────────────────

  Future<List<BookingBase>> fetchOpenRequests(double floatAmount) async {
    final results = <BookingBase>[];
    for (final kind in BookingKind.values) {
      var query = _supabase
          .from(kind.tableName)
          .select()
          .filter('rider_id', 'is', null)
          .eq('status', 'pending');
      
      if (kind == BookingKind.food) {
        // Only show food deliveries if the rider has enough float to cover the items price
        query = query.lte('total_items_price', floatAmount);
      }

      final response = await query.order('created_at', ascending: false);
      results.addAll((response as List).map((json) => _fromRow(kind, json)));
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  /// Accepts a booking with a race-safe guard (only if rider_id still null).
  Future<void> acceptBooking(BookingBase booking, String riderId) async {
    await _supabase
        .from(booking.kind.tableName)
        .update({'rider_id': riderId, 'status': 'accepted'})
        .eq('id', booking.id)
        .filter('rider_id', 'is', null);
  }

  // ── Accepted / active bookings ────────────────────────────────────────

  Future<List<BookingBase>> fetchAcceptedBookings(String riderId) async {
    final results = <BookingBase>[];
    for (final kind in BookingKind.values) {
      final response = await _supabase
          .from(kind.tableName)
          .select()
          .eq('rider_id', riderId)
          .inFilter('status', ['accepted', 'ongoing'])
          .order('created_at', ascending: false);
      results.addAll((response as List).map((json) => _fromRow(kind, json)));
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<bool> hasActiveBooking(String riderId) async {
    for (final kind in BookingKind.values) {
      final response = await _supabase
          .from(kind.tableName)
          .select('id')
          .eq('rider_id', riderId)
          .inFilter('status', ['accepted', 'ongoing']).limit(1);
      if ((response as List).isNotEmpty) return true;
    }
    return false;
  }

  /// Advances a booking's status. The client only ever writes `status` —
  /// locking `final_fare`, marking cash as paid, and inserting the `payments`
  /// ledger row (with the platform commission split) are all done server-side
  /// by the `booking_before_update` trigger (migration 005). Writing those
  /// columns from here would now be rejected by that trigger / RLS.
  Future<void> updateStatus(
    BookingBase booking,
    String status, {
    required String riderId,
    String? dropoffPhotoUrl,
  }) async {
    await _supabase
        .from(booking.kind.tableName)
        .update({
          'status': status,
          if (dropoffPhotoUrl != null) 'dropoff_photo_url': dropoffPhotoUrl,
        }).eq('id', booking.id);
  }

  Future<void> cancelAndRematchBooking(BookingBase booking) async {
    await _supabase.from(booking.kind.tableName).update({
      'status': 'pending',
      'rider_id': null,
    }).eq('id', booking.id);
  }

  Future<String> uploadDropoffPhoto(String bookingId, String filePath) async {
    final file = dart_io.File(filePath);
    final ext = filePath.split('.').last;
    final path = 'dropoffs/${bookingId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage.from('deliveries').upload(path, file);
    return _supabase.storage.from('deliveries').getPublicUrl(path);
  }

  Future<void> adjustFoodBill(String bookingId, double actualCost, String receiptPath) async {
    final file = dart_io.File(receiptPath);
    final ext = receiptPath.split('.').last;
    final path = 'receipts/${bookingId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage.from('deliveries').upload(path, file);
    final url = _supabase.storage.from('deliveries').getPublicUrl(path);
    
    await _supabase.from('food_deliveries').update({
      'actual_food_cost': actualCost,
      'receipt_photo_url': url,
    }).eq('id', bookingId);
  }

  Future<void> markItemOutOfStock(String bookingId, int itemIndex) async {
    final response = await _supabase.from('food_deliveries').select('items').eq('id', bookingId).single();
    final items = List<dynamic>.from(response['items'] ?? []);
    if (itemIndex >= 0 && itemIndex < items.length) {
      final item = Map<String, dynamic>.from(items[itemIndex]);
      item['is_out_of_stock'] = true;
      items[itemIndex] = item;
      await _supabase.from('food_deliveries').update({'items': items}).eq('id', bookingId);
    }
  }

  // ── History ───────────────────────────────────────────────────────────

  Future<List<BookingBase>> fetchHistory(BookingKind kind, String riderId) async {
    final response = await _supabase
        .from(kind.tableName)
        .select()
        .eq('rider_id', riderId)
        .inFilter('status', ['completed', 'cancelled', 'expired', 'no_show'])
        .order('created_at', ascending: false);
    return (response as List).map((json) => _fromRow(kind, json)).toList();
  }

  // ── Earnings & ratings ────────────────────────────────────────────────

  Future<RiderEarnings> fetchEarnings(String riderId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: now.weekday % 7));
    final startOfMonth = DateTime(now.year, now.month, 1);

    var today = 0.0, week = 0.0, month = 0.0;
    final daily = List.filled(7, 0.0);
    final cutoff = startOfDay.subtract(const Duration(days: 6));

    final payments = await _supabase
        .from('payments')
        .select('rider_payout, created_at')
        .eq('rider_id', riderId);

    for (final row in (payments as List)) {
      final payout = (row['rider_payout'] as num?)?.toDouble() ?? 0;
      final created = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (created == null) continue;
      final local = created.toLocal();
      if (!local.isBefore(startOfDay)) today += payout;
      if (!local.isBefore(startOfWeek)) week += payout;
      if (!local.isBefore(startOfMonth)) month += payout;
      if (!local.isBefore(cutoff)) {
        final index = local.difference(cutoff).inDays;
        if (index >= 0 && index < 7) daily[index] += payout;
      }
    }

    var ratingSum = 0.0;
    var ratingCount = 0;
    try {
      final reviews = await _supabase
          .from('reviews')
          .select('rating')
          .eq('rider_id', riderId);
      for (final row in (reviews as List)) {
        ratingSum += (row['rating'] as num?)?.toDouble() ?? 0;
        ratingCount++;
      }
    } catch (e, s) {
      AppLog.warn('rider reviews query failed', e, s);
    }

    return RiderEarnings(
      today: today,
      week: week,
      month: month,
      averageRating: ratingCount > 0 ? ratingSum / ratingCount : 0,
      last7Days: daily,
    );
  }

  Future<void> updateFloatAmount(String riderId, double amount) async {
    await _supabase.from('profiles').update({'float_amount': amount}).eq('id', riderId);
  }

  BookingBase _fromRow(BookingKind kind, Map<String, dynamic> json) {
    switch (kind) {
      case BookingKind.transport:
        return TransportBookingModel.fromJson(json);
      case BookingKind.food:
        return FoodDeliveryModel.fromJson(json);
      case BookingKind.parcel:
        return ParcelDeliveryModel.fromJson(json);
    }
  }
}
