import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:app_itulod/core/constants/ilocos_norte.dart';

void main() {
  group('isInIlocosNorte', () {
    const inside = {
      'Laoag': LatLng(18.1975, 120.5936),
      'Batac': LatLng(18.0554, 120.5654),
      'Pagudpud': LatLng(18.5636, 120.7875),
      'Badoc': LatLng(17.9269, 120.4756),
      'Nueva Era': LatLng(17.9156, 120.6679),
      'Adams': LatLng(18.4575, 120.9056),
      'Carasi': LatLng(18.1964, 120.8711),
      'Paoay': LatLng(18.0619, 120.5222),
      'Burgos': LatLng(18.5150, 120.6455),
      'San Nicolas': LatLng(18.1725, 120.5951),
      'Laoag Airport': LatLng(18.1781, 120.5317),
    };
    const outside = {
      'Vigan, Ilocos Sur': LatLng(17.5747, 120.3869),
      'Sinait, Ilocos Sur': LatLng(17.8670, 120.4587),
      'Bangued, Abra': LatLng(17.5964, 120.6178),
      'Claveria, Cagayan': LatLng(18.6073, 121.0824),
      'Kabugao, Apayao': LatLng(18.0231, 121.1833),
      'Manila': LatLng(14.5995, 120.9842),
    };

    for (final e in inside.entries) {
      test('${e.key} is inside', () => expect(isInIlocosNorte(e.value), isTrue));
    }
    for (final e in outside.entries) {
      test('${e.key} is outside', () => expect(isInIlocosNorte(e.value), isFalse));
    }
    test('null is outside', () => expect(isInIlocosNorte(null), isFalse));
  });
}
