// Rider sign-up offers every rider vehicle type the job matching knows
// (web sql/033 rider_type_for_vehicle), each with models and its jobs.
import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/core/constants/vehicle_catalog.dart';

void main() {
  test('all 10 rider vehicle types, Jeepney and Bus included', () {
    expect(vehicleTypes, ['Bicycle', 'Motorcycle', 'Tricycle', 'Car', 'SUV', 'Van', 'Jeepney', 'Bus', 'Pickup', 'Truck']);
  });

  test('each has models to pick and says which jobs it gets', () {
    for (final t in vehicleTypes) {
      expect(vehicleModelsByType[t], isNotEmpty, reason: '$t models');
      expect(vehicleTypeJobs[t], isNotNull, reason: '$t jobs');
    }
    expect(vehicleModelsByType['Pickup'], contains('Suzuki Multicab'));
    expect(vehicleModelsByType['Van'], contains('Mitsubishi L300'));
    expect(vehicleTypeLabel['Pickup'], 'Pickup / Multicab');
    expect(vehicleTypeJobs['Bicycle'], 'Food only');
  });
}
