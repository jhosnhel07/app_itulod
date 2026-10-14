import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_typography.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/utils/app_log.dart';
import '../../core/utils/formatters.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/customer/data/customer_repository.dart';
import '../../features/customer/presentation/screens/booking_confirmation_screen.dart'
    show paymentMethodLabel;
import '../models/booking_models.dart';
import '../providers/booking_extras_providers.dart';
import '../widgets/booking_route_map.dart';
import '../widgets/status_badge.dart';

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
  bool _loadingRider = true;
  bool _showMap = false;

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
      if (!mounted) return;
      setState(() {
        _riderProfile = results[0];
        _riderApplication = results[1];
        _vehicle = results[2];
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
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    Row(
                      children: [
                        Text('${b.kind.label} booking', style: AppTypography.h3),
                        const Spacer(),
                        StatusBadge(status: b.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${Formatters.date(b.createdAt)} · ${b.displayFare}',
                        style: AppTypography.caption),
                    const SizedBox(height: 12),
                    if (_statusNotice() != null) ...[
                      _noticeBanner(_statusNotice()!),
                      const SizedBox(height: 16),
                    ],
                    _routeSection(stops, stopsAsync.isLoading),
                    ..._kindSpecific(),
                    _fareSection(),
                    _vehicleSection(),
                    _riderSection(),
                    _documentsSection(),
                    _proofSection(),
                    if (b.hasRider)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, ChatScreen.route(b)),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: Text(b.canSendChat ? 'Messages' : 'Messages (read-only)'),
                        ),
                      ),
                    if (b.cancelledReason != null && b.cancelledReason!.isNotEmpty)
                      _section('Cancellation', [
                        Text(b.cancelledReason!, style: AppTypography.body.copyWith(color: AppColors.danger)),
                      ]),
                    if (b.rating != null)
                      _section('Rating', [
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

  // ── Sections ──────────────────────────────────────────────────────────

  Widget _routeSection(List<RideStop> stops, bool stopsLoading) {
    return _section('Route', [
      _detailRow('From', b.pickupLine),
      for (final s in stops)
        _detailRow(
          'Stop ${s.stopOrder}',
          '${s.arrived ? '✓ ' : ''}${s.address}',
        ),
      _detailRow('To', b.dropoffLine),
      if (b.distanceKm != null) _detailRow('Distance', Formatters.distance(b.distanceKm)),
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
          if (booking.codAmount > 0) _detailRow('COD to collect', Formatters.currency(booking.codAmount)),
        ]),
      ];
    }
    return const [];
  }

  Widget _fareSection() {
    final booking = b;
    return _section('Fare & payment', [
      if (booking is FoodDeliveryModel && booking.itemSubtotal != null)
        _detailRow('Item subtotal', Formatters.currency(booking.itemSubtotal)),
      if (booking is FoodDeliveryModel && booking.deliveryFee != null)
        _detailRow('Delivery fee', Formatters.currency(booking.deliveryFee)),
      if (booking.estimatedFare != null) _detailRow('Estimated fare', Formatters.currency(booking.estimatedFare)),
      if (booking.finalFare != null) _detailRow('Final fare', Formatters.currency(booking.finalFare)),
      if (booking is FoodDeliveryModel && booking.actualFoodCost != null)
        _detailRow('Paid at counter', Formatters.currency(booking.actualFoodCost)),
      if (booking.promoCode != null && booking.promoCode!.isNotEmpty)
        _detailRow('Promo', '${booking.promoCode}'
            '${(booking.discountAmount ?? 0) > 0 ? ' (−${Formatters.currency(booking.discountAmount)})' : ''}'),
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
          child: Text("You'll be asked to pay once the rider confirms the fare at pickup.",
              style: AppTypography.caption),
        ),
      if (booking.tipAmount != null && booking.tipAmount! > 0)
        _detailRow('Tip', Formatters.currency(booking.tipAmount)),
      if (booking.cancellationFee != null && booking.cancellationFee! > 0)
        _detailRow('Cancellation fee', Formatters.currency(booking.cancellationFee)),
    ]);
  }

  Widget _vehicleSection() {
    final name = _vehicle?['name'] as String? ?? _riderApplication?['vehicle_type'] as String?;
    if (name == null) return const SizedBox.shrink();
    final plate = _riderApplication?['vehicle_plate'] as String?;
    final license = _riderApplication?['license_number'] as String?;
    final base = (_vehicle?['base_fare'] as num?)?.toDouble();
    final perKm = (_vehicle?['per_km_rate'] as num?)?.toDouble();
    return _section('Vehicle', [
      _detailRow('Vehicle type', name),
      if (plate != null && plate.isNotEmpty) _detailRow('Plate number', plate),
      if (license != null && license.isNotEmpty) _detailRow('License no.', license),
      if (base != null) _detailRow('Base fare', Formatters.currency(base)),
      if (perKm != null) _detailRow('Rate per km', '${Formatters.currency(perKm)}/km'),
    ]);
  }

  Widget _riderSection() {
    if (_loadingRider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!b.hasRider) {
      return _section('Rider', [
        Text('No rider assigned yet — waiting for a rider to accept.', style: AppTypography.caption),
      ]);
    }
    final name = _riderProfile?['full_name'] as String?;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    final phone = _riderProfile?['phone'] as String?;
    final avatar = _riderProfile?['avatar_url'] as String?;
    final appStatus = _riderApplication?['status'] as String?;
    return _section('Rider', [
      Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary100,
            backgroundImage: (avatar?.isNotEmpty ?? false) ? NetworkImage(avatar!) : null,
            child: (avatar?.isNotEmpty ?? false)
                ? null
                : Text(name[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.bodyBold),
                if (phone != null && phone.isNotEmpty) Text(phone, style: AppTypography.captionDark),
              ],
            ),
          ),
          if (appStatus != null) StatusBadge(status: appStatus, fontSize: 10),
          if (phone != null && phone.isNotEmpty)
            IconButton(
              tooltip: 'Call rider',
              icon: const Icon(Icons.call_rounded, color: AppColors.primary),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            ),
        ],
      ),
    ]);
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
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        );
    return _section('Rider documents', [
      if (license != null && license.isNotEmpty) link("Driver's License", license),
      if (orcr != null && orcr.isNotEmpty) link('OR / CR', orcr),
    ]);
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
    if (b.status == 'pending') return AppStrings.pendingGracePeriodNote;
    if (b.status == 'accepted') return AppStrings.gracePeriodNote;
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
