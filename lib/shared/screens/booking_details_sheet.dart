import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_typography.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/fare_estimator.dart';
import '../../core/utils/formatters.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/customer/data/customer_repository.dart';
import '../../features/rider/presentation/screens/vehicle_documents_screen.dart' show riderDocPath;
import '../../features/customer/presentation/screens/booking_confirmation_screen.dart'
    show paymentMethodLabel;
import '../models/booking_models.dart';
import '../models/profile_model.dart' show UserRole;
import '../models/vehicle_model.dart';
import '../providers/booking_extras_providers.dart';
import '../widgets/booking_route_map.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/status_badge.dart';

typedef RiderBookingView = ({Map<String, dynamic>? customer, Map<String, dynamic>? earn});

/// For the rider of a booking (or one looking at a waiting request): the
/// customer — name, photo, bookings; phone while the trip is on — and the
/// earnings (web sql/047 booking_customer / rider_booking_earnings). Keyed by
/// (type, id, withCustomer).
final riderBookingViewProvider =
    FutureProvider.autoDispose.family<RiderBookingView, (String, String, bool)>((ref, key) async {
  final (type, id, withCustomer) = key;
  Future<Map<String, dynamic>?> first(String fn) async {
    try {
      final rows = await SupabaseConfig.client.rpc(fn, params: {'p_type': type, 'p_id': id}) as List;
      return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
    } catch (e, s) {
      AppLog.warn('riderBookingView: $fn failed', e, s);
      return null;
    }
  }
  return (customer: withCustomer ? await first('booking_customer') : null, earn: await first('rider_booking_earnings'));
});

/// The rider's booking details (Requests, Trip, History): the customer, the
/// full order and what you earn — BookingDetailsSheet shows the rider view
/// when a rider opens it.
Future<void> showRiderBookingDetails(BuildContext context, BookingBase booking) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BookingDetailsSheet(booking: booking),
  );
}

/// Bottom sheet mirroring the web app's booking-details modal
/// (js/bookingDetails.js): route + stops + map with live rider tracking,
/// order items, fare breakdown, vehicle, rider and their documents, proof of
/// delivery, and the chat thread.
class BookingDetailsSheet extends ConsumerStatefulWidget {
  final BookingBase booking;
  /// Optional actions rendered under the details (cancel / rate buttons).
  final List<Widget> actions;

  const BookingDetailsSheet({
    super.key,
    required this.booking,
    this.actions = const [],
  });

  @override
  ConsumerState<BookingDetailsSheet> createState() => _BookingDetailsSheetState();
}

class _BookingDetailsSheetState extends ConsumerState<BookingDetailsSheet> {
  Map<String, dynamic>? _riderProfile;
  Map<String, dynamic>? _riderApplication;
  Map<String, dynamic>? _vehicle;
  List<int> _riderRatings = const [];
  bool _loadingRider = true;
  bool _showMap = false;
  /// A finished trip only offers View chat when there was a chat.
  bool _hadChat = false;

  bool get _asRider => ref.read(authNotifierProvider).profile?.role == UserRole.rider;
  bool get _myJob => _asRider && b.riderId == ref.read(authNotifierProvider).profile?.id;
  bool get _openRequest => _asRider && !b.hasRider && b.status == 'pending';

  /// The rider's own view (web sql/047): the customer (once accepted) and the earnings.
  RiderBookingView get _riderView => _myJob || _openRequest
      ? ref.watch(riderBookingViewProvider((b.kind.name, b.id, _myJob))).valueOrNull ?? const (customer: null, earn: null)
      : const (customer: null, earn: null);
  Map<String, dynamic>? get _customer => _riderView.customer;
  Map<String, dynamic>? get _earn => _riderView.earn;

  BookingBase get b => widget.booking;

  /// Live tracking makes sense only while a rider is on the way / on the
  /// trip, and only for the customer (the rider has their own Trip tab).
  bool get _liveTrackable =>
      b.canSendChat && ref.read(authNotifierProvider).profile?.id == b.customerId;

  @override
  void initState() {
    super.initState();
    _showMap = _liveTrackable;
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(customerRepositoryProvider);
    final riderId = b.riderId;
    final vehicleId = b.vehicleId;
    try {
      final results = await Future.wait([
        riderId == null || riderId.isEmpty
            ? Future<Map<String, dynamic>?>.value(null)
            : SupabaseConfig.client
                .from('profiles')
                .select('full_name, phone, avatar_url')
                .eq('id', riderId)
                .maybeSingle(),
        riderId == null || riderId.isEmpty
            ? Future<Map<String, dynamic>?>.value(null)
            : repo.fetchRiderApplication(riderId),
        vehicleId == null || vehicleId.isEmpty
            ? Future<Map<String, dynamic>?>.value(null)
            : repo.fetchVehicle(vehicleId),
      ]);
      // Rider's average rating for the rider card (reviews are readable by
      // any signed-in user).
      var ratings = const <int>[];
      if (riderId != null && riderId.isNotEmpty) {
        try {
          final rows = await SupabaseConfig.client
              .from('reviews')
              .select('rating')
              .eq('rider_id', riderId)
              .limit(500);
          ratings = [
            for (final r in rows as List) (r['rating'] as num?)?.toInt() ?? 0
          ].where((v) => v > 0).toList();
        } catch (e, s) {
          AppLog.warn('BookingDetailsSheet: ratings lookup failed', e, s);
        }
      }
      var hadChat = false;
      if (riderId != null && riderId.isNotEmpty && !b.canSendChat) {
        try {
          final rows = await SupabaseConfig.client
              .from('booking_messages')
              .select('id')
              .eq('booking_type', b.kind.name)
              .eq('booking_id', b.id)
              .limit(1);
          hadChat = (rows as List).isNotEmpty;
        } catch (e, s) {
          AppLog.warn('BookingDetailsSheet: chat lookup failed', e, s);
        }
      }
      if (!mounted) return;
      setState(() {
        _hadChat = hadChat;
        _riderProfile = results[0];
        _riderApplication = results[1];
        _vehicle = results[2];
        _riderRatings = ratings;
      });
    } catch (e, s) {
      AppLog.warn('BookingDetailsSheet: lookup failed', e, s);
    }
    if (mounted) setState(() => _loadingRider = false);
  }

  @override
  Widget build(BuildContext context) {
    final stopsAsync = b.kind == BookingKind.transport
        ? ref.watch(rideStopsProvider(b.id))
        : const AsyncValue<List<RideStop>>.data([]);
    final stops = stopsAsync.valueOrNull ?? const <RideStop>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _header(),
                    const SizedBox(height: 16),
                    if (_statusNotice() != null) ...[
                      _noticeBanner(_statusNotice()!),
                      const SizedBox(height: 16),
                    ],
                    // The rider sees the customer and their earnings instead of
                    // their own card, vehicle and documents.
                    _asRider ? _customerSection() : _riderSection(),
                    _routeSection(stops, stopsAsync.isLoading),
                    ..._kindSpecific(),
                    _asRider ? _earningsSection() : _fareSection(),
                    if (!_asRider) _vehicleSection(),
                    if (!_asRider) _documentsSection(),
                    _proofSection(),
                    if (b.cancelledReason != null && b.cancelledReason!.isNotEmpty)
                      _section('Cancellation', [
                        Text(b.cancelledReason!, style: AppTypography.body.copyWith(color: AppColors.danger)),
                      ]),
                    if (b.rating != null)
                      _section(_asRider ? 'Customer rated you' : 'Rating', [
                        Row(
                          children: List.generate(
                            b.rating!,
                            (_) => const Icon(Icons.star, size: 18, color: Colors.amber),
                          ),
                        ),
                        if (b.review != null && b.review!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(b.review!, style: AppTypography.body),
                        ],
                      ]),
                  ],
                ),
              ),
              if (widget.actions.isNotEmpty)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.actions,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Header: kind + status, big fare, progress timeline ───────────────

  Widget _header() {
    final fare = b.finalFare ?? b.estimatedFare;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary50, AppColors.primary50.withValues(alpha: 0)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(b.kind.label.toUpperCase(),
                    style: AppTypography.overline.copyWith(color: AppColors.primary, letterSpacing: 0.8)),
              ),
              const Spacer(),
              StatusBadge(status: b.status),
            ],
          ),
          const SizedBox(height: 10),
          Text('${b.pickupLine} → ${b.dropoffLine}', style: AppTypography.h3),
          const SizedBox(height: 2),
          Text(Formatters.date(b.createdAt), style: AppTypography.caption),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          (_asRider && _earn != null
                                  ? (_earn!['is_final'] == true ? 'You earned' : 'You earn')
                                  : 'Total')
                              .toUpperCase(),
                          style: AppTypography.overline.copyWith(color: AppColors.neutral500, letterSpacing: 0.6)),
                      const SizedBox(height: 2),
                      Text(
                          _asRider && _earn != null
                              ? Formatters.currency((_earn!['payout'] as num).toDouble())
                              : fare != null ? Formatters.currency(fare) : '—',
                          key: const Key('details-hero-amount'),
                          style: AppTypography.display.copyWith(fontSize: 28)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.neutral50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_paymentIcon(b.paymentMethod), size: 15, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(paymentMethodLabel(b.paymentMethod),
                              style: AppTypography.bodyBold.copyWith(fontSize: 13)),
                        ],
                      ),
                    ),
                    if (b.paymentStatus != null) ...[
                      const SizedBox(height: 6),
                      StatusBadge(status: b.paymentStatus!, fontSize: 10),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _BookingTimeline(booking: b),
        ],
      ),
    );
  }

  IconData _paymentIcon(String? method) {
    switch (method) {
      case 'gcash':
        return Icons.phone_iphone_rounded;
      case 'wallet':
        return Icons.account_balance_wallet_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  // ── Sections ──────────────────────────────────────────────────────────

  Widget _routeSection(List<RideStop> stops, bool stopsLoading) {
    return _section('Route', [
      _RouteLine(
        from: b.pickupLine,
        to: b.dropoffLine,
        stops: [for (final s in stops) '${s.arrived ? '✓ ' : ''}Stop ${s.stopOrder}: ${s.address}'],
      ),
      const SizedBox(height: 6),
      if (b.distanceKm != null) _detailRow('Distance', Formatters.distance(b.distanceKm)),
      if (b is TransportBookingModel)
        _detailRow('Passengers', '${(b as TransportBookingModel).passengers}'),
      if (b is TransportBookingModel && (b as TransportBookingModel).scheduledFor != null)
        _detailRow('Scheduled for', Formatters.date((b as TransportBookingModel).scheduledFor!)),
      if (b is HaulingBookingModel && (b as HaulingBookingModel).scheduledFor != null)
        _detailRow('Scheduled for', Formatters.date((b as HaulingBookingModel).scheduledFor!)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showMap = !_showMap),
          icon: Icon(_showMap ? Icons.expand_less : Icons.map_outlined, size: 18),
          label: Text(_showMap
              ? 'Hide map'
              : _liveTrackable
                  ? 'Track rider on map'
                  : 'View route on map'),
        ),
      ),
      if (_showMap && !stopsLoading)
        BookingRouteMap(booking: b, stops: stops, trackRider: _liveTrackable),
    ]);
  }

  List<Widget> _kindSpecific() {
    final booking = b;
    if (booking is FoodDeliveryModel) {
      final items = ref.watch(foodOrderItemsProvider(booking.id)).valueOrNull ?? const <FoodOrderItem>[];
      return [
        _section('Order', [
          _detailRow('Restaurant', booking.restaurantName),
          if (booking.instructions.isNotEmpty) _detailRow('Instructions', booking.instructions),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity} × ${item.name}${item.isOutOfStock ? ' (out of stock)' : ''}',
                      style: AppTypography.bodyMedium.copyWith(
                        fontSize: 14,
                        decoration: item.isOutOfStock ? TextDecoration.lineThrough : null,
                        color: item.isOutOfStock ? AppColors.neutral400 : null,
                      ),
                    ),
                  ),
                  Text(Formatters.currency(item.subtotal),
                      style: AppTypography.bodyMedium.copyWith(
                        fontSize: 14,
                        decoration: item.isOutOfStock ? TextDecoration.lineThrough : null,
                      )),
                ],
              ),
            ),
          if (_asRider) ...[
            if (booking.itemSubtotal != null) _detailRow('Item subtotal', Formatters.currency(booking.itemSubtotal)),
            if (outOfStockTotal(items) > 0) _detailRow('Out of stock', '− ${Formatters.currency(outOfStockTotal(items))}'),
            if (booking.deliveryFee != null) _detailRow('Delivery fee', Formatters.currency(booking.deliveryFee)),
            if (booking.itemSubtotal != null && (booking.status == 'pending' || booking.status == 'accepted'))
              _noteBox(Icons.payments_outlined,
                  'Bring ${Formatters.currency((booking.itemSubtotal! - outOfStockTotal(items)).clamp(0, double.infinity))} cash '
                  'to buy the food — the customer pays you back with the delivery fee.'
                  '${booking.status == 'accepted' ? ' Then take a photo of the receipt to start the trip.' : ''}'),
          ],
        ]),
        // the receipt the rider photographed before the trip (web sql/050)
        if ((booking.receiptPhotoUrl ?? '').isNotEmpty)
          _section('Receipt', [
            GestureDetector(
              key: const Key('details-receipt'),
              onTap: () => launchUrl(Uri.parse(booking.receiptPhotoUrl!), mode: LaunchMode.externalApplication),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  booking.receiptPhotoUrl!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    alignment: Alignment.center,
                    color: AppColors.neutral100,
                    child: Text('Open the receipt', style: AppTypography.caption),
                  ),
                ),
              ),
            ),
          ]),
      ];
    }
    if (booking is HaulingBookingModel) {
      return [
        _section('Hauling', [
          _detailRow('Pickup contact', '${booking.senderName}${booking.senderPhone.isEmpty ? '' : ' • ${booking.senderPhone}'}'),
          _detailRow('Receiver', '${booking.receiverName}${booking.receiverPhone.isEmpty ? '' : ' • ${booking.receiverPhone}'}'),
          _detailRow('Items', '${booking.categoryLabel} — ${booking.itemDescription}'),
          if (booking.estimatedWeightKg != null)
            _detailRow('Approx. weight', '${booking.estimatedWeightKg!.toStringAsFixed(0)} kg'),
          _detailRow('Helpers', booking.helpers == 0
              ? 'None — driver only'
              : '${booking.helpers} × ${Formatters.currency(booking.helperFee)}'),
          if (booking.instructions.isNotEmpty) _detailRow('Instructions', booking.instructions),
        ]),
      ];
    }
    if (booking is ParcelDeliveryModel) {
      return [
        _section('Parcel', [
          _detailRow('Sender', '${booking.senderName}${booking.senderPhone.isEmpty ? '' : ' • ${booking.senderPhone}'}'),
          _detailRow('Receiver', '${booking.receiverName}${booking.receiverPhone.isEmpty ? '' : ' • ${booking.receiverPhone}'}'),
          _detailRow('Size', booking.parcelSize),
          if (booking.parcelWeight != null)
            _detailRow('Weight', '${booking.parcelWeight!.toStringAsFixed(1)} kg'),
          if (booking.parcelDescription.isNotEmpty) _detailRow('Description', booking.parcelDescription),
          if (booking.instructions.isNotEmpty) _detailRow('Instructions', booking.instructions),
          if (booking.isRoundTrip) _detailRow('Round trip', 'Returns to the sender'),
          if (booking.codAmount > 0)
            _detailRow(
              'Cash on delivery',
              '${Formatters.currency(booking.codAmount)}'
              '${booking.codRemittedAt != null ? ' · handed to sender ${Formatters.date(booking.codRemittedAt!)}' : booking.status == 'completed' ? ' · collected, not yet handed over' : ''}',
            ),
        ]),
      ];
    }
    return const [];
  }

  double get _outOfStock => b is FoodDeliveryModel
      ? outOfStockTotal(ref.watch(foodOrderItemsProvider(b.id)).valueOrNull ?? const <FoodOrderItem>[])
      : 0;

  Widget _fareSection() {
    final booking = b;
    return _section('Fare & payment', [
      if (booking is FoodDeliveryModel && booking.itemSubtotal != null)
        _detailRow('Item subtotal', Formatters.currency(booking.itemSubtotal)),
      if (booking is FoodDeliveryModel && booking.deliveryFee != null)
        _detailRow('Delivery fee', Formatters.currency(booking.deliveryFee)),
      if (booking is FoodDeliveryModel && _outOfStock > 0)
        _detailRow(
            'Out of stock',
            '− ${Formatters.currency(_outOfStock)}'
            '${booking.paymentStatus == 'paid' && (booking.paymentMethod == 'gcash' || booking.paymentMethod == 'wallet') ? ' · refunded to your iTULOD wallet' : ''}'),
      // the promo taken off (web sql/053), above the total it lowered
      if ((booking.discountAmount ?? 0) > 0)
        _detailRow('Promo ${booking.promoCode ?? ''}', '− ${Formatters.currency(booking.discountAmount)}'),
      if (booking.finalFare != null || booking.estimatedFare != null)
        _totalRow('Total', Formatters.currency(booking.finalFare ?? booking.estimatedFare)),
      _detailRow('Method', paymentMethodLabel(booking.paymentMethod)),
      if (booking.paymentStatus != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text('Payment', style: AppTypography.captionDark)),
              StatusBadge(status: booking.paymentStatus!, fontSize: 11),
            ],
          ),
        ),
      if (booking.awaitingFinalFare)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('You can pay as soon as a rider accepts.',
              style: AppTypography.caption),
        ),
      if (booking.tipAmount != null && booking.tipAmount! > 0)
        _detailRow('Tip', Formatters.currency(booking.tipAmount)),
      if (booking.cancellationFee != null && booking.cancellationFee! > 0)
        _detailRow(
          booking.isNoShow ? 'No-show fee' : 'Cancellation fee',
          '${Formatters.currency(booking.cancellationFee)}'
          '${booking.cancellationFeePaid == true ? ' · paid' : booking.cancellationFeePaid == false ? ' · unpaid (top up your wallet)' : ''}',
        ),
      if (booking.paymentStatus == 'refunded')
        _detailRow(
          'Refund',
          '${Formatters.currency(((booking.finalFare ?? booking.estimatedFare ?? 0) - (booking.cancellationFee ?? 0)).clamp(0, double.infinity))} to your iTULOD wallet',
        ),
    ]);
  }

  // ── Rider view (web sql/047): the customer, earnings, what to collect ──

  Widget _noteBox(IconData icon, String text) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.primaryDark))),
          ],
        ),
      );

  Widget _customerSection() {
    if (_loadingRider) return const SkeletonList(count: 1, padding: EdgeInsets.only(bottom: 18));
    final c = _customer;
    if (c == null) {
      if (!_openRequest) return const SizedBox.shrink();
      return _section('Customer', [
        Text("The customer's name and number show once you accept this booking.", style: AppTypography.caption),
      ]);
    }
    final name = (c['full_name'] as String?)?.trim().isNotEmpty == true ? c['full_name'] as String : 'Customer';
    final phone = c['phone'] as String?;
    final avatar = c['avatar_url'] as String?;
    final completed = (c['completed_bookings'] as num?)?.toInt() ?? 0;
    final since = DateTime.tryParse(c['member_since']?.toString() ?? '');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final tripActive = b.canSendChat;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR CUSTOMER', style: AppTypography.caption.copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.primary,
                      backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar == null || avatar.isEmpty
                          ? Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTypography.bodyBold.copyWith(fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              completed == 0 ? 'New customer' : '$completed completed booking${completed == 1 ? '' : 's'}',
                              if (since != null) 'Since ${months[since.month - 1]} ${since.year}',
                            ].join(' · '),
                            style: AppTypography.caption,
                          ),
                          if (phone != null && phone.isNotEmpty)
                            Text(phone, style: AppTypography.caption.copyWith(color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (tripActive || _hadChat) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (tripActive && phone != null && phone.isNotEmpty) ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: const Text('Call'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, ChatScreen.route(b)),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: Text(tripActive ? 'Message' : 'View chat'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _earningsSection() {
    final booking = b;
    final e = _earn;
    final ended = booking.status == 'cancelled' || booking.isNoShow || booking.isExpired;
    final fare = booking.finalFare ?? booking.estimatedFare;
    final cod = booking is ParcelDeliveryModel && booking.codAmount > 0 ? booking.codAmount : 0.0;
    final isFinal = e?['is_final'] == true;
    final tip = (e?['tip'] as num?)?.toDouble() ?? 0;
    final shownFare = e == null ? null : (e['fare'] as num).toDouble() - (isFinal ? tip : 0);
    String? collect;
    if (!ended && booking.status != 'completed') {
      final codText = cod > 0 ? ' · plus the ${Formatters.currency(cod)} cash on delivery for the sender' : '';
      if (booking.paymentMethod == null || booking.paymentMethod == 'cash') {
        collect = 'Collect ${Formatters.currency(fare)} in cash from the customer$codText.';
      } else if (booking.paymentStatus == 'paid') {
        collect = 'Paid online — nothing to collect${cod > 0 ? ', except the ${Formatters.currency(cod)} cash on delivery for the sender' : ''}.';
      } else {
        collect = 'The customer pays online (${paymentMethodLabel(booking.paymentMethod)})$codText.';
      }
    }
    return _section('Your earnings', [
      if (e != null) ...[
        _detailRow(ended ? 'Fee from the customer' : 'Fare', Formatters.currency(shownFare)),
        // a promo is paid by iTULOD — the rider still earns from the full fare
        if (!ended && (booking.discountAmount ?? 0) > 0)
          _detailRow('Promo ${booking.promoCode ?? ''}', '${Formatters.currency(booking.discountAmount)} · paid by iTULOD, not you'),
        if (((e['commission'] as num?) ?? 0) > 0)
          _detailRow('iTULOD commission', '− ${Formatters.currency((e['commission'] as num).toDouble())}'),
        if (tip > 0) _detailRow('Tip from the customer', Formatters.currency(tip)),
        _totalRow(isFinal ? 'You earned' : 'You earn (estimate)',
            Formatters.currency((e['payout'] as num).toDouble())),
      ] else
        _detailRow('Fare', fare != null ? Formatters.currency(fare) : '—'),
      _detailRow('Method', paymentMethodLabel(booking.paymentMethod)),
      if (booking.paymentStatus != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text('Payment', style: AppTypography.captionDark)),
              StatusBadge(status: booking.paymentStatus!, fontSize: 11),
            ],
          ),
        ),
      if (collect != null) _noteBox(Icons.price_check_rounded, collect),
    ]);
  }

  Widget _vehicleSection() {
    final name = _vehicle?['name'] as String? ?? _riderApplication?['vehicle_type'] as String?;
    if (name == null) return const SizedBox.shrink();
    final plate = _riderApplication?['vehicle_plate'] as String?;
    final license = _riderApplication?['license_number'] as String?;
    final base = (_vehicle?['base_fare'] as num?)?.toDouble();
    final perKm = (_vehicle?['per_km_rate'] as num?)?.toDouble();
    // Plate is on the rider card once a rider's profile is shown.
    final onRiderCard = b.hasRider && (_riderProfile?['full_name'] as String?)?.isNotEmpty == true;
    return _section('Vehicle', [
      _detailRow('Vehicle type', name),
      if (plate != null && plate.isNotEmpty && !onRiderCard) _detailRow('Plate number', plate),
      if (license != null && license.isNotEmpty) _detailRow('License no.', license),
      // Rides are priced with the ride rates and the group size (sql/044).
      if (b is TransportBookingModel && _vehicle != null)
        _detailRow(
            'Fare',
            FareEstimator.rideFareBreakdown(VehicleModel.fromJson(_vehicle!), b.distanceKm ?? 1,
                (b as TransportBookingModel).passengers, Formatters.currency))
      else ...[
        if (base != null) _detailRow('Base fare', Formatters.currency(base)),
        if (perKm != null) _detailRow('Rate per km', '${Formatters.currency(perKm)}/km'),
      ],
    ]);
  }

  Widget _riderSection() {
    if (_loadingRider) {
      return const SkeletonList(count: 1, padding: EdgeInsets.only(bottom: 18));
    }
    if (!b.hasRider) {
      return _section('Rider', [
        Text(
            b.status == 'pending' || b.status == 'accepted'
                ? 'No rider assigned yet — waiting for a rider to accept.'
                : 'No rider was assigned to this booking.',
            style: AppTypography.caption),
      ]);
    }
    final name = _riderProfile?['full_name'] as String?;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    final phone = _riderProfile?['phone'] as String?;
    final avatar = _riderProfile?['avatar_url'] as String?;
    final isOwnJob = ref.read(authNotifierProvider).profile?.id == b.riderId;
    final tripActive = b.canSendChat;
    final vehicleName = _vehicle?['name'] as String? ?? _riderApplication?['vehicle_type'] as String?;
    final plate = _riderApplication?['vehicle_plate'] as String?;
    final avg = _riderRatings.isEmpty
        ? null
        : _riderRatings.reduce((a, c) => a + c) / _riderRatings.length;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((isOwnJob ? 'You' : 'Your rider').toUpperCase(),
              style: AppTypography.caption.copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary50),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.primary,
                        backgroundImage: (avatar?.isNotEmpty ?? false) ? NetworkImage(avatar!) : null,
                        child: (avatar?.isNotEmpty ?? false)
                            ? null
                            : Text(initials,
                                style: AppTypography.bodyBold.copyWith(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTypography.h3.copyWith(fontSize: 16)),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (avg != null)
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0A200)),
                                  const SizedBox(width: 2),
                                  Text(avg.toStringAsFixed(1), style: AppTypography.bodyBold.copyWith(fontSize: 13)),
                                  Text(' (${_riderRatings.length})', style: AppTypography.caption),
                                ])
                              else
                                Text('New rider',
                                    style: AppTypography.bodyBold.copyWith(fontSize: 13, color: AppColors.success)),
                              if (phone != null && phone.isNotEmpty) Text(phone, style: AppTypography.caption),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if ((plate != null && plate.isNotEmpty) || vehicleName != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (plate != null && plate.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.neutral900, width: 2),
                              ),
                              child: Text(plate,
                                  style: AppTypography.bodyBold.copyWith(fontSize: 13, letterSpacing: 1)),
                            ),
                          if (vehicleName != null) ...[
                            const SizedBox(height: 4),
                            Text(vehicleName, style: AppTypography.caption.copyWith(fontSize: 11.5)),
                          ],
                        ],
                      ),
                  ],
                ),
                // The chat lives here only: Message during the trip, View chat
                // (read-only) after — no second Messages button further down.
                if (!isOwnJob && (tripActive || _hadChat)) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (tripActive && phone != null && phone.isNotEmpty) ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: const Text('Call'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, ChatScreen.route(b)),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: Text(tripActive ? 'Message' : 'View chat'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentsSection() {
    final license = _riderApplication?['license_url'] as String?;
    final orcr = _riderApplication?['or_cr_url'] as String?;
    if ((license == null || license.isEmpty) && (orcr == null || orcr.isEmpty)) {
      return const SizedBox.shrink();
    }
    Widget link(String label, String url) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: Text(label),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _openRiderDoc(url),
        );
    return _section('Rider documents', [
      if (license != null && license.isNotEmpty) link("Driver's License", license),
      if (orcr != null && orcr.isNotEmpty) link('OR / CR', orcr),
    ]);
  }

  /// rider-documents is private — the saved public URL answers "Bucket not
  /// found" — so open a 1-hour signed link (customers may sign their rider's
  /// license and OR/CR, web sql/045).
  Future<void> _openRiderDoc(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = riderDocPath(url);
    try {
      if (path == null) throw Exception('file not found');
      final signed = await SupabaseConfig.client.storage.from('rider-documents').createSignedUrl(path, 3600);
      await launchUrl(Uri.parse(signed), mode: LaunchMode.externalApplication);
    } catch (e, s) {
      AppLog.warn('BookingDetailsSheet: rider document', e, s);
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't open that document.")));
    }
  }

  Widget _proofSection() {
    final url = b.deliveryProofUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return _section('Proof of delivery', [
      GestureDetector(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(url, height: 200, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text('Photo unavailable', style: AppTypography.caption)),
        ),
      ),
    ]);
  }

  /// The right status copy for the booking's current stage — expired,
  /// no-show, or the 15-minute grace-period reminder (web: statusNote).
  String? _statusNotice() {
    if (b.isExpired) return AppStrings.bookingExpiredMessage;
    if (b.isNoShow) return 'This booking was marked as a no-show by the rider.';
    if (b.status == 'pending') {
      return _asRider
          ? 'Accept within the 15-minute window, or this request expires automatically.'
          : AppStrings.pendingGracePeriodNote;
    }
    if (b.status == 'accepted') {
      return _asRider
          ? 'Start the trip within 15 minutes of the booking time, or it expires automatically.'
          : AppStrings.gracePeriodNote;
    }
    return null;
  }

  Widget _noticeBanner(String message) {
    final muted = b.isExpired || b.isNoShow;
    final color = muted ? AppColors.neutral500 : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: muted ? AppColors.neutral100 : AppColors.warning50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            b.isNoShow
                ? Icons.person_off_rounded
                : b.isExpired
                    ? Icons.timer_off_rounded
                    : Icons.hourglass_top_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: AppTypography.captionDark.copyWith(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title.toUpperCase(), style: AppTypography.caption.copyWith(letterSpacing: 1)),
            const SizedBox(height: 8),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.cardBorder))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodyBold.copyWith(fontSize: 14))),
          Text(value, style: AppTypography.h3.copyWith(fontSize: 17)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: AppTypography.captionDark)),
          Expanded(child: Text(value, style: AppTypography.bodyMedium.copyWith(fontSize: 14))),
        ],
      ),
    );
  }
}

/// Booked → Rider accepted → In progress → Done, with the times we know.
/// A cancelled / expired / no-show booking ends in a red step where it stopped
/// (web: timelineHTML in js/bookingDetails.js).
class _BookingTimeline extends StatelessWidget {
  final BookingBase booking;
  const _BookingTimeline({required this.booking});

  static const _progress = {
    BookingKind.transport: ('Trip started', 'Arrived'),
    BookingKind.food: ('Order picked up', 'Delivered'),
    BookingKind.parcel: ('Parcel picked up', 'Delivered'),
    BookingKind.hauling: ('Loaded, on the way', 'Delivered'),
  };
  static const _ended = {'cancelled': 'Cancelled', 'expired': 'Expired', 'no_show': 'No-show'};

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final labels = _progress[b.kind] ?? _progress[BookingKind.transport]!;
    final steps = <({String label, String time, bool ended})>[
      (label: 'Booked', time: Formatters.timeOnly(b.createdAt), ended: false),
      (label: 'Rider accepted', time: b.acceptedAt == null ? '' : Formatters.timeOnly(b.acceptedAt), ended: false),
      (label: labels.$1, time: '', ended: false),
      (
        label: labels.$2,
        time: b.status == 'completed' && b.updatedAt != null ? Formatters.timeOnly(b.updatedAt) : '',
        ended: false
      ),
    ];
    const reachedByStatus = {'pending': 0, 'accepted': 1, 'ongoing': 2, 'completed': 3};
    var reached = reachedByStatus[b.status] ?? 0;
    final endedLabel = _ended[b.status];
    if (endedLabel != null) {
      reached = b.acceptedAt != null ? 1 : 0;
      steps.removeRange(reached + 1, steps.length);
      steps.add((label: endedLabel, time: b.updatedAt == null ? '' : Formatters.timeOnly(b.updatedAt), ended: true));
    }

    String stateOf(int i) {
      if (steps[i].ended) return 'ended';
      if (i < reached || (i == reached && (endedLabel != null || b.status == 'completed'))) return 'done';
      if (i == reached) return 'current';
      return 'todo';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 26,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 3,
                              color: i == 0
                                  ? Colors.transparent
                                  : (stateOf(i) == 'todo' ? AppColors.cardBorder : AppColors.primary),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 3,
                              color: i == steps.length - 1
                                  ? Colors.transparent
                                  : (stateOf(i + 1) == 'todo' ? AppColors.cardBorder : AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                      _dot(stateOf(i)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i].label,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    fontSize: 11,
                    fontWeight: stateOf(i) == 'todo' ? FontWeight.w500 : FontWeight.w700,
                    color: stateOf(i) == 'ended'
                        ? AppColors.danger
                        : stateOf(i) == 'todo'
                            ? AppColors.neutral500
                            : AppColors.neutral900,
                  ),
                ),
                if (steps[i].time.isNotEmpty)
                  Text(steps[i].time, style: AppTypography.caption.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot(String state) {
    switch (state) {
      case 'done':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
        );
      case 'ended':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
        );
      case 'current':
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), spreadRadius: 4)],
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            ),
          ),
        );
      default:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.cardBorder, width: 2),
          ),
        );
    }
  }
}

/// Pickup dot → (stops) → drop-off marker on a vertical line.
class _RouteLine extends StatelessWidget {
  final String from;
  final String to;
  final List<String> stops;
  const _RouteLine({required this.from, required this.to, this.stops = const []});

  @override
  Widget build(BuildContext context) {
    Widget point(String label, String address, {required bool isEnd, bool isStop = false}) {
      final markerColor = isEnd ? AppColors.secondaryDark : AppColors.primary;
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  const SizedBox(height: 3),
                  Container(
                    width: isStop ? 10 : 16,
                    height: isStop ? 10 : 16,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: isEnd ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isEnd ? BorderRadius.circular(4) : null,
                      border: Border.all(color: markerColor, width: isStop ? 2.5 : 4),
                    ),
                  ),
                  if (!isEnd)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: AppColors.primary100,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isEnd ? 0 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label.isNotEmpty)
                      Text(label.toUpperCase(),
                          style: AppTypography.overline.copyWith(color: AppColors.neutral500, letterSpacing: 0.5)),
                    Text(address,
                        style: isStop
                            ? AppTypography.body.copyWith(fontSize: 13.5)
                            : AppTypography.bodyBold.copyWith(fontSize: 14.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        point('Pickup', from, isEnd: false),
        for (final s in stops) point('', s, isEnd: false, isStop: true),
        point('Drop-off', to, isEnd: true),
      ],
    );
  }
}
