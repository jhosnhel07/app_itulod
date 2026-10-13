import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/map_config.dart';
import '../../../../shared/widgets/map_widgets.dart';

/// Read-only map showing the trip: pickup pin, destination pin, and the route
/// between them.
///
/// [routePoints] is the real road geometry when the routing service answered.
/// When it is null or too short the straight line is drawn dashed instead, so
/// the customer can see at a glance that it is an estimate.
class RoutePreviewMap extends StatelessWidget {
  final LatLng pickup;
  final LatLng destination;
  final List<LatLng>? routePoints;
  final double height;

  /// Intermediate stops on a multi-stop ride, drawn as small numbered dots.
  final List<LatLng> stops;

  /// The assigned rider's live position while a trip is active. Not part of
  /// the camera fit, so the map doesn't jump every time the rider moves.
  final LatLng? liveRider;

  /// Test seam: keeps tiles off the network.
  final TileProvider? tileProvider;

  const RoutePreviewMap({
    super.key,
    required this.pickup,
    required this.destination,
    this.routePoints,
    this.height = 180,
    this.stops = const [],
    this.liveRider,
    this.tileProvider,
  });

  /// Breathing room between the trip and the edge of the box.
  static const _padding = EdgeInsets.all(36);

  /// Zoomed out far enough to show a whole city trip, close enough that a very
  /// short hop is still legible.
  static const _maxFitZoom = 16.0;

  bool get _hasRoute => (routePoints?.length ?? 0) >= 2;

  /// Centre and zoom that frame [line] inside a box of [size].
  ///
  /// This deliberately does the fit itself instead of handing the job to
  /// [MapOptions.initialCameraFit]. flutter_map applies `initialCameraFit` in a
  /// post-frame callback, *after* [TileLayer] has already run its one and only
  /// unprompted tile load against the camera it was born with. That load is
  /// wasted, and the layer then relies on the map's event stream to notice the
  /// fit and load again — which does not happen reliably for a map built after
  /// the first frame, as this one is: the route arrives from OSRM well after
  /// the booking form is on screen. The result was a preview that drew its
  /// polyline and pins over blank grey, with no tiles at all.
  ///
  /// Passing the fitted camera as the *initial* camera means the layer's first
  /// load is already the right one, so no event plumbing has to fire.
  ({LatLng center, double zoom}) _fitTo(Size size, List<LatLng> line) {
    final fallback = (center: line.first, zoom: MapConfig.pickerZoom);

    // A box smaller than its own padding makes the fit maths degenerate.
    if (!size.isFinite ||
        size.width <= _padding.horizontal ||
        size.height <= _padding.vertical) {
      return fallback;
    }

    final fitted = CameraFit.coordinates(
      coordinates: line,
      padding: _padding,
      // Caps the zoom when both pins are on the same spot, which would
      // otherwise fit a zero-area bounds at infinite zoom.
      maxZoom: _maxFitZoom,
    ).fit(
      MapCamera(
        crs: const Epsg3857(),
        center: line.first,
        zoom: MapConfig.pickerZoom,
        rotation: 0,
        nonRotatedSize: size,
        minZoom: MapConfig.minZoom,
        maxZoom: MapConfig.maxZoom,
      ),
    );

    if (!fitted.zoom.isFinite) return fallback;
    return (
      center: fitted.center,
      zoom: fitted.zoom.clamp(MapConfig.minZoom, MapConfig.maxZoom),
    );
  }

  @override
  Widget build(BuildContext context) {
    final line = _hasRoute ? routePoints! : [pickup, destination];

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final camera = _fitTo(constraints.biggest, line);

            return FlutterMap(
              // Changing initialCenter/initialZoom does not move an existing
              // camera, so the map is rebuilt when the trip changes — which is
              // exactly when the route replaces the straight-line guess.
              key: ValueKey(
                '${camera.center.latitude},${camera.center.longitude},'
                '${camera.zoom},${line.length}',
              ),
              options: MapOptions(
                initialCenter: camera.center,
                initialZoom: camera.zoom,
                minZoom: MapConfig.minZoom,
                maxZoom: MapConfig.maxZoom,
                // A preview inside a scrolling form should not steal drags.
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                OsmTileLayer(tileProvider: tileProvider),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: line,
                      color: AppColors.primary,
                      strokeWidth: 4,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                      pattern: _hasRoute
                          ? const StrokePattern.solid()
                          : StrokePattern.dashed(segments: const [10, 8]),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 34,
                      height: 34,
                      alignment: Alignment.topCenter,
                      child: const MapPin(color: AppColors.success, size: 34),
                    ),
                    Marker(
                      point: destination,
                      width: 34,
                      height: 34,
                      alignment: Alignment.topCenter,
                      child: const MapPin(color: AppColors.danger, size: 34),
                    ),
                    for (var i = 0; i < stops.length; i++)
                      Marker(
                        point: stops[i],
                        width: 22,
                        height: 22,
                        child: _Dot(label: '${i + 1}', color: AppColors.warning),
                      ),
                    if (liveRider != null)
                      Marker(
                        point: liveRider!,
                        width: 34,
                        height: 34,
                        child: const _RiderBadge(),
                      ),
                  ],
                ),
                const OsmAttribution(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final String label;
  final Color color;

  const _Dot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// The live rider marker — matches the web's motorcycle badge on the
/// booking-details map.
class _RiderBadge extends StatelessWidget {
  const _RiderBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 10),
        ],
      ),
      child: const Icon(Icons.two_wheeler_rounded, size: 20, color: AppColors.primary),
    );
  }
}
