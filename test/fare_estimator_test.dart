import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:app_itulod/core/constants/map_config.dart';
import 'package:app_itulod/core/services/geocoding_service.dart';
import 'package:app_itulod/core/utils/fare_estimator.dart';
import 'package:app_itulod/shared/models/vehicle_model.dart';

VehicleModel _vehicle({double baseFare = 40, double perKmRate = 12}) {
  return VehicleModel(
    id: 'v1',
    name: 'Motorcycle',
    baseFare: baseFare,
    perKmRate: perKmRate,
  );
}

void main() {
  group('haversineKm', () {
    test('one degree of latitude is about 111 km', () {
      final km = FareEstimator.haversineKm(
        const LatLng(0, 0),
        const LatLng(1, 0),
      );
      expect(km, closeTo(111.3, 1.0));
    });

    test('measures a known Cebu pair', () {
      // Cebu City centre → Mandaue City centre, roughly 4 km apart.
      final km = FareEstimator.haversineKm(
        const LatLng(10.3157, 123.8854),
        const LatLng(10.3231, 123.9223),
      );
      expect(km, closeTo(4.1, 0.4));
    });

    test('is zero for the same point', () {
      const point = LatLng(10.3157, 123.8854);
      expect(FareEstimator.haversineKm(point, point), 0);
    });
  });

  group('roadDistanceKm', () {
    test('scales the straight line by the road factor', () {
      const from = LatLng(10.3157, 123.8854);
      const to = LatLng(10.3231, 123.9223);

      expect(
        FareEstimator.roadDistanceKm(from, to),
        closeTo(
          FareEstimator.haversineKm(from, to) * MapConfig.roadDistanceFactor,
          0.001,
        ),
      );
    });

    test('never collapses to zero for two nearly identical pins', () {
      // A fare of exactly base_fare would be right, but a zero distance makes
      // estimateFare fall back to 1 km, which would overcharge.
      final km = FareEstimator.roadDistanceKm(
        const LatLng(10.3157, 123.8854),
        const LatLng(10.31570001, 123.88540001),
      );
      expect(km, greaterThan(0));
      expect(km, lessThan(0.2));
    });
  });

  group('simulateDistanceKm (food & parcel fallback)', () {
    test('stays within 1.0 – 14.0 km', () {
      const samples = [
        ['', ''],
        ['Colon Street', 'SM City Cebu'],
        ['a', 'b'],
        ['Ayala Center Cebu, Cebu City', 'Mactan Airport, Lapu-Lapu'],
        ['zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz', 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'],
      ];
      for (final pair in samples) {
        final km = FareEstimator.simulateDistanceKm(pair[0], pair[1]);
        expect(km, greaterThanOrEqualTo(1.0), reason: 'for $pair');
        expect(km, lessThanOrEqualTo(14.0), reason: 'for $pair');
      }
    });

    test('is deterministic and ignores case and padding', () {
      expect(
        FareEstimator.simulateDistanceKm('  Colon Street ', 'SM CITY CEBU'),
        FareEstimator.simulateDistanceKm('colon street', 'sm city cebu'),
      );
    });
  });

  group('estimateFare', () {
    test('is base fare plus per-km rate times distance', () {
      expect(FareEstimator.estimateFare(_vehicle(), 5), 40 + 12 * 5);
    });

    test('treats a zero distance as one kilometre', () {
      expect(FareEstimator.estimateFare(_vehicle(), 0), 40 + 12);
    });

    test('is zero without a vehicle', () {
      expect(FareEstimator.estimateFare(null, 5), 0);
    });

    test('a longer real distance costs more than a shorter one', () {
      final short = FareEstimator.roadDistanceKm(
        const LatLng(10.3157, 123.8854),
        const LatLng(10.3231, 123.9223),
      );
      final long = FareEstimator.roadDistanceKm(
        const LatLng(10.3157, 123.8854),
        const LatLng(10.3103, 123.9788), // Mactan
      );
      expect(
        FareEstimator.estimateFare(_vehicle(), long),
        greaterThan(FareEstimator.estimateFare(_vehicle(), short)),
      );
    });
  });

  group('GeocodingService.shortenAddress', () {
    test('keeps the leading segments and drops country and postcode', () {
      expect(
        GeocodingService.shortenAddress(
          'Colon Street, Parian, Cebu City, Cebu, Central Visayas, 6000, Philippines',
        ),
        'Colon Street, Parian, Cebu City, Cebu',
      );
    });

    test('leaves a short address alone', () {
      expect(
        GeocodingService.shortenAddress('SM City Cebu, Cebu City'),
        'SM City Cebu, Cebu City',
      );
    });

    test('handles a name with no commas', () {
      expect(GeocodingService.shortenAddress('Mactan'), 'Mactan');
    });
  });
}
