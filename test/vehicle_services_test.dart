import 'package:flutter_test/flutter_test.dart';
import 'package:app_itulod/shared/models/vehicle_model.dart';

// vehicles.services (web sql/040): which services each vehicle can be booked for.
void main() {
  test('reads the services list', () {
    final bike = VehicleModel.fromJson({'id': 'b', 'name': 'Bicycle', 'service': 'standard', 'services': ['food']});
    expect(bike.allows('food'), isTrue);
    expect(bike.allows('ride'), isFalse);
    expect(bike.allows('parcel'), isFalse);
    expect(bike.isHauling, isFalse);

    final suv = VehicleModel.fromJson({'id': 's', 'name': 'SUV', 'services': ['parcel', 'ride']});
    expect(suv.allows('ride'), isTrue);
    expect(suv.allows('food'), isFalse);
  });

  test('older rows without services fall back to the standard / hauling split', () {
    final car = VehicleModel.fromJson({'id': 'c', 'name': 'Car', 'service': 'standard'});
    expect(['ride', 'food', 'parcel'].every(car.allows), isTrue);
    expect(car.allows('hauling'), isFalse);

    final l300 = VehicleModel.fromJson({'id': 'l', 'name': 'L300 Van', 'service': 'hauling'});
    expect(l300.isHauling, isTrue);
    expect(l300.allows('ride'), isFalse);
  });
}
