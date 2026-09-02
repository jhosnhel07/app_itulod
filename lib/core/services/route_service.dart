import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants/map_config.dart';

final routeServiceProvider = Provider<RouteService>((ref) {
  final service = RouteService();
  ref.onDispose(service.dispose);
  return service;
});

/// A driving route: how far it actually is by road, and the shape to draw.
class RouteResult {
  final double distanceKm;
  final Duration duration;
  final List<LatLng> points;

  const RouteResult({
    required this.distanceKm,
    required this.duration,
    required this.points,
  });
}

/// Road distance and geometry from the public OSRM demo server.
///
/// The demo server has no uptime guarantee, so [fetchRoute] returns null on
/// any failure and callers fall back to the straight-line estimate in
/// `FareEstimator.roadDistanceKm`. Nothing here is load-bearing.
class RouteService {
  RouteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void dispose() => _client.close();

  Future<RouteResult?> fetchRoute(LatLng from, LatLng to) async {
    // OSRM takes lon,lat — the reverse of LatLng's order.
    final coords = '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}';
    final uri = Uri.parse('${MapConfig.osrmBase}/route/v1/driving/$coords')
        .replace(queryParameters: {
      'overview': 'full',
      'geometries': 'geojson',
      'alternatives': 'false',
      'steps': 'false',
    });

    try {
      final response = await _client.get(uri).timeout(MapConfig.networkTimeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] != 'Ok') return null;

      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final meters = (route['distance'] as num?)?.toDouble();
      final seconds = (route['duration'] as num?)?.toDouble() ?? 0;
      final coordinates =
          (route['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?;
      if (meters == null || coordinates == null) return null;

      final points = <LatLng>[];
      for (final pair in coordinates) {
        final xy = pair as List;
        if (xy.length < 2) continue;
        points.add(LatLng((xy[1] as num).toDouble(), (xy[0] as num).toDouble()));
      }
      if (points.isEmpty) return null;

      return RouteResult(
        distanceKm: meters / 1000,
        duration: Duration(seconds: seconds.round()),
        points: points,
      );
    } catch (_) {
      return null;
    }
  }
}
