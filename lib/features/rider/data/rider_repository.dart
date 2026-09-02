import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
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

class RiderRepository {
  final SupabaseClient _supabase;

  RiderRepository(this._supabase);

  // ── Requests ──────────────────────────────────────────────────────────

  Future<List<BookingBase>> fetchOpenRequests() async {
    final results = <BookingBase>[];
    for (final kind in BookingKind.values) {
      final response = await _supabase
          .from(kind.tableName)
          .select()
          .filter('rider_id', 'is', null)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
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

  Future<void> updateStatus(
    BookingBase booking,
    String status, {
    required String riderId,
  }) async {
    final updates = <String, dynamic>{'status': status};

    if (status == 'completed') {
      final fare = booking.finalFare ?? booking.estimatedFare ?? 0;
      updates['final_fare'] = double.parse(fare.toStringAsFixed(2));

      // Cash on delivery/collection: rider collects and marks paid.
      final method = booking.paymentMethod ?? 'cash';
      if (method == 'cash') {
        updates['payment_status'] = 'paid';
      }

      await _supabase.from(booking.kind.tableName).update(updates).eq('id', booking.id);

      // Record the payment ledger entry.
      final commission = double.parse((fare * 0.15).toStringAsFixed(2));
      try {
        await _supabase.from('payments').insert({
          'customer_id': booking.customerId,
          'rider_id': riderId,
          'booking_type': booking.kind.name,
          'booking_id': booking.id,
          'amount': double.parse(fare.toStringAsFixed(2)),
          'platform_commission': commission,
          'rider_payout': double.parse((fare - commission).toStringAsFixed(2)),
          'method': method == 'cash' ? 'cash' : method,
          'status': 'paid',
        });
      } catch (_) {
        // Ledger insert is non-fatal — booking completion already succeeded.
      }
      return;
    }

    await _supabase.from(booking.kind.tableName).update(updates).eq('id', booking.id);
  }

  // ── History ───────────────────────────────────────────────────────────

  Future<List<BookingBase>> fetchHistory(BookingKind kind, String riderId) async {
    final response = await _supabase
        .from(kind.tableName)
        .select()
        .eq('rider_id', riderId)
        .inFilter('status', ['completed', 'cancelled'])
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
    } catch (_) {}

    return RiderEarnings(
      today: today,
      week: week,
      month: month,
      averageRating: ratingCount > 0 ? ratingSum / ratingCount : 0,
      last7Days: daily,
    );
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
