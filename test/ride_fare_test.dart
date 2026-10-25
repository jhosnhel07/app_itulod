// Ride fares + passengers (sql/044). FareEstimator.estimateRideFare must
// match public.vehicle_fare() in the database and estimateRideFare() on the
// web (test/unit/ride-fare.test.mjs), or the booking is refused as
// underpriced. Rates are the Philippine fares sql/044 sets.
import 'package:flutter_test/flutter_test.dart';

import 'package:app_itulod/core/utils/fare_estimator.dart';
import 'package:app_itulod/core/utils/formatters.dart';
import 'package:app_itulod/shared/models/vehicle_model.dart';

VehicleModel _v(Map<String, dynamic> json) => VehicleModel.fromJson({'id': json['name'], ...json});

final motorcycle = _v({'name': 'Motorcycle', 'base_fare': 25, 'per_km_rate': 8, 'ride_base_fare': 20, 'ride_base_km': 1, 'ride_per_km_rate': 10, 'min_passengers': 1, 'max_passengers': 1});
final tricycle = _v({'name': 'Tricycle', 'base_fare': 30, 'per_km_rate': 9, 'ride_base_fare': 20, 'ride_base_km': 1.5, 'ride_per_km_rate': 8, 'extra_passenger_fee': 20, 'min_passengers': 1, 'max_passengers': 3});
final car = _v({'name': 'Car', 'base_fare': 40, 'per_km_rate': 12, 'ride_base_fare': 65, 'ride_base_km': 0, 'ride_per_km_rate': 15, 'min_passengers': 1, 'max_passengers': 4});
final suv = _v({'name': 'SUV', 'ride_base_fare': 75, 'ride_per_km_rate': 18, 'min_passengers': 3, 'max_passengers': 6});
final jeepney = _v({'name': 'Jeepney', 'ride_base_fare': 14, 'ride_base_km': 4, 'ride_per_km_rate': 2, 'fare_per_passenger': true, 'min_passengers': 9, 'max_passengers': 14});
final bus = _v({'name': 'Bus', 'ride_base_fare': 12, 'ride_base_km': 5, 'ride_per_km_rate': 2.2, 'fare_per_passenger': true, 'min_passengers': 15, 'max_passengers': 40});
final all = [motorcycle, tricycle, car, suv, jeepney, bus];

void main() {
  test('ride fares for 10 km match the web and the DB', () {
    expect(FareEstimator.estimateRideFare(motorcycle, 10, 1), 110);
    expect(FareEstimator.estimateRideFare(tricycle, 10, 1), 88);
    expect(FareEstimator.estimateRideFare(tricycle, 10, 3), 128); // + 2 × ₱20
    expect(FareEstimator.estimateRideFare(car, 10, 4), 215); // per vehicle
    expect(FareEstimator.estimateRideFare(jeepney, 10, 12), 312); // ₱26 × 12
    expect(FareEstimator.estimateRideFare(bus, 10, 20), 460); // ₱23 × 20
  });

  test('per-person fare is rounded to centavos before multiplying', () {
    // ₱14 + 12.17 km × ₱2 = ₱38.34 per person (DB: 460.08, not 460.12)
    expect(FareEstimator.estimateRideFare(jeepney, 16.17, 12), 460.08);
  });

  test('the minimum fare covers the included km', () {
    expect(FareEstimator.estimateRideFare(jeepney, 3, 9), 14.0 * 9);
    expect(FareEstimator.estimateRideFare(motorcycle, 0.5, 1), 20);
  });

  test('deliveries keep their own rates', () {
    expect(FareEstimator.estimateFare(motorcycle, 10), 105);
    expect(FareEstimator.estimateFare(car, 10), 160);
  });

  test('only vehicles that fit the group are offered', () {
    List<String> fits(int pax) => all.where((v) => v.fitsPassengers(pax)).map((v) => v.name).toList();
    expect(fits(1), ['Motorcycle', 'Tricycle', 'Car']);
    expect(fits(3), ['Tricycle', 'Car', 'SUV']);
    expect(fits(12), ['Jeepney']);
    expect(fits(20), ['Bus']);
    expect(fits(41), isEmpty);
  });

  test('max passengers falls back to capacity on old rows', () {
    final old = VehicleModel.fromJson({'id': 'x', 'name': 'Old', 'capacity': 4});
    expect(old.minPassengers, 1);
    expect(old.maxPassengers, 4);
    expect(old.fitsPassengers(4), isTrue);
    expect(old.fitsPassengers(5), isFalse);
  });

  test('labels and breakdowns', () {
    expect(motorcycle.passengerRangeText, '1 passenger');
    expect(jeepney.passengerRangeText, '9–14 passengers');
    final peso = Formatters.currency;
    expect(FareEstimator.rideFareBreakdown(tricycle, 10, 3, peso), contains('2 extra passengers × ${peso(20)}'));
    expect(FareEstimator.rideFareBreakdown(jeepney, 10, 12, peso), contains('per person × 12'));
    expect(FareEstimator.rideFareBreakdown(jeepney, 10, 12, peso), startsWith('${peso(14)} (first 4 km) + 6.0 km'));
  });
}
