import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return const LocationService();
});

/// Why a location request came back empty, so the UI can say something useful
/// instead of failing silently.
enum LocationFailure {
  /// Device location (GPS / location services) is switched off.
  serviceDisabled,

  /// User said no this time.
  denied,

  /// User said never — only the OS settings screen can undo it.
  deniedForever,

  /// Timed out, no fix, or the platform threw.
  unavailable,
}

class LocationResult {
  final LatLng? point;
  final LocationFailure? failure;

  const LocationResult.success(LatLng this.point) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : point = null;

  bool get isSuccess => point != null;

  /// Message to surface to the customer. Empty on success.
  String get message {
    switch (failure) {
      case LocationFailure.serviceDisabled:
        return 'Turn on location services to use your current position.';
      case LocationFailure.denied:
        return 'Location permission denied. Pick your spot on the map instead.';
      case LocationFailure.deniedForever:
        return 'Location is blocked for iTULOD. Enable it in your device settings.';
      case LocationFailure.unavailable:
        return "Couldn't get your location. Pick your spot on the map instead.";
      case null:
        return '';
    }
  }
}

/// Wraps geolocator so callers never have to handle a platform exception.
/// Every failure comes back as a [LocationResult], never as a throw.
class LocationService {
  const LocationService();

  Future<LocationResult> currentPosition({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failed(LocationFailure.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failed(LocationFailure.denied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return LocationResult.success(
        LatLng(position.latitude, position.longitude),
      );
    } catch (_) {
      // Timeouts, no-fix, Windows privacy settings, web insecure origin.
      return const LocationResult.failed(LocationFailure.unavailable);
    }
  }
}
