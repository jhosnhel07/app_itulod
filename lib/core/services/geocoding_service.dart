import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants/ilocos_norte.dart';
import '../constants/map_config.dart';
import '../utils/app_log.dart';

final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  final service = GeocodingService();
  ref.onDispose(service.dispose);
  return service;
});

/// A place returned by search — its label and where it is.
class PlaceResult {
  final String displayName;
  final LatLng point;

  const PlaceResult({required this.displayName, required this.point});
}

/// Address lookup against OpenStreetMap's Nominatim.
///
/// Nominatim's usage policy allows about one request per second from a single
/// client, so calls are serialised through [_throttle]. Every method degrades
/// to null / an empty list rather than throwing: a failed lookup must never
/// stop the customer from confirming a pin they can already see.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  DateTime? _lastCall;

  void dispose() => _client.close();

  /// Nominatim returns the whole hierarchy down to the country
  /// ("Colon Street, Parian, Cebu City, Cebu, Central Visayas, 6000,
  /// Philippines"). Riders only need the front of that, and it is what gets
  /// stored on the booking, so trim it to the leading [parts] segments.
  static String shortenAddress(String displayName, {int parts = 4}) {
    final segments = displayName
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return displayName.trim();
    return segments.take(parts).join(', ');
  }

  /// The address at a coordinate, or null if nothing has a name for it.
  /// Mapbox first — the web's _reverseGeocode does the same, so a pin gets
  /// the same address in both — then Nominatim.
  Future<String?> reverseGeocode(LatLng point) async {
    final fromMapbox = await _mapboxReverse(point);
    if (fromMapbox != null) return fromMapbox;

    final uri = Uri.parse('${MapConfig.nominatimBase}/reverse').replace(
      queryParameters: {
        'format': 'jsonv2',
        'lat': point.latitude.toStringAsFixed(6),
        'lon': point.longitude.toStringAsFixed(6),
        'zoom': '18',
        'addressdetails': '1',
      },
    );

    final body = await _get(uri);
    if (body == null) return null;

    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final name = json['display_name'] as String?;
      return (name == null || name.isEmpty) ? null : name;
    } catch (e, s) {
      AppLog.warn('reverseGeocode: bad Nominatim response', e, s);
      return null;
    }
  }

  Future<String?> _mapboxReverse(LatLng point) async {
    final token = MapConfig.mapboxToken;
    if (token == null) return null;
    final uri = Uri.parse(
            'https://api.mapbox.com/geocoding/v5/mapbox.places/${point.longitude.toStringAsFixed(6)},${point.latitude.toStringAsFixed(6)}.json')
        .replace(queryParameters: {'access_token': token, 'limit': '1'});
    try {
      final response = await _client.get(uri).timeout(MapConfig.networkTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final features = json['features'] as List?;
      final name = (features == null || features.isEmpty)
          ? null
          : (features.first as Map<String, dynamic>)['place_name'] as String?;
      return (name == null || name.isEmpty) ? null : name;
    } catch (e, s) {
      AppLog.warn('Mapbox reverse geocode failed', e, s);
      return null;
    }
  }

  /// Places matching a free-text query, best match first.
  Future<List<PlaceResult>> searchPlaces(String query, {int limit = 6}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final uri = Uri.parse('${MapConfig.nominatimBase}/search').replace(
      queryParameters: {
        'format': 'jsonv2',
        'q': trimmed,
        'limit': '$limit',
        'countrycodes': MapConfig.searchCountryCodes,
        'addressdetails': '1',
        // Ilocos Norte only (iTULOD's service area).
        'viewbox': ilocosNorteViewbox,
        'bounded': '1',
      },
    );

    final body = await _get(uri);
    if (body == null) return const [];

    try {
      final rows = jsonDecode(body) as List;
      final results = <PlaceResult>[];
      for (final row in rows) {
        final map = row as Map<String, dynamic>;
        final lat = double.tryParse('${map['lat']}');
        final lon = double.tryParse('${map['lon']}');
        final name = map['display_name'] as String?;
        if (lat == null || lon == null || name == null || name.isEmpty) continue;
        if (!isInIlocosNorte(LatLng(lat, lon))) continue;
        results.add(PlaceResult(displayName: name, point: LatLng(lat, lon)));
      }
      return results;
    } catch (e, s) {
      AppLog.warn('searchPlaces: bad Nominatim response', e, s);
      return const [];
    }
  }

  /// Returns the response body, or null on any failure.
  Future<String?> _get(Uri uri) async {
    await _throttle();
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(MapConfig.networkTimeout);
      if (response.statusCode != 200) return null;
      return utf8.decode(response.bodyBytes);
    } catch (e, s) {
      AppLog.warn('Nominatim request failed: $uri', e, s);
      return null;
    }
  }

  /// Nominatim wants an identifying User-Agent. Browsers forbid setting that
  /// header, so on web the origin identifies us instead.
  Map<String, String> get _headers => kIsWeb
      ? const {'Accept': 'application/json'}
      : const {
          'Accept': 'application/json',
          'User-Agent': 'iTULOD/1.0 (${MapConfig.userAgentPackageName})',
        };

  Future<void> _throttle() async {
    final last = _lastCall;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      final wait = MapConfig.geocodeMinInterval - elapsed;
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    _lastCall = DateTime.now();
  }
}
