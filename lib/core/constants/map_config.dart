import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';

/// Every knob the map feature turns, in one place.
class MapConfig {
  MapConfig._();

  // ── Tiles ─────────────────────────────────────────────────────────────

  /// Public Mapbox token (MAPBOX_TOKEN in .env — the same pk.… token the web
  /// app uses in js/map.js). With it, every map uses the web's Mapbox style;
  /// without it (e.g. widget tests) the maps fall back to the Esri tiles below.
  static String? get mapboxToken {
    if (!dotenv.isInitialized) return null;
    final token = dotenv.env['MAPBOX_TOKEN']?.trim();
    return (token == null || token.isEmpty) ? null : token;
  }

  /// Mapbox "Satellite Streets" — the web's STYLE
  /// (mapbox://styles/mapbox/satellite-streets-v12) served as raster tiles,
  /// so the app's maps look the same as the web's. Roads and labels are
  /// baked in, so no overlays are needed.
  static const String mapboxTileUrl =
      'https://api.mapbox.com/styles/v1/mapbox/satellite-streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}';

  static const String mapboxAttribution = '© Mapbox © OpenStreetMap';
  static const String mapboxFeedbackUrl = 'https://www.mapbox.com/map-feedback/';

  /// Esri "World Imagery" — global satellite / aerial photography. Free and
  /// key-free for light use; move to a paid imagery host (Esri, MapTiler,
  /// Mapbox) before a real launch. Note the `{z}/{y}/{x}` order.
  static const String tileUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Transparent reference overlays drawn on top of the imagery so the map
  /// reads as a "hybrid" view: roads with names, then town / place labels.
  static const List<String> overlayTileUrls = [
    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
  ];

  /// Sent as part of the User-Agent on every tile request. Some hosts block
  /// unidentified clients, and flutter_map defaults this to 'unknown'.
  static const String userAgentPackageName = 'com.itulod.app';

  /// Esri imagery serves native tiles well past z19 in cities; cap at 19 to
  /// match [maxZoom] and keep the reference overlays aligned.
  static const int maxNativeZoom = 19;

  /// Attribution for the Esri basemap — keep the overlay visible.
  static const String attribution =
      'Imagery © Esri, Maxar, Earthstar Geographics';
  static const String attributionUrl =
      'https://www.esri.com/en-us/legal/terms/data-attributions';

  // ── Geocoding & routing ───────────────────────────────────────────────

  static const String nominatimBase = 'https://nominatim.openstreetmap.org';

  /// Public OSRM demo server. No SLA, so every call site treats a failure
  /// as "fall back to the straight-line estimate".
  static const String osrmBase = 'https://router.project-osrm.org';

  /// Nominatim asks for at most one request per second.
  static const Duration geocodeMinInterval = Duration(seconds: 1);

  /// How long the map must sit still before we reverse-geocode the pin.
  static const Duration pinSettleDelay = Duration(milliseconds: 450);

  static const Duration networkTimeout = Duration(seconds: 10);

  /// Bias place search to the Philippines.
  static const String searchCountryCodes = 'ph';

  // ── Distance ──────────────────────────────────────────────────────────

  /// Straight-line km × this ≈ road km. Used when OSRM is unreachable.
  static const double roadDistanceFactor = 1.3;

  // ── Camera ────────────────────────────────────────────────────────────

  /// Where the picker opens when the device location is unavailable.
  /// Change this to your service area.
  static final LatLng defaultCenter = LatLng(18.1977, 120.5936); // Laoag City — iTULOD serves Ilocos Norte

  static const double pickerZoom = 16;
  static const double minZoom = 4;
  static const double maxZoom = 19;
}
