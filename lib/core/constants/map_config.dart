import 'package:latlong2/latlong.dart';

/// Every knob the map feature turns, in one place.
class MapConfig {
  MapConfig._();

  // ── Tiles ─────────────────────────────────────────────────────────────

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
