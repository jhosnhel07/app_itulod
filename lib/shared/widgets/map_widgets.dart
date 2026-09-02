import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/constants/map_config.dart';

/// The satellite basemap, configured once so the picker and the route preview
/// always request tiles the same way: Esri "World Imagery" aerial photography
/// with transparent road- and place-label overlays on top ("hybrid" view).
///
/// [tileProvider] exists as a seam for widget tests, which inject a provider
/// that returns a transparent image instead of hitting the network.
class OsmTileLayer extends StatelessWidget {
  final TileProvider? tileProvider;

  const OsmTileLayer({super.key, this.tileProvider});

  @override
  Widget build(BuildContext context) {
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
/// Esri tiles, not a nicety — do not remove it.
class OsmAttribution extends StatelessWidget {
  final Alignment alignment;

  const OsmAttribution({super.key, this.alignment = Alignment.bottomRight});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(MapConfig.attributionUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              MapConfig.attribution,
              style: AppTypography.caption.copyWith(
                fontSize: 10,
                color: AppColors.neutral600,
              ),
            ),
          ),
        ),
      ),
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
