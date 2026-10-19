import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/map_config.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../shared/widgets/map_widgets.dart';
import '../../data/customer_repository.dart';

/// Online, approved, idle riders from `get_nearby_riders()` (sql/017),
/// refreshed every 20 s — the same cadence as the web's
/// startNearbyRidersWatch(). Positions are coarse (~110 m) by design.
final nearbyRidersProvider = StreamProvider.autoDispose<List<NearbyRider>>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final controller = StreamController<List<NearbyRider>>();

  Future<void> poll() async {
    try {
      controller.add(await repo.fetchNearbyRiders());
    } catch (e, s) {
      AppLog.warn('get_nearby_riders failed', e, s);
    }
  }

  poll();
  final timer = Timer.periodic(const Duration(seconds: 20), (_) => poll());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// "Nearby" means within this distance of the pickup (web: NEARBY_RADIUS_KM).
const double nearbyRadiusKm = 10;

/// Rider vehicle types that can take hauling jobs (sql/022 is_hauling_rider).
const List<String> haulingRiderTypes = ['Van', 'Pickup', 'Truck'];

/// Booking vehicle name (vehicles.name) → rider vehicle type
/// (rider_applications.vehicle_type). Standard names match one to one; the
/// hauling ones are descriptive ("L300 Van", "6-Wheeler Truck").
/// Mirrors riderTypeForVehicle() in the web's js/map.js.
String? riderTypeForVehicle(String? name) {
  if (name == null || name.isEmpty) return null;
  if (_vehicleKinds.containsKey(name)) return name;
  final n = name.toLowerCase();
  if (n.contains('pickup') || n.contains('multicab')) return 'Pickup';
  if (n.contains('truck') || n.contains('wheeler')) return 'Truck';
  if (n.contains('van')) return 'Van';
  if (n.contains('suv')) return 'SUV';
  if (n.contains('tricycle') || n.contains('trike')) return 'Tricycle';
  if (n.contains('motor')) return 'Motorcycle';
  if (n.contains('bicycle') || n.contains('bike')) return 'Bicycle';
  if (n.contains('jeep')) return 'Jeepney';
  if (n.contains('bus')) return 'Bus';
  if (n.contains('car') || n.contains('sedan')) return 'Car';
  return name;
}

class _VehicleKind {
  final FaIconData? icon;
  final String? emoji;
  final String one;
  final String many;
  const _VehicleKind(this.one, this.many, {this.icon, this.emoji});
}

const _vehicleKinds = <String, _VehicleKind>{
  'Motorcycle': _VehicleKind('motorcycle', 'motorcycles', icon: FontAwesomeIcons.motorcycle),
  'Tricycle': _VehicleKind('tricycle', 'tricycles', emoji: '🛺'),
  'Car': _VehicleKind('car', 'cars', icon: FontAwesomeIcons.car),
  'SUV': _VehicleKind('SUV', 'SUVs', icon: FontAwesomeIcons.carSide),
  'Van': _VehicleKind('van', 'vans', icon: FontAwesomeIcons.vanShuttle),
  'Pickup': _VehicleKind('pickup', 'pickups', icon: FontAwesomeIcons.truckPickup),
  'Truck': _VehicleKind('truck', 'trucks', icon: FontAwesomeIcons.truck),
  'Bicycle': _VehicleKind('bicycle', 'bicycles', icon: FontAwesomeIcons.bicycle),
  'Jeepney': _VehicleKind('jeepney', 'jeepneys', icon: FontAwesomeIcons.busSimple),
  'Bus': _VehicleKind('bus', 'buses', icon: FontAwesomeIcons.bus),
};

/// The "Riders near you" map on every booking form (ride, food, parcel,
/// hauling): only drivers with the chosen vehicle, and only those within
/// [nearbyRadiusKm] of [origin] (the pickup, or the restaurant for food).
/// Same rules as the web's renderNearbyRiders() in js/map.js.
class RidersNearYouMap extends ConsumerWidget {
  /// Name of the vehicle picked on the form (vehicles.name), if any.
  final String? vehicleName;

  /// Where "nearby" is measured from; null until the customer sets it.
  final LatLng? origin;

  /// Hauling form: with no vehicle picked, show Van / Pickup / Truck drivers.
  final bool hauling;

  /// How [origin] is described: "within 10 km of {originLabel}".
  final String originLabel;

  /// Shown while [origin] is null: "… online — {noOriginHint} to see who's near".
  /// Null just says how many are online (food: a restaurant without a map pin).
  final String? noOriginHint;

  const RidersNearYouMap({
    super.key,
    this.vehicleName,
    this.origin,
    this.hauling = false,
    this.originLabel = 'your pickup',
    this.noOriginHint = 'set your pickup',
  });

  static const _distance = Distance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(nearbyRidersProvider).valueOrNull ?? const <NearbyRider>[];
    final type = riderTypeForVehicle(vehicleName);
    final types = type != null ? [type] : (hauling ? haulingRiderTypes : null);
    final from = origin;
    final riders = [
      for (final r in all)
        if ((types == null || types.contains(r.vehicleType)) &&
            (from == null || _distance.as(LengthUnit.Kilometer, from, r.point) <= nearbyRadiusKm))
          r,
    ];

    final fallback = hauling
        ? const _VehicleKind('hauling driver', 'hauling drivers', icon: FontAwesomeIcons.truckMoving)
        : const _VehicleKind('driver', 'drivers', icon: FontAwesomeIcons.motorcycle);
    final kind = _vehicleKinds[type] ??
        (type != null ? _VehicleKind('$type driver', '$type drivers', icon: fallback.icon) : fallback);
    final n = riders.length;
    final noun = n == 1 ? kind.one : kind.many;
    final km = nearbyRadiusKm.toStringAsFixed(0);
    final label = from != null
        ? (n > 0 ? '$n $noun within $km km of $originLabel' : 'No ${kind.many} within $km km of $originLabel right now')
        : n == 0
            ? 'No ${kind.many} online right now'
            : noOriginHint == null
                ? '$n $noun online'
                : "$n $noun online — $noOriginHint to see who's near";

    final center = from ?? (riders.isNotEmpty ? riders.first.point : MapConfig.defaultCenter);

    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          FlutterMap(
            // Re-centre when the pickup moves, or once the first riders arrive.
            key: ValueKey(from ?? riders.isEmpty),
            options: MapOptions(
              initialCenter: center,
              initialZoom: from != null ? 12.5 : 13,
              minZoom: MapConfig.minZoom,
              maxZoom: MapConfig.maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              const OsmTileLayer(),
              MarkerLayer(
                markers: [
                  for (final r in riders)
                    Marker(
                      point: r.point,
                      width: 30,
                      height: 30,
                      child: _RiderPin(kind: _vehicleKinds[r.vehicleType] ?? _vehicleKinds['Motorcycle']!),
                    ),
                  if (from != null)
                    Marker(
                      point: from,
                      width: 34,
                      height: 34,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on_rounded, size: 34, color: Color(0xFF22C55E)),
                    ),
                ],
              ),
              const OsmAttribution(),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _KindIcon(kind: kind, size: 13, color: AppColors.success),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderPin extends StatelessWidget {
  final _VehicleKind kind;
  const _RiderPin({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A9D63),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: _KindIcon(kind: kind, size: 13, color: Colors.white),
    );
  }
}

class _KindIcon extends StatelessWidget {
  final _VehicleKind kind;
  final double size;
  final Color color;
  const _KindIcon({required this.kind, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final emoji = kind.emoji;
    if (emoji != null) return Text(emoji, style: TextStyle(fontSize: size + 1, height: 1));
    return FaIcon(kind.icon, size: size, color: color);
  }
}
