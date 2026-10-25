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

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// Ride fare (sql/044 public.vehicle_fare, web estimateRideFare): the
  /// minimum fare covers the first [VehicleModel.rideBaseKm], then the per-km
  /// rate. Jeepney / bus multiply by the passengers; others add the extra
  /// passenger fee. The per-unit fare is rounded to centavos first, like the
  /// database, or the booking is refused as underpriced.
  static double estimateRideFare(VehicleModel? vehicle, double distanceKm, int passengers) {
    if (vehicle == null) return 0;
    final pax = passengers < 1 ? 1 : passengers;
    final one = _round2(_rideBase(vehicle) + _ridePerKm(vehicle) * _extraKm(vehicle, distanceKm));
    final total = vehicle.farePerPassenger ? one * pax : one + (pax - 1) * vehicle.extraPassengerFee;
    return _round2(total);
  }

  /// "₱14.00 (first 4 km) + 12.2 km × ₱2.00 = ₱38.34 per person × 12"
  static String rideFareBreakdown(VehicleModel vehicle, double distanceKm, int passengers,
      String Function(num) peso) {
    final pax = passengers < 1 ? 1 : passengers;
    final baseKm = vehicle.rideBaseKm;
    final baseKmText = baseKm == baseKm.roundToDouble() ? baseKm.toStringAsFixed(0) : '$baseKm';
    final extraKm = _extraKm(vehicle, distanceKm);
    var s = peso(_rideBase(vehicle)) + (baseKm > 0 ? ' (first $baseKmText km)' : ' base');
    if (extraKm > 0) s += ' + ${extraKm.toStringAsFixed(1)} km × ${peso(_ridePerKm(vehicle))}';
    if (vehicle.farePerPassenger) {
      s += ' = ${peso(estimateRideFare(vehicle, distanceKm, 1))} per person × $pax';
    } else if (vehicle.extraPassengerFee > 0 && pax > 1) {
      s += ' + ${pax - 1} extra passenger${pax > 2 ? 's' : ''} × ${peso(vehicle.extraPassengerFee)}';
    }
    return s;
  }

  static double _rideBase(VehicleModel v) => v.rideBaseFare ?? v.baseFare;
  static double _ridePerKm(VehicleModel v) => v.ridePerKmRate ?? v.perKmRate;
  static double _extraKm(VehicleModel v, double distanceKm) {
    final km = distanceKm > 0 ? distanceKm : 1.0;
    return km > v.rideBaseKm ? km - v.rideBaseKm : 0;
  }
}
