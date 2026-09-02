import 'package:latlong2/latlong.dart';

import '../../shared/models/vehicle_model.dart';
import '../constants/map_config.dart';

class FareEstimator {
  FareEstimator._();

  static const Distance _distance = Distance();

  /// Straight-line ("as the crow flies") kilometres between two coordinates.
  static double haversineKm(LatLng from, LatLng to) {
    return _distance.as(LengthUnit.Kilometer, from, to);
  }

  /// Estimated road distance: straight line scaled by
  /// [MapConfig.roadDistanceFactor]. Used when the routing service is
  /// unreachable — real road distance comes from `RouteService.fetchRoute`.
  static double roadDistanceKm(LatLng from, LatLng to) {
    final km = haversineKm(from, to) * MapConfig.roadDistanceFactor;
    return km < 0.1 ? 0.1 : km;
  }

  /// Fallback for bookings with no coordinates: a deterministic pseudo-distance
  /// derived from the address text, mirroring the web app. Always returns
  /// 1.0 – 14.0 km. Ride bookings now use real coordinates via the map picker;
  /// food and parcel bookings still rely on this.
  static double simulateDistanceKm(String pickup, String destination) {
    final a = pickup.trim().toLowerCase();
    final b = destination.trim().toLowerCase();
    var seed = 0;
    for (final code in (a + b).codeUnits) {
      seed += code;
    }
    final km = ((seed % 140) / 10).floorToDouble();
    return km < 1 ? 1.0 : km;
  }

  /// fare = base_fare + per_km_rate × km (km defaults to 1).
  static double estimateFare(VehicleModel? vehicle, double distanceKm) {
    if (vehicle == null) return 0;
    return vehicle.baseFare + vehicle.perKmRate * (distanceKm > 0 ? distanceKm : 1);
  }
}
