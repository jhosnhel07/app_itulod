import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/constants/ilocos_norte.dart';
import '../../../../core/constants/map_config.dart';
import '../../../../core/services/geocoding_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/route_service.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/map_widgets.dart';
import '../providers/saved_addresses_provider.dart';

/// What the picker hands back: where the pin was, and what that place is called.
class PickedPlace {
  final LatLng point;
  final String address;

  const PickedPlace({required this.point, required this.address});
}

/// Both ends of a trip, from [MapPickerScreen.showRoute]. Either can be null
/// when the customer only set one of them.
class PickedRoute {
  final PickedPlace? pickup;
  final PickedPlace? dropoff;

  const PickedRoute({this.pickup, this.dropoff});
}

/// Which pin a tap on the map sets (route mode).
enum PinMode { pickup, dropoff }

/// Full-screen "Set location on map" — the app version of the web's booking
/// map (js/map.js): tap the map to drop the pin, on the same Mapbox style.
///
/// * **Route mode** ([showRoute]) — the web's "1 Set Pickup / 2 Set Drop-off"
///   map: tap to set the pickup, then it switches to drop-off by itself; both
///   pins and the road route show together.
/// * **Single mode** ([show]) — one pin (delivery address, a saved address,
///   a ride stop). [fixedPoint] can show a place that isn't editable, like
///   the restaurant a food order comes from.
class MapPickerScreen extends ConsumerStatefulWidget {
  /// Shown in the app bar.
  final String title;

  /// Single mode: pin colour.
  final Color pinColor;

  /// Single mode: an already-chosen spot (pin shown from the start).
  final LatLng? initialCenter;

  /// Single mode: [initialCenter]'s address, so it doesn't flash empty.
  final String? initialAddress;

  /// Route mode: pickup + drop-off pins with the mode switch.
  final bool routeMode;
  final PickedPlace? initialPickup;
  final PickedPlace? initialDropoff;
  final PinMode startMode;

  /// A place shown for reference that can't be moved (e.g. the restaurant).
  final LatLng? fixedPoint;

  /// Test seam: injecting a provider keeps tiles off the network.
  final TileProvider? tileProvider;

  /// Test seam: skips the device-location request on open.
  final bool autoLocate;

  const MapPickerScreen({
    super.key,
    required this.title,
    this.pinColor = LocationDotPin.address,
    this.initialCenter,
    this.initialAddress,
    this.routeMode = false,
    this.initialPickup,
    this.initialDropoff,
    this.startMode = PinMode.pickup,
    this.fixedPoint,
    this.tileProvider,
    this.autoLocate = true,
  });

  /// One pin. Returns the chosen place, or null if dismissed.
  static Future<PickedPlace?> show(
    BuildContext context, {
    required String title,
    Color pinColor = LocationDotPin.address,
    LatLng? initialCenter,
    String? initialAddress,
    LatLng? fixedPoint,
  }) {
    return Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          title: title,
          pinColor: pinColor,
          initialCenter: initialCenter,
          initialAddress: initialAddress,
          fixedPoint: fixedPoint,
        ),
      ),
    );
  }

  /// Pickup + drop-off, starting on [startWith]. Returns both, or null if
  /// dismissed.
  static Future<PickedRoute?> showRoute(
    BuildContext context, {
    PickedPlace? pickup,
    PickedPlace? dropoff,
    PinMode startWith = PinMode.pickup,
  }) {
    return Navigator.of(context).push<PickedRoute>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          title: 'Set location on map',
          routeMode: true,
          initialPickup: pickup,
          initialDropoff: dropoff,
          startMode: startWith,
        ),
      ),
    );
  }

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  static const double _pinZoom = 16;
  static const Color _routeColor = Color(0xFF2196F3);
  static const Color _activeBlue = Color(0xFF2196F3);

  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// Route-mode pins; in single mode the one pin lives in [_pickup].
  PickedPlace? _pickup;
  PickedPlace? _dropoff;
  late PinMode _mode;

  /// Pins whose address is still being looked up.
  final Set<PinMode> _resolving = {};
  bool _locating = false;

  /// Whether a pin has been placed; a slow device fix arriving afterwards
  /// must not move the map away from it.
  bool _userChosePlace = false;

  List<LatLng>? _route;
  int _routeToken = 0;

  bool _searchOpen = false;
  List<PlaceResult> _results = const [];
  bool _searching = false;
  Timer? _searchDebounce;

  bool get _twoPins => widget.routeMode;

  @override
  void initState() {
    super.initState();
    _mode = _twoPins ? widget.startMode : PinMode.pickup;
    if (_twoPins) {
      _pickup = _inside(widget.initialPickup);
      _dropoff = _inside(widget.initialDropoff);
    } else {
      final start = widget.initialCenter;
      // A saved spot from before the Ilocos Norte limit could be outside it.
      if (start != null && isInIlocosNorte(start)) {
        _pickup = PickedPlace(point: start, address: widget.initialAddress ?? '');
      }
    }
    _userChosePlace = _pickup != null || _dropoff != null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A pin opened without its address gets one.
      if (!_twoPins && _pickup != null && _pickup!.address.isEmpty) {
        _lookup(PinMode.pickup, _pickup!.point);
      }
      if (_twoPins) _refreshRoute();
      if (!_userChosePlace && widget.autoLocate) _useMyLocation(silent: true);
    });
  }

  static PickedPlace? _inside(PickedPlace? p) =>
      (p != null && isInIlocosNorte(p.point)) ? p : null;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    super.dispose();
  }

  LatLng get _initialCenter =>
      _pickup?.point ?? _dropoff?.point ?? widget.fixedPoint ?? MapConfig.defaultCenter;

  PickedPlace? _pinFor(PinMode mode) => mode == PinMode.pickup ? _pickup : _dropoff;

  void _setPin(PinMode mode, PickedPlace? place) {
    if (mode == PinMode.pickup) {
      _pickup = place;
    } else {
      _dropoff = place;
    }
  }

  Color _colorFor(PinMode mode) {
    if (!_twoPins) return widget.pinColor;
    return mode == PinMode.pickup ? LocationDotPin.pickup : LocationDotPin.dropoff;
  }

  // ── Placing pins ──────────────────────────────────────────────────────

  /// Drops the active pin at [point] — a map tap, a search result, a saved
  /// address or the device location (web: _setStop).
  void _placePin(LatLng point, {String? address, bool moveCamera = false}) {
    if (!isInIlocosNorte(point)) {
      _snack(outsideServiceAreaMessage, AppColors.danger);
      return;
    }
    final mode = _mode;
    _userChosePlace = true;
    setState(() {
      _setPin(mode, PickedPlace(point: point, address: address ?? ''));
      // Web: once the pickup is set, the next tap sets the drop-off.
      if (_twoPins && mode == PinMode.pickup) _mode = PinMode.dropoff;
    });
    if (moveCamera) {
      _mapController.move(point, math.max(_mapController.camera.zoom, _pinZoom));
    }
    if (address == null) _lookup(mode, point);
    if (_twoPins) _refreshRoute();
  }

  Future<void> _lookup(PinMode mode, LatLng point) async {
    setState(() => _resolving.add(mode));
    final full = await ref.read(geocodingServiceProvider).reverseGeocode(point);
    if (!mounted) return;
    setState(() {
      final pin = _pinFor(mode);
      // Only if that pin hasn't been moved again meanwhile.
      if (pin != null && pin.point == point) {
        _setPin(
          mode,
          PickedPlace(
            point: point,
            address: full == null ? _coordinateLabel(point) : GeocodingService.shortenAddress(full),
          ),
        );
        _resolving.remove(mode);
      }
    });
  }

  static String _coordinateLabel(LatLng p) =>
      'Pinned location (${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';

  // ── Route ─────────────────────────────────────────────────────────────

  Future<void> _refreshRoute() async {
    final a = _pickup?.point, b = _dropoff?.point;
    final token = ++_routeToken;
    if (a == null || b == null) {
      if (_route != null) setState(() => _route = null);
      return;
    }
    setState(() => _route = [a, b]); // straight line until the road route arrives
    _fitPins();
    final result = await ref.read(routeServiceProvider).fetchRoute(a, b);
    if (!mounted || token != _routeToken) return;
    if (result != null && result.points.length > 1) {
      setState(() => _route = result.points);
      _fitPins();
    }
  }

  /// Frames both pins and the route, like the web's fitBounds.
  void _fitPins() {
    final points = [
      if (_pickup != null) _pickup!.point,
      if (_dropoff != null) _dropoff!.point,
      ...?_route,
    ];
    if (points.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(50, 70, 50, 50),
          maxZoom: 17,
        ));
      } catch (_) {
        // Map not laid out yet — keep the current camera.
      }
    });
  }

  // ── My location ───────────────────────────────────────────────────────

  /// [silent]: the automatic attempt when the picker opens — it only centres
  /// the map (no pin), says nothing on failure, and gives up if a pin has
  /// already been placed. The button drops the active pin at the device.
  Future<void> _useMyLocation({bool silent = false}) async {
    setState(() => _locating = true);
    final result = await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);

    if (!result.isSuccess) {
      if (!silent) _snack(result.message, AppColors.warning);
      return;
    }
    final point = result.point!;
    if (!isInIlocosNorte(point)) {
      if (!silent) {
        _snack(
          "You're outside Ilocos Norte — iTULOD only serves the province. Tap your spot on the map instead.",
          AppColors.warning,
        );
      }
      return;
    }
    if (silent) {
      if (!_userChosePlace) _mapController.move(point, _pinZoom);
      return;
    }
    _placePin(point, moveCamera: true);
  }

  // ── Search ────────────────────────────────────────────────────────────

  void _openSearch() {
    setState(() => _searchOpen = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() {
      _searchOpen = false;
      _results = const [];
      _searching = false;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final found = await ref.read(geocodingServiceProvider).searchPlaces(value);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    });
  }

  void _choose(LatLng point, String address) {
    _closeSearch();
    _placePin(point, address: address, moveCamera: true);
  }

  // ── Done ──────────────────────────────────────────────────────────────

  bool get _canFinish => _twoPins ? (_pickup != null || _dropoff != null) : _pickup != null;

  PickedPlace? _final(PickedPlace? p) => p == null
      ? null
      : PickedPlace(
          point: p.point,
          // Never hand back an empty address: the booking form requires one.
          address: p.address.trim().isEmpty ? _coordinateLabel(p.point) : p.address.trim(),
        );

  void _finish() {
    if (_twoPins) {
      Navigator.of(context).pop(PickedRoute(pickup: _final(_pickup), dropoff: _final(_dropoff)));
    } else {
      Navigator.of(context).pop(_final(_pickup));
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_twoPins) _modeSwitch(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
            child: Row(
              children: [
                Icon(Icons.info_rounded, size: 14, color: AppColors.iconMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    !_twoPins
                        ? 'Tap on the map to set the location.'
                        : _mode == PinMode.pickup
                            ? 'Tap on the map to set your pickup location.'
                            : 'Tap on the map to set your drop-off location.',
                    style: AppTypography.caption,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    _map(),
                    _zoomButtons(),
                    _searchOverlay(),
                    Positioned(
                      right: 10,
                      bottom: 36,
                      child: FloatingActionButton.small(
                        heroTag: 'map-picker-locate',
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.primary,
                        tooltip: 'Use my location',
                        onPressed: _locating ? null : _useMyLocation,
                        child: _locating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _bottomPanel(),
        ],
      ),
    );
  }

  /// "1 Set Pickup | 2 Set Drop-off" — the web's map mode buttons.
  Widget _modeSwitch() {
    Widget button(PinMode mode, String number, IconData icon, String label) {
      final active = _mode == mode;
      final done = _pinFor(mode) != null;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _mode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? _activeBlue
                        : done
                            ? AppColors.success
                            : AppColors.neutral200,
                  ),
                  child: done && !active
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : Text(
                          number,
                          style: AppTypography.caption.copyWith(
                            color: active ? Colors.white : AppColors.neutral600,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: active ? _activeBlue : AppColors.neutral500),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyBold.copyWith(
                      fontSize: 14,
                      color: active ? _activeBlue : AppColors.neutral600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          button(PinMode.pickup, '1', Icons.location_on_rounded, 'Set Pickup'),
          const SizedBox(width: 4),
          button(PinMode.dropoff, '2', Icons.flag_rounded, 'Set Drop-off'),
        ],
      ),
    );
  }

  Widget _map() {
    Marker pin(LatLng point, Color color) => Marker(
          point: point,
          width: 36,
          height: 36,
          alignment: Alignment.topCenter,
          child: LocationDotPin(color: color),
        );
    final fixed = widget.fixedPoint;
    final route = _route;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: (_pickup != null || _dropoff != null) ? _pinZoom : 14,
        minZoom: 8,
        maxZoom: MapConfig.maxZoom,
        // Keep the map on Ilocos Norte, like the web's maxBounds.
        cameraConstraint: CameraConstraint.containCenter(bounds: ilocosNorteMaxBounds),
        onTap: (_, point) {
          if (_searchOpen) {
            _closeSearch();
            return;
          }
          _placePin(point);
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        OsmTileLayer(tileProvider: widget.tileProvider),
        if (route != null && route.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: route, color: _routeColor.withValues(alpha: 0.85), strokeWidth: 4),
          ]),
        MarkerLayer(markers: [
          if (fixed != null) pin(fixed, LocationDotPin.pickup),
          if (_pickup != null) pin(_pickup!.point, _colorFor(PinMode.pickup)),
          if (_dropoff != null) pin(_dropoff!.point, _colorFor(PinMode.dropoff)),
        ]),
        const OsmAttribution(alignment: Alignment.bottomLeft),
      ],
    );
  }

  Widget _zoomButtons() {
    Widget btn(IconData icon, String tip, double delta) => SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: tip,
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: 20, color: AppColors.neutral700),
            onPressed: () {
              final cam = _mapController.camera;
              _mapController.move(cam.center, (cam.zoom + delta).clamp(8.0, MapConfig.maxZoom));
            },
          ),
        );
    return Positioned(
      top: 10,
      right: 10,
      child: Material(
        color: AppColors.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            btn(Icons.add_rounded, 'Zoom in', 1),
            Container(width: 24, height: 1, color: AppColors.neutral200),
            btn(Icons.remove_rounded, 'Zoom out', -1),
          ],
        ),
      ),
    );
  }

  /// The web's round search button on the map, which opens a search box.
  Widget _searchOverlay() {
    if (!_searchOpen) {
      return Positioned(
        top: 10,
        left: 10,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          elevation: 2,
          child: IconButton(
            tooltip: 'Search a place',
            icon: Icon(Icons.search_rounded, color: AppColors.neutral700),
            onPressed: _openSearch,
          ),
        ),
      );
    }
    return Positioned(
      top: 10,
      left: 10,
      right: 58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surface,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search a place',
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: 'Close search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _closeSearch,
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_results.isNotEmpty)
            _list([
              for (final place in _results)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.place_outlined, size: 18, color: AppColors.neutral500),
                  title: Text(
                    place.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(fontSize: 13),
                  ),
                  onTap: () => _choose(place.point, GeocodingService.shortenAddress(place.displayName)),
                ),
            ])
          else if (_searchController.text.trim().isEmpty)
            Consumer(builder: (context, ref, _) {
              final saved = ref.watch(savedAddressesProvider).valueOrNull ?? const [];
              if (saved.isEmpty) return const SizedBox.shrink();
              return _list([
                for (final addr in saved)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.star_rounded, size: 18, color: AppColors.primary),
                    title: Text(addr.label, style: AppTypography.bodyBold.copyWith(fontSize: 13)),
                    subtitle: Text(
                      addr.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                    onTap: () => _choose(addr.point, addr.address),
                  ),
              ]);
            }),
        ],
      ),
    );
  }

  Widget _list(List<Widget> tiles) => Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: tiles.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.neutral100),
            itemBuilder: (_, i) => tiles[i],
          ),
        ),
      );

  Widget _bottomPanel() {
    Widget row(PinMode mode, String label) {
      final pin = _pinFor(mode);
      final active = _twoPins && _mode == mode;
      final resolving = _resolving.contains(mode) || (pin != null && pin.address.isEmpty);
      final text = pin == null ? 'Tap the map to set' : (resolving ? 'Finding address…' : pin.address);
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _twoPins ? () => setState(() => _mode = mode) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? _activeBlue.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(width: 24, height: 26, child: LocationDotPin(color: _colorFor(mode), size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(), style: AppTypography.caption.copyWith(letterSpacing: 0.8, fontSize: 10.5)),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: pin == null ? AppTypography.caption : AppTypography.bodyMedium.copyWith(fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              if (pin != null && !resolving)
                IconButton(
                  tooltip: 'Save location',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.star_outline_rounded, size: 20),
                  color: AppColors.primary,
                  onPressed: () => _promptSaveAddress(pin),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_twoPins) ...[
                row(PinMode.pickup, 'Pickup'),
                row(PinMode.dropoff, 'Drop-off'),
              ] else
                row(PinMode.pickup, 'Selected location'),
              const SizedBox(height: 8),
              AppButton(
                text: 'Done',
                icon: Icons.check_rounded,
                onPressed: _canFinish ? _finish : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptSaveAddress(PickedPlace place) async {
    final labelController = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.address, style: AppTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label (e.g. Home, Work)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, labelController.text), child: const Text('Save')),
        ],
      ),
    );

    if (label == null || label.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(savedAddressesProvider.notifier)
          .add(label.trim(), place.address, place.point.latitude, place.point.longitude);
      if (!mounted) return;
      if (saved != null) messenger.showSnackBar(const SnackBar(content: Text('Address saved')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to save address: $e')));
    }
  }
}
