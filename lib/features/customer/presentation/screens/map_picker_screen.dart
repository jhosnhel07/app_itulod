import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/constants/map_config.dart';
import '../../../../core/services/geocoding_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/map_widgets.dart';
import '../providers/saved_addresses_provider.dart';

/// What the picker hands back: where the pin was, and what that place is called.
class PickedPlace {
  final LatLng point;
  final String address;

  const PickedPlace({required this.point, required this.address});
}

/// Full-screen map for choosing one location.
///
/// A pushed route rather than a bottom sheet on purpose — a draggable sheet
/// competes with the map's own pan gesture.
///
/// The pin is fixed at the centre of the screen and the map moves underneath
/// it. That beats tap-to-place on a phone, where the target would otherwise sit
/// under the user's thumb.
class MapPickerScreen extends ConsumerStatefulWidget {
  /// Shown in the app bar, e.g. 'Set pickup location'.
  final String title;

  /// Marker colour, so pickup and destination read differently.
  final Color pinColor;

  /// Where to open. When null the picker asks the device for a location and
  /// falls back to [MapConfig.defaultCenter].
  final LatLng? initialCenter;

  /// Pre-fills the address bar so a re-open doesn't flash empty.
  final String? initialAddress;

  /// Test seam: injecting a provider keeps tiles off the network.
  final TileProvider? tileProvider;

  /// Test seam: skips the device-location request on open.
  final bool autoLocate;

  const MapPickerScreen({
    super.key,
    required this.title,
    this.pinColor = AppColors.primary,
    this.initialCenter,
    this.initialAddress,
    this.tileProvider,
    this.autoLocate = true,
  });

  /// Pushes the picker and returns the chosen place, or null if dismissed.
  static Future<PickedPlace?> show(
    BuildContext context, {
    required String title,
    Color pinColor = AppColors.primary,
    LatLng? initialCenter,
    String? initialAddress,
  }) {
    return Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          title: title,
          pinColor: pinColor,
          initialCenter: initialCenter,
          initialAddress: initialAddress,
        ),
      ),
    );
  }

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  static const double _pinSize = 44;

  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// Not held in setState — nothing in the tree renders it directly, and
  /// onPositionChanged fires on every drag frame.
  late LatLng _center;

  String? _address;
  bool _resolving = false;
  bool _locating = false;

  Timer? _settleTimer;
  Timer? _searchDebounce;

  /// Guards against a slow reverse-geocode landing after a newer one.
  int _lookupToken = 0;

  /// Whether the user has already chosen a spot, by dragging the map or picking
  /// a search result. A device fix that arrives after that must not move the
  /// map — see [_useMyLocation].
  bool _userChosePlace = false;

  List<PlaceResult> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter ?? MapConfig.defaultCenter;
    _address = widget.initialAddress;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialCenter == null && widget.autoLocate) {
        _useMyLocation(silent: true);
      } else if (_address == null) {
        _reverseGeocode();
      }
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Address resolution ────────────────────────────────────────────────

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;

    _userChosePlace = true;

    // The label under the pin is now wrong. Show it as pending once, then
    // wait for the map to settle before spending a Nominatim call.
    if (!_resolving) setState(() => _resolving = true);
    _settleTimer?.cancel();
    _settleTimer = Timer(MapConfig.pinSettleDelay, _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    final token = ++_lookupToken;
    if (!_resolving) setState(() => _resolving = true);

    final target = _center;
    final address = await ref.read(geocodingServiceProvider).reverseGeocode(target);

    if (!mounted || token != _lookupToken) return;
    setState(() {
      _resolving = false;
      _address = address == null ? null : GeocodingService.shortenAddress(address);
    });
  }

  // ── My location ───────────────────────────────────────────────────────

  /// Moves the map to the device location.
  ///
  /// [silent] marks the automatic attempt made when the picker opens, which
  /// differs from a button press in two ways: it says nothing when the fix
  /// fails, and it gives up if the user has already chosen a spot. A cold GPS
  /// fix can take many seconds, easily long enough for someone to drag the map
  /// where they want it first — moving them at that point would throw away a
  /// deliberate choice.
  Future<void> _useMyLocation({bool silent = false}) async {
    setState(() => _locating = true);
    final result = await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);

    if (silent && _userChosePlace) {
      if (_address == null) await _reverseGeocode();
      return;
    }

    if (result.isSuccess) {
      _mapController.move(result.point!, MapConfig.pickerZoom);
      _center = result.point!;
      await _reverseGeocode();
      return;
    }

    // Opening the picker shouldn't nag about permissions — the map is usable
    // without a fix. Only complain when the button was pressed deliberately.
    if (silent) {
      if (_address == null) await _reverseGeocode();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Search ────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      if (_results.isNotEmpty || _searching) {
        setState(() {
          _results = const [];
          _searching = false;
        });
      }
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

  void _selectResult(PlaceResult place) {
    _searchFocus.unfocus();
    _searchController.clear();
    _userChosePlace = true;
    _mapController.move(place.point, MapConfig.pickerZoom);
    _center = place.point;
    _settleTimer?.cancel();
    _lookupToken++; // discard any in-flight reverse lookup
    setState(() {
      _results = const [];
      _searching = false;
      _resolving = false;
      _address = GeocodingService.shortenAddress(place.displayName);
    });
  }

  // ── Confirm ───────────────────────────────────────────────────────────

  void _confirm() {
    final address = _address?.trim();
    Navigator.of(context).pop(
      PickedPlace(
        point: _center,
        // Never hand back an empty string: the booking form requires an
        // address, and Nominatim can legitimately have no name for a spot.
        address: (address == null || address.isEmpty) ? _coordinateLabel : address,
      ),
    );
  }

  String get _coordinateLabel =>
      'Pinned location (${_center.latitude.toStringAsFixed(5)}, '
      '${_center.longitude.toStringAsFixed(5)})';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: MapConfig.pickerZoom,
              minZoom: MapConfig.minZoom,
              maxZoom: MapConfig.maxZoom,
              onPositionChanged: _onPositionChanged,
              interactionOptions: const InteractionOptions(
                // Rotation makes the fixed-pin metaphor confusing, and there
                // is nothing here that needs it.
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              OsmTileLayer(tileProvider: widget.tileProvider),
              const OsmAttribution(alignment: Alignment.bottomLeft),
            ],
          ),
          _centrePin(),
          _searchBar(),
          _bottomPanel(),
        ],
      ),
    );
  }

  /// The pin's tip must sit on the exact map centre, so the graphic is lifted
  /// by half its height.
  Widget _centrePin() {
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -_pinSize / 2),
          child: MapPin(color: widget.pinColor, size: _pinSize),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(12),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search a place',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 6),
            Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.neutral100),
                  itemBuilder: (_, i) {
                    final place = _results[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined,
                          size: 18, color: AppColors.neutral500),
                      title: Text(
                        place.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(fontSize: 13),
                      ),
                      onTap: () => _selectResult(place),
                    );
                  },
                ),
              ),
            ),
          ] else if (_searchController.text.isEmpty) ...[
            Consumer(
              builder: (context, ref, child) {
                final savedAsync = ref.watch(savedAddressesProvider);
                return savedAsync.when(
                  data: (saved) {
                    if (saved.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: saved.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: AppColors.neutral100),
                            itemBuilder: (_, i) {
                              final addr = saved[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.star_rounded,
                                    size: 18, color: AppColors.primary),
                                title: Text(
                                  addr.label,
                                  style: AppTypography.bodyBold.copyWith(fontSize: 13),
                                ),
                                subtitle: Text(
                                  addr.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(fontSize: 11),
                                ),
                                onTap: () {
                                  _searchFocus.unfocus();
                                  _userChosePlace = true;
                                  _mapController.move(addr.point, MapConfig.pickerZoom);
                                  _center = addr.point;
                                  _address = addr.address;
                                  setState(() {});
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 10),
            child: FloatingActionButton.small(
              heroTag: 'map-picker-locate',
              backgroundColor: Colors.white,
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
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [
                BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SELECTED LOCATION',
                        style: AppTypography.caption.copyWith(letterSpacing: 1)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 44,
                      child: _resolving
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text('Finding address…',
                                    style: AppTypography.captionDark),
                              ],
                            )
                          : Text(
                              _address ?? _coordinateLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(fontSize: 14),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            text: 'Confirm location',
                            icon: Icons.check_rounded,
                            onPressed: _confirm,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () => _promptSaveAddress(context),
                          icon: const Icon(Icons.star_outline_rounded),
                          tooltip: 'Save location',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.primary50,
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptSaveAddress(BuildContext context) async {
    final labelController = TextEditingController();
    final address = _address ?? _coordinateLabel;
    
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(address, style: AppTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, labelController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (label != null && label.trim().isNotEmpty && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final saved = await ref.read(savedAddressesProvider.notifier).add(
          label.trim(),
          address,
          _center.latitude,
          _center.longitude,
        );
        if (!mounted) return;
        if (saved != null) {
          messenger.showSnackBar(const SnackBar(content: Text('Address saved')));
        }
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Failed to save address: $e')));
      }
    }
  }
}
