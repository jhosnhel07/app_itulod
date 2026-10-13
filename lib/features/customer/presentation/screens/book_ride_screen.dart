import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/route_service.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/location_picker_field.dart';
import '../widgets/route_preview_map.dart';
import '../widgets/riders_near_you_map.dart';
import '../providers/saved_addresses_provider.dart';
import 'booking_confirmation_screen.dart';
import 'map_picker_screen.dart';

class BookRideScreen extends ConsumerStatefulWidget {
  const BookRideScreen({super.key});

  @override
  ConsumerState<BookRideScreen> createState() => _BookRideScreenState();
}

class _BookRideScreenState extends ConsumerState<BookRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();

  /// Coordinates behind the two address fields. Both are set by the map picker,
  /// which is the only way to fill those fields.
  LatLng? _pickupPoint;
  LatLng? _destinationPoint;

  final List<TextEditingController> _stopControllers = [];
  final List<LatLng?> _stopPoints = [];
  static const int _maxStops = 3;

  /// Road route from OSRM. Null means it hasn't answered (or failed), in which
  /// case the straight-line estimate stands in.
  RouteResult? _route;
  bool _routing = false;
  int _routeToken = 0;

  VehicleModel? _vehicle;
  String _paymentMethod = 'cash';
  DateTime? _scheduledFor;

  bool get _hasBothPoints => _pickupPoint != null && _destinationPoint != null;

  /// Kilometres for the fare, best source first: real road distance, then
  /// straight line scaled by the road factor. Null until both pins are down —
  /// showing a number before then would be inventing one.
  double? get _distanceKm {
    if (_route != null) return _route!.distanceKm;
    final pickup = _pickupPoint;
    final destination = _destinationPoint;
    if (pickup == null || destination == null) return null;
    
    double total = 0;
    LatLng prev = pickup;
    for (final stop in _stopPoints) {
      if (stop != null) {
        total += FareEstimator.roadDistanceKm(prev, stop);
        prev = stop;
      }
    }
    total += FareEstimator.roadDistanceKm(prev, destination);
    return total;
  }

  double? get _fare {
    final km = _distanceKm;
    if (km == null) return null;
    final vehicles = ref.read(vehiclesListProvider).value ?? [];
    final vehicle = _vehicle ?? (vehicles.isNotEmpty ? vehicles.first : null);
    if (vehicle == null) return null;
    return FareEstimator.estimateFare(vehicle, km);
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    for (final c in _stopControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Location picking ──────────────────────────────────────────────────

  Future<void> _pickLocation({required bool isPickup, int? stopIndex}) async {
    final title = isPickup ? 'Set pickup location' : (stopIndex != null ? 'Set stop ${stopIndex + 1}' : 'Set destination');
    final initialCenter = isPickup ? _pickupPoint : (stopIndex != null ? _stopPoints[stopIndex] : _destinationPoint) ?? _pickupPoint;
    final initialAddress = isPickup
        ? _nullIfEmpty(_pickupController.text)
        : (stopIndex != null ? _nullIfEmpty(_stopControllers[stopIndex].text) : _nullIfEmpty(_destinationController.text));

    // Ask user to pick from saved addresses or map
    final savedAddresses = ref.read(savedAddressesProvider).value ?? [];
    PickedPlace? picked;

    if (savedAddresses.isNotEmpty) {
      picked = await showModalBottomSheet<PickedPlace>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.map_rounded),
                title: const Text('Choose on Map'),
                onTap: () {
                  Navigator.pop(ctx, const PickedPlace(address: '', point: LatLng(0,0))); // Sentinel value for map
                },
              ),
              const Divider(),
              for (final addr in savedAddresses)
                ListTile(
                  leading: const Icon(Icons.location_on_rounded),
                  title: Text(addr.label),
                  subtitle: Text(addr.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx, PickedPlace(address: addr.address, point: addr.point));
                  },
                ),
            ],
          ),
        ),
      );
    } else {
      // Just map if no saved addresses
      picked = const PickedPlace(address: '', point: LatLng(0,0));
    }

    if (picked == null) return;
    if (picked.address.isEmpty) { // Sentinel value, open map
      picked = await MapPickerScreen.show(
        context,
        title: title,
        pinColor: isPickup ? AppColors.success : AppColors.danger,
        initialCenter: initialCenter,
        initialAddress: initialAddress,
      );
    }
    
    if (picked == null || !mounted) return;

    setState(() {
      if (isPickup) {
        _pickupController.text = picked!.address;
        _pickupPoint = picked.point;
      } else if (stopIndex != null) {
        _stopControllers[stopIndex].text = picked!.address;
        _stopPoints[stopIndex] = picked.point;
      } else {
        _destinationController.text = picked!.address;
        _destinationPoint = picked.point;
      }
    });
    _refreshRoute();
  }

  static String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value;

  /// Asks the routing service for the road geometry. Failure is expected and
  /// fine — [_distanceKm] already has a usable answer without it.
  Future<void> _refreshRoute() async {
    final pickup = _pickupPoint;
    final destination = _destinationPoint;
    final token = ++_routeToken;

    if (pickup == null || destination == null) {
      setState(() {
        _route = null;
        _routing = false;
      });
      return;
    }

    setState(() {
      _route = null;
      _routing = true;
    });

    final waypoints = [
      pickup,
      ..._stopPoints.where((p) => p != null).cast<LatLng>(),
      destination,
    ];

    final result = await ref.read(routeServiceProvider).fetchRouteWaypoints(waypoints);
    if (!mounted || token != _routeToken) return;
    setState(() {
      _route = result;
      _routing = false;
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────

  void _submit() {
    if (!_formKey.currentState!.validate() || _vehicle == null) return;
    final fare = _fare;
    if (fare == null) return;

    // Same window the web enforces (customer.js wireRideForm).
    final scheduled = _scheduledFor;
    if (scheduled != null) {
      final now = DateTime.now();
      String? problem;
      if (scheduled.isBefore(now.add(const Duration(minutes: 10)))) {
        problem = 'Scheduled pickup must be at least 10 minutes from now.';
      } else if (scheduled.isAfter(now.add(const Duration(days: 7)))) {
        problem = 'Scheduled pickup can be at most 7 days from now.';
      }
      if (problem != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(problem), backgroundColor: AppColors.danger),
        );
        return;
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingConfirmationScreen(
          vehicle: _vehicle!,
          pickupAddress: _pickupController.text,
          destinationAddress: _destinationController.text,
          pickupPoint: _pickupPoint,
          destinationPoint: _destinationPoint,
          stops: [
            for (var i = 0; i < _stopControllers.length; i++)
              if (_stopControllers[i].text.trim().isNotEmpty)
                (address: _stopControllers[i].text, point: _stopPoints[i]),
          ],
          distanceKm: _distanceKm,
          fare: fare,
          paymentMethod: _paymentMethod,
          scheduledFor: _scheduledFor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(savedAddressesProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Book a Ride')),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load vehicles.\n$e', textAlign: TextAlign.center)),
        data: (vehicles) {
          _vehicle ??= vehicles.isNotEmpty ? vehicles.first : null;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              onChanged: () => setState(() {}),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RidersNearYouMap(),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          LocationPickerField(
                            controller: _pickupController,
                            hint: 'Tap to set pickup on the map',
                            isPickup: true,
                            emptyError: 'Set a pickup location',
                            onTap: () => _pickLocation(isPickup: true),
                          ),
                          const SizedBox(height: 14),
                          for (int i = 0; i < _stopControllers.length; i++) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: LocationPickerField(
                                    controller: _stopControllers[i],
                                    hint: 'Tap to set stop ${i + 1}',
                                    isPickup: false,
                                    emptyError: 'Set stop location',
                                    onTap: () => _pickLocation(isPickup: false, stopIndex: i),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                                  onPressed: () {
                                    setState(() {
                                      _stopControllers[i].dispose();
                                      _stopControllers.removeAt(i);
                                      _stopPoints.removeAt(i);
                                    });
                                    _refreshRoute();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],
                          LocationPickerField(
                            controller: _destinationController,
                            hint: 'Tap to set destination on the map',
                            isPickup: false,
                            emptyError: 'Set a destination',
                            onTap: () => _pickLocation(isPickup: false),
                          ),
                          if (_stopControllers.length < _maxStops) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _stopControllers.add(TextEditingController());
                                  _stopPoints.add(null);
                                });
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add Stop'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_hasBothPoints) ...[
                    const SizedBox(height: 16),
                    RoutePreviewMap(
                      pickup: _pickupPoint!,
                      destination: _destinationPoint!,
                      routePoints: _route?.points,
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<VehicleModel>(
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle type',
                      prefixIcon: Icon(Icons.directions_rounded),
                    ),
                    items: vehicles
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('${v.name} — from ${Formatters.currency(v.baseFare)}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _vehicle = v),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(_scheduledFor == null ? 'Schedule for later (Optional)' : 'Scheduled for ${Formatters.date(_scheduledFor!)}'),
                      trailing: _scheduledFor == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _scheduledFor = null),
                            ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 7)),
                        );
                        if (date == null) return;
                        if (!mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time == null) return;
                        setState(() {
                          _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Payment method', style: AppTypography.bodyBold),
                          const SizedBox(height: 10),
                          RadioGroup<String>(
                            groupValue: _paymentMethod,
                            onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                            child: Column(
                              children: [
                                ...['cash', 'gcash', 'wallet'].map((method) => RadioListTile<String>(
                                      value: method,
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      activeColor: AppColors.primary,
                                      title: Text(_methodLabel(method),
                                          style: AppTypography.bodyMedium.copyWith(fontSize: 14)),
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _fareBox(),
                  const SizedBox(height: 24),
                  AppButton(
                    text: 'Review Booking',
                    onPressed: vehicles.isEmpty ? null : _submit,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fareBox() {
    final km = _distanceKm;
    final fare = _fare;

    final baseFare = _vehicle?.baseFare ?? 0.0;
    final distanceFare = (fare != null) ? fare - baseFare : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESTIMATED DISTANCE', style: AppTypography.caption),
                    Text(Formatters.distance(km), style: AppTypography.h3),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.cardBorder),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('ESTIMATED FARE', style: AppTypography.caption),
                    Text(fare == null ? '—' : Formatters.currency(fare),
                        style: AppTypography.h3.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
            ],
          ),
          if (fare != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.cardBorder),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Base Fare', style: AppTypography.caption.copyWith(color: AppColors.neutral500)),
                Text(Formatters.currency(baseFare), style: AppTypography.caption.copyWith(color: AppColors.neutral700)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Distance Charge', style: AppTypography.caption.copyWith(color: AppColors.neutral500)),
                Text(Formatters.currency(distanceFare!), style: AppTypography.caption.copyWith(color: AppColors.neutral700)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(_sourceIcon, size: 13, color: AppColors.neutral500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_sourceLabel,
                    style: AppTypography.caption.copyWith(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData get _sourceIcon {
    if (!_hasBothPoints) return Icons.touch_app_outlined;
    if (_routing) return Icons.sync_rounded;
    return _route != null ? Icons.route_rounded : Icons.straighten_rounded;
  }

  /// Says where the number came from, so an estimate never masquerades as a
  /// measured road distance.
  String get _sourceLabel {
    if (!_hasBothPoints) return 'Set both locations on the map to see the fare.';
    if (_routing) return 'Measuring the road route…';
    if (_route != null) {
      final minutes = _route!.duration.inMinutes;
      final eta = minutes > 0 ? ' • about $minutes min' : '';
      return 'Measured along roads$eta';
    }
    return 'Straight-line estimate — routing service unavailable';
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'gcash':
        return 'GCash';
      case 'wallet':
        return 'Wallet';
      case 'card':
        return 'Card';
      default:
        return 'Cash on arrival';
    }
  }
}
