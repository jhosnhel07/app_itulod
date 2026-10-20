import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_typography.dart';
import '../../core/constants/map_config.dart';

/// The satellite basemap, configured once so every map requests tiles the
/// same way: Mapbox "Satellite Streets" — the web's map style — when a
/// MAPBOX_TOKEN is configured, otherwise Esri "World Imagery" with road- and
/// place-label overlays on top ("hybrid" view).
///
/// [tileProvider] exists as a seam for widget tests, which inject a provider
/// that returns a transparent image instead of hitting the network.
class OsmTileLayer extends StatelessWidget {
  final TileProvider? tileProvider;

  const OsmTileLayer({super.key, this.tileProvider});

  @override
  Widget build(BuildContext context) {
    final mapboxToken = MapConfig.mapboxToken;
    if (mapboxToken != null) {
      return TileLayer(
        urlTemplate: MapConfig.mapboxTileUrl,
        additionalOptions: {'accessToken': mapboxToken},
        userAgentPackageName: MapConfig.userAgentPackageName,
        maxNativeZoom: MapConfig.maxNativeZoom,
        tileProvider: tileProvider,
      );
    }
    return Stack(
      children: [
        TileLayer(
          urlTemplate: MapConfig.tileUrl,
          userAgentPackageName: MapConfig.userAgentPackageName,
          maxNativeZoom: MapConfig.maxNativeZoom,
          tileProvider: tileProvider,
        ),
        for (final url in MapConfig.overlayTileUrls)
          TileLayer(
            urlTemplate: url,
            userAgentPackageName: MapConfig.userAgentPackageName,
            maxNativeZoom: MapConfig.maxNativeZoom,
            tileProvider: tileProvider,
          ),
      ],
    );
  }
}

/// Basemap attribution. Displaying this is a licence condition of using the
/// Mapbox / Esri tiles, not a nicety — do not remove it. For Mapbox it's the
/// "mapbox" wordmark plus "© Mapbox © OpenStreetMap" (tap: improve this map).
class OsmAttribution extends StatelessWidget {
  final Alignment alignment;

  const OsmAttribution({super.key, this.alignment = Alignment.bottomRight});

  @override
  Widget build(BuildContext context) {
    final mapbox = MapConfig.mapboxToken != null;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(mapbox ? MapConfig.mapboxFeedbackUrl : MapConfig.attributionUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mapbox) ...[
                  Text(
                    'mapbox',
                    style: AppTypography.caption.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    mapbox ? MapConfig.mapboxAttribution : MapConfig.attribution,
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: const Color(0xFF4B5563),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The web's map marker (js/map.js _makeMarker): Font Awesome "location-dot"
/// with a white halo so it reads on satellite imagery. Place it with
/// `Marker(alignment: Alignment.topCenter, …)` so its tip sits on the point.
class LocationDotPin extends StatelessWidget {
  final Color color;
  final double size;

  const LocationDotPin({super.key, required this.color, this.size = 30});

  /// Web colours: pickup, drop-off, a single address.
  static const Color pickup = Color(0xFF22C55E);
  static const Color dropoff = Color(0xFFEF4444);
  static const Color address = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final halo = FaIcon(FontAwesomeIcons.locationDot, size: size + 3, color: Colors.white);
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))],
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: size * 0.3, height: size * 0.3),
          ),
        ),
        halo,
        Padding(
          padding: const EdgeInsets.only(bottom: 1.5),
          child: FaIcon(FontAwesomeIcons.locationDot, size: size, color: color),
        ),
      ],
    );
  }
}

/// Teardrop map marker. [color] separates pickup (green) from destination (red).
class MapPin extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double size;

  const MapPin({
    super.key,
    required this.color,
    this.icon = Icons.place_rounded,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      shadows: const [
        Shadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    );
  }
}
