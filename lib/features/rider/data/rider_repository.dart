import 'dart:typed_data';
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
  /// Every paid trip, newest first (web: Earnings records).
  final List<EarningRecord> records;

  const RiderEarnings({
    this.today = 0,
    this.week = 0,
    this.month = 0,
    this.averageRating = 0,
    this.last7Days = const [0, 0, 0, 0, 0, 0, 0],
    this.records = const [],
  });
}

/// One paid trip: what the customer paid, iTULOD's commission and the
/// rider's share, and how it was paid (cash / gcash / wallet).
class EarningRecord {
  final String method;
  final String bookingType;
  final double amount;
  final double commission;
  final double payout;
  final DateTime createdAt;

  const EarningRecord({
    required this.method,
    required this.bookingType,
    required this.amount,
    required this.commission,
    required this.payout,
    required this.createdAt,
  });

  /// A cancellation / no-show fee goes to the rider whole (no commission).
  bool get isFee => commission == 0 && amount == payout;
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

/// Commission the rider owes on cash trips vs the admin's limit
/// (sql/043 rider_debt_status). Over the limit, the rider can't accept jobs.
class RiderDebt {
  final double owed;
  final double limit;
  final bool blocked;
  const RiderDebt({this.owed = 0, this.limit = 0, this.blocked = false});
}

class RiderBalance {
  final double onlineEarnings;
  final double cashCommission;
  final double payoutsMade;
  final double collectionsMade;
  /// Positive = iTULOD owes the rider; negative = the rider owes iTULOD.
  final double net;
  final double codUnremitted;

  const RiderBalance({
    required this.onlineEarnings,
    required this.cashCommission,
    required this.payoutsMade,
    required this.collectionsMade,
    required this.net,
    required this.codUnremitted,
  });

  factory RiderBalance.fromJson(Map<String, dynamic> j) {
    double n(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return RiderBalance(
      onlineEarnings: n('online_earnings'),
      cashCommission: n('cash_commission'),
      payoutsMade: n('payouts_made'),
      collectionsMade: n('collections_made'),
      net: n('net'),
      codUnremitted: n('cod_unremitted'),
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

  /// Latest rider application — the web's "Vehicle info" tab.
  Future<Map<String, dynamic>?> fetchApplication(String riderId) async {
    return await _supabase
        .from('rider_applications')
        .select()
        .eq('rider_id', riderId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  // ── Request visibility ────────────────────────────────────────────────

  /// Open (unassigned, pending) requests for [kind]. A scheduled ride stays
  /// hidden until 30 minutes before pickup — same rule as the web's
  /// loadRequests() (food/parcel can't be scheduled).
  PostgrestFilterBuilder<List<Map<String, dynamic>>> _openQuery(
    BookingKind kind, {
    String columns = '*',
  }) {
    var q = _supabase
        .from(kind.tableName)
        .select(columns)
        .filter('rider_id', 'is', null)
        .eq('status', 'pending');
    // Rides and hauling can be scheduled ahead; food/parcel can't. Hauling
    // jobs only reach riders with a Van/Pickup/Truck (RLS is_hauling_rider()).
    if (kind == BookingKind.transport || kind == BookingKind.hauling) {
      final visibleBy =
          DateTime.now().add(const Duration(minutes: 30)).toUtc().toIso8601String();
      q = q.or('scheduled_for.is.null,scheduled_for.lte.$visibleBy');
    }
    return q;
  }

  // ── Home snapshot ─────────────────────────────────────────────────────

  Future<RiderHomeSnapshot> fetchHomeSnapshot(String riderId) async {
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
      final open = await _openQuery(kind, columns: 'id');
      openRequests += open.length;

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

  /// Every open request, like the web. Food orders above the rider's float
  /// are still listed — the requests tab flags them so the rider knows they'd
  /// need more cash on hand to buy the order.
  Future<List<BookingBase>> fetchOpenRequests() async {
    final results = <BookingBase>[];
    for (final kind in BookingKind.values) {
      final response = await _openQuery(kind).order('created_at', ascending: false);
      results.addAll(response.map((json) => _fromRow(kind, json)));
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  /// Accepts a booking with a race-safe guard (only if rider_id still null).
  Future<void> acceptBooking(BookingBase booking, String riderId) async {
    final rows = await _supabase
        .from(booking.kind.tableName)
        .update({'rider_id': riderId, 'status': 'accepted'})
        .eq('id', booking.id)
        .filter('rider_id', 'is', null)
        .select('id');
    // Zero rows = another rider claimed it first (or it expired/cancelled).
    if (rows.isEmpty) throw Exception('This booking was just taken or is no longer available.');
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
  }) async {
    // A ride paid online can't start or finish until PayMongo confirmed it —
    // same guard as the web's updateStatus().
    if (booking.kind == BookingKind.transport &&
        (status == 'ongoing' || status == 'completed')) {
      final current = await _supabase
          .from(booking.kind.tableName)
          .select('payment_method, payment_status')
          .eq('id', booking.id)
          .single();
      final method = current['payment_method'] as String?;
      if (method != null && method != 'cash' && current['payment_status'] != 'paid') {
        throw Exception(
            "Customer's ${method == 'gcash' ? 'GCash' : method} payment hasn't gone through yet.");
      }
    }
    await _supabase
        .from(booking.kind.tableName)
        .update({'status': status}).eq('id', booking.id);
  }

  /// Can't make it after accepting — hand the job back to the pool (allowed
  /// only before the trip starts; the trigger resets the grace period).
  Future<void> releaseBooking(BookingBase booking) async {
    await _supabase.from(booking.kind.tableName).update({
      'status': 'pending',
      'rider_id': null,
    }).eq('id', booking.id);
  }

  /// Uploads a proof-of-delivery photo to `delivery-proof/<riderId>/…` (the
  /// only folder the storage policy lets this rider write). Returns the public
  /// URL; [saveDeliveryProof] records it on the booking.
  Future<String> uploadDeliveryProof({
    required String riderId,
    required BookingBase booking,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final path =
        '$riderId/${booking.kind.name}-${booking.id}-${DateTime.now().millisecondsSinceEpoch}${_ext(fileName)}';
    await _supabase.storage.from('delivery-proof').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: _mime(fileName)),
        );
    return _supabase.storage.from('delivery-proof').getPublicUrl(path);
  }

  /// Records the proof-of-delivery photo on a food/parcel/hauling booking.
  /// It's its own step: "Mark complete" unlocks once it's saved (and the
  /// database refuses to complete a delivery without it — web sql/031).
  Future<void> saveDeliveryProof(BookingBase booking, String url) async {
    await _supabase
        .from(booking.kind.tableName)
        .update({'delivery_proof_url': url}).eq('id', booking.id);
  }

  /// Food: the photo of the receipt (`receipts/<riderId>/…`), taken after
  /// buying the order. It unlocks "Start Trip" (the database refuses to start
  /// without it — web sql/050) and the customer sees it in booking details.
  /// The total itself is fixed: what the customer booked.
  Future<void> saveFoodReceipt({
    required String riderId,
    required FoodDeliveryModel booking,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final path = '$riderId/receipt-${booking.id}-${DateTime.now().millisecondsSinceEpoch}${_ext(fileName)}';
    await _supabase.storage.from('receipts').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: _mime(fileName)),
        );
    final url = _supabase.storage.from('receipts').getPublicUrl(path);
    await _supabase.from('food_deliveries').update({'receipt_photo_url': url}).eq('id', booking.id);
  }

  /// The item's price comes off the order's total (refunded to the
  /// customer's wallet if they already paid online) — web sql/050.
  Future<void> markItemOutOfStock(String orderItemId) async {
    final rows = await _supabase
        .from('food_order_items')
        .update({'is_out_of_stock': true})
        .eq('id', orderItemId)
        .select('id');
    if (rows.isEmpty) throw Exception('Could not update that item.');
  }

  /// Multi-stop rides: the assigned rider marks the next stop reached.
  Future<void> markStopArrived(String stopId) async {
    await _supabase
        .from('ride_stops')
        .update({'arrived_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', stopId);
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot).toLowerCase() : '.jpg';
  }

  static String _mime(String name) {
    switch (_ext(name)) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
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
        .select('rider_payout, created_at, method, amount, platform_commission, booking_type, status')
        .eq('rider_id', riderId);

    final records = <EarningRecord>[];
    for (final row in (payments as List)) {
      final payout = (row['rider_payout'] as num?)?.toDouble() ?? 0;
      final created = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (created == null) continue;
      final local = created.toLocal();
      if (row['status'] == 'paid') {
        records.add(EarningRecord(
          method: row['method'] as String? ?? '',
          bookingType: row['booking_type'] as String? ?? '',
          amount: (row['amount'] as num?)?.toDouble() ?? 0,
          commission: (row['platform_commission'] as num?)?.toDouble() ?? 0,
          payout: payout,
          createdAt: local,
        ));
      }
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
      records: records..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  /// Balance with iTULOD (sql/024 rider_balance): GCash/wallet fares owed to
  /// the rider minus commission owed on cash trips, net of settlements.
  Future<RiderBalance?> fetchBalance() async {
    try {
      final rows = await _supabase.rpc('rider_balance');
      if (rows is! List || rows.isEmpty) return null;
      return RiderBalance.fromJson(Map<String, dynamic>.from(rows.first as Map));
    } catch (e, s) {
      AppLog.warn('rider_balance failed', e, s);
      return null;
    }
  }

  Future<RiderDebt> fetchDebtStatus() async {
    try {
      final rows = await _supabase.rpc('rider_debt_status');
      if (rows is! List || rows.isEmpty) return const RiderDebt();
      final r = Map<String, dynamic>.from(rows.first as Map);
      return RiderDebt(
        owed: (r['owed'] as num?)?.toDouble() ?? 0,
        limit: (r['debt_limit'] as num?)?.toDouble() ?? 0,
        blocked: r['blocked'] == true,
      );
    } catch (e, s) {
      AppLog.warn('rider_debt_status failed', e, s);
      return const RiderDebt();
    }
  }

  /// Parcel COD: the rider handed the collected cash to the sender.
  Future<void> markCodRemitted(String parcelId) async {
    await _supabase
        .from('parcel_deliveries')
        .update({'cod_remitted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', parcelId);
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
      case BookingKind.hauling:
        return HaulingBookingModel.fromJson(json);
    }
  }
}
