import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:app_itulod/core/constants/map_config.dart';
import 'package:app_itulod/shared/models/saved_address_model.dart';

void main() {
  group('SavedAddressModel', () {
    test('parses correctly with valid numeric lat and lng', () {
      final json = {
        'id': 'addr-1',
        'customer_id': 'user-1',
        'label': 'Home',
        'address': '123 Main St, Cebu City',
        'lat': 10.3157,
        'lng': 123.8854,
      };

      final model = SavedAddressModel.fromJson(json);

      expect(model.id, 'addr-1');
      expect(model.userId, 'user-1');
      expect(model.label, 'Home');
      expect(model.address, '123 Main St, Cebu City');
      expect(model.point.latitude, 10.3157);
      expect(model.point.longitude, 123.8854);
    });

    test('parses correctly when lat and lng are null (e.g. from web or missing geocode)', () {
      final json = {
        'id': 'addr-2',
        'customer_id': 'user-2',
        'label': 'Office',
        'address': 'Ayala Center Cebu',
        'lat': null,
        'lng': null,
      };

      final model = SavedAddressModel.fromJson(json);

      expect(model.id, 'addr-2');
      expect(model.userId, 'user-2');
      expect(model.label, 'Office');
      expect(model.address, 'Ayala Center Cebu');
      // Falls back to MapConfig.defaultCenter
      expect(model.point.latitude, MapConfig.defaultCenter.latitude);
      expect(model.point.longitude, MapConfig.defaultCenter.longitude);
    });

    test('parses correctly when lat and lng are formatted as Strings', () {
      final json = {
        'id': 'addr-3',
        'customer_id': 'user-3',
        'label': 'Gym',
        'address': 'IT Park, Cebu City',
        'lat': '10.3298',
        'lng': '123.9063',
      };

      final model = SavedAddressModel.fromJson(json);

      expect(model.id, 'addr-3');
      expect(model.point.latitude, 10.3298);
      expect(model.point.longitude, 123.9063);
    });

    test('handles user_id alias and null id gracefully', () {
      final json = {
        'user_id': 'user-4',
        'label': 'School',
        'address': 'USC Talamban',
        'lat': 10.3533,
        'lng': 123.9135,
      };

      final model = SavedAddressModel.fromJson(json);

      expect(model.id, '');
      expect(model.userId, 'user-4');
      expect(model.label, 'School');
    });

    test('toJson produces expected payload for Supabase insertion', () {
      final model = SavedAddressModel(
        id: 'addr-5',
        userId: 'user-5',
        label: 'Coffee Shop',
        address: 'Fuente Osmena',
        point: const LatLng(10.3117, 123.8924),
      );

      final json = model.toJson();

      expect(json['id'], 'addr-5');
      expect(json['customer_id'], 'user-5');
      expect(json['label'], 'Coffee Shop');
      expect(json['address'], 'Fuente Osmena');
      expect(json['lat'], 10.3117);
      expect(json['lng'], 123.8924);
    });
  });
}
