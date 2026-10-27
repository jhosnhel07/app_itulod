import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/booking_models.dart';

/// One of the customer's promos (web sql/053 my_promos()): claimed ones with
/// a status — ready / used / expired / ended / full — plus sent ones still to
/// claim ('unclaimed'). Web twin: js/promos.js.
class MyPromo {
  final String id;
  final String code;
  final String title;
  final String summary;
  final String discountType; // percent | flat
  final double discountValue;
  final double minFare;
  final List<String> services; // booking kinds: transport / food / parcel / hauling
  final DateTime? expiresAt;
  final DateTime? usedAt;
  final String? usedBookingType;
  final String status;

  const MyPromo({
    required this.id,
    required this.code,
    required this.title,
    required this.summary,
    required this.discountType,
    required this.discountValue,
    this.minFare = 0,
    this.services = const ['transport', 'food', 'parcel', 'hauling'],
    this.expiresAt,
    this.usedAt,
    this.usedBookingType,
    required this.status,
  });

  factory MyPromo.fromJson(Map<String, dynamic> j) => MyPromo(
        id: j['id'] as String,
        code: j['code'] as String? ?? '',
        title: j['title'] as String? ?? j['code'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        discountType: j['discount_type'] as String? ?? 'percent',
        discountValue: (j['discount_value'] as num?)?.toDouble() ?? 0,
        minFare: (j['min_fare'] as num?)?.toDouble() ?? 0,
        services: (j['services'] as List?)?.cast<String>() ?? const ['transport', 'food', 'parcel', 'hauling'],
        expiresAt: DateTime.tryParse(j['expires_at']?.toString() ?? ''),
        usedAt: DateTime.tryParse(j['used_at']?.toString() ?? ''),
        usedBookingType: j['used_booking_type'] as String?,
        status: j['status'] as String? ?? 'ready',
      );

  bool get isReady => status == 'ready';
  bool worksFor(BookingKind kind) => services.contains(kind.name);

  /// What it takes off [fare] — never below the minimum fare (redeem-promo).
  double discountFor(double fare, {double fareMin = 20}) {
    final raw = discountType == 'percent' ? (fare * discountValue / 100 * 100).roundToDouble() / 100 : discountValue;
    final capped = raw < fare - fareMin ? raw : fare - fareMin;
    return capped <= 0 ? 0 : (capped * 100).roundToDouble() / 100;
  }

  /// Can be picked for this booking: claimed, right service, total big enough.
  bool usableOn(BookingKind kind, double fare) => isReady && worksFor(kind) && fare >= minFare && discountFor(fare) > 0;

  /// "₱30" / "10%" on the ticket.
  String get badge => discountType == 'percent'
      ? '${discountValue.toStringAsFixed(discountValue % 1 == 0 ? 0 : 1)}%'
      : '₱${discountValue.toStringAsFixed(discountValue % 1 == 0 ? 0 : 2)}';
}

final promoRepositoryProvider = Provider<PromoRepository>((ref) => PromoRepository(SupabaseConfig.client));

/// The signed-in customer's promos, refreshed when one is claimed or used.
final myPromosProvider = FutureProvider.autoDispose<List<MyPromo>>((ref) {
  return ref.watch(promoRepositoryProvider).fetchMyPromos();
});

class PromoRepository {
  final SupabaseClient _supabase;
  PromoRepository(this._supabase);

  Future<List<MyPromo>> fetchMyPromos() async {
    final rows = await _supabase.rpc('my_promos');
    return (rows as List).map((r) => MyPromo.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Claims by id (from its notification) or by a typed code; returns the code.
  Future<String> claim({String? id, String? code}) async {
    try {
      final rows = await _supabase.rpc('claim_promo', params: {
        'p_promo': id,
        'p_code': code?.trim(),
      });
      final list = rows as List;
      return list.isEmpty ? (code ?? '') : (list.first as Map)['code'] as String;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Applies the picked promo to a booking just placed (redeem-promo, any
  /// service in the promo's list). Returns the discount.
  Future<double> redeem({required String code, required BookingKind kind, required String bookingId}) async {
    try {
      final res = await _supabase.functions.invoke('redeem-promo', body: {
        'code': code,
        'booking_type': kind.name,
        'booking_id': bookingId,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      return ((data as Map)['discount_amount'] as num?)?.toDouble() ?? 0;
    } on FunctionException catch (e) {
      final details = e.details;
      throw Exception(details is Map && details['error'] != null ? details['error'] : 'That promo could not be applied.');
    }
  }
}
