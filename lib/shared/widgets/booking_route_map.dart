import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/services/route_service.dart';
import '../../features/customer/data/customer_repository.dart';
import '../../features/customer/presentation/widgets/route_preview_map.dart';
import '../models/booking_models.dart';

/// Route map for one booking — the app's version of the web's booking-details
/// map (js/map.js showBookingDetailsRoute + trackRiderOnBookingMap).
///
/// Uses the pins stored on the booking when there are any (rides booked from
/// the map picker), otherwise geocodes the addresses. With [trackRider] it
/// also follows the assigned rider's live `rider_locations` row and shows an
/// ETA to pickup (before the trip starts) or drop-off (once it's ongoing).
class BookingRouteMap extends ConsumerStatefulWidget {
  final BookingBase booking;
  final List<RideStop> stops;
  final bool trackRider;
  final double height;

  const BookingRouteMap({
    super.key,
    required this.booking,
    this.stops = const [],
    this.trackRider = false,
    this.height = 220,
  });

  @override
  ConsumerState<BookingRouteMap> createState() => _BookingRouteMapState();
}

class _BookingRouteMapState extends ConsumerState<BookingRouteMap> {
  LatLng? _pickup;
  LatLng? _dropoff;
  List<LatLng> _stopPoints = const [];
  List<LatLng>? _route;
  bool _loading = true;

  LatLng? _rider;
  int? _etaMinutes;
  StreamSubscription<LatLng?>? _riderSub;
  DateTime _lastEta = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _riderSub?.cancel();
    super.dispose();
  }

  Future<LatLng?> _geocode(String address) async {
    if (address.trim().isEmpty) return null;
    final hits = await ref.read(geocodingServiceProvider).searchPlaces(address, limit: 1);
    return hits.isEmpty ? null : hits.first.point;
  }

  Future<void> _resolve() async {
    final b = widget.booking;
    LatLng? pickup, dropoff;
    if (b is TransportBookingModel) {
      if (b.pickupLat != null && b.pickupLng != null) pickup = LatLng(b.pickupLat!, b.pickupLng!);
      if (b.destinationLat != null && b.destinationLng != null) {
        dropoff = LatLng(b.destinationLat!, b.destinationLng!);
      }
    }
    pickup ??= await _geocode(b.pickupLine);
    dropoff ??= await _geocode(b.dropoffLine);

    final stops = <LatLng>[];
    for (final s in widget.stops) {
      final p = (s.lat != null && s.lng != null) ? LatLng(s.lat!, s.lng!) : await _geocode(s.address);
      if (p != null) stops.add(p);
    }

    List<LatLng>? route;
    if (pickup != null && dropoff != null) {
      final result = await ref
          .read(routeServiceProvider)
          .fetchRouteWaypoints([pickup, ...stops, dropoff]);
      route = result?.points;
    }
    if (!mounted) return;
    setState(() {
      _pickup = pickup;
      _dropoff = dropoff;
      _stopPoints = stops;
      _route = route;
      _loading = false;
    });

    if (widget.trackRider && b.hasRider) {
      _riderSub = ref
          .read(customerRepositoryProvider)
          .watchRiderLocation(b.riderId!)
          .listen(_onRider, onError: (_) {});
    }
  }

  Future<void> _onRider(LatLng? position) async {
    if (!mounted || position == null) return;
    setState(() => _rider = position);
    // ETA from OSRM at most every 30 s — the rider writes every ~10 s.
    final target = widget.booking.status == 'ongoing' ? _dropoff : _pickup;
    if (target == null || DateTime.now().difference(_lastEta) < const Duration(seconds: 30)) return;
    _lastEta = DateTime.now();
    final result = await ref.read(routeServiceProvider).fetchRoute(position, target);
    if (mounted && result != null) {
      setState(() => _etaMinutes = result.duration.inMinutes.clamp(1, 999));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_pickup == null || _dropoff == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Map unavailable — these addresses could not be located.',
            style: AppTypography.caption),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.trackRider && _etaMinutes != null) ...[
          Row(
            children: [
              const Icon(Icons.two_wheeler_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                widget.booking.status == 'ongoing'
                    ? 'About $_etaMinutes min to drop-off'
                    : 'Rider ~$_etaMinutes min away',
                style: AppTypography.bodyBold.copyWith(color: AppColors.primary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ] else if (widget.trackRider && _rider == null) ...[
          Text('Waiting for the rider\'s live location…', style: AppTypography.caption),
          const SizedBox(height: 8),
        ],
        RoutePreviewMap(
          pickup: _pickup!,
          destination: _dropoff!,
          routePoints: _route,
          stops: _stopPoints,
          liveRider: _rider,
          height: widget.height,
        ),
      ],
    );
  }
}
