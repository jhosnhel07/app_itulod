import 'package:flutter/material.dart';
import '../../../../core/constants/ilocos_norte.dart';
import '../../../../shared/widgets/booking_stepper.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/last_place.dart';
import '../../../../core/services/route_service.dart';
import '../../../../core/utils/fare_estimator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/vehicle_model.dart';
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

class _BookRideScreenState extends ConsumerState<BookRideScreen>
    with BookingDraftMixin<BookRideScreen> {
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
  /// Not counting the driver. Only vehicles whose range fits are offered
  /// (sql/044; web: renderRideVehicleOptions).
  int _passengers = 1;
  static const _maxPassengers = 40;
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
    final vehicle = _vehicle;
    if (vehicle == null) return null;
    return FareEstimator.estimateRideFare(vehicle, km, _passengers);
  }

  /// Keeps the chosen vehicle when it still fits the group, otherwise picks
  /// the first one that does (null when none fits).
  List<VehicleModel> _fitVehicles(List<VehicleModel> all) {
    final fitting = all.where((v) => v.fitsPassengers(_passengers)).toList();
    // a restored draft names its vehicle by id
    final wantId = _draftVehicleId ?? _vehicle?.id;
    if (fitting.isNotEmpty) _draftVehicleId = null;
    if (wantId == null || !fitting.any((v) => v.id == wantId)) {
      _vehicle = fitting.isNotEmpty ? fitting.first : null;
    } else {
      _vehicle = fitting.firstWhere((v) => v.id == wantId);
    }
    return fitting;
  }

  void _setPassengers(int n) => setState(() => _passengers = n.clamp(1, _maxPassengers));

  String _vehicleLabel(VehicleModel v) {
    final base = v.rideBaseFare ?? v.baseFare;
    final price = v.farePerPassenger
        ? '${Formatters.currency(base)}/person'
        : 'from ${Formatters.currency(base)}';
    return '${v.name} — ${v.passengerRangeText} · $price';
  }

  Widget _passengerStepper() {
    Widget btn(IconData icon, String tip, int delta, bool enabled) => IconButton.outlined(
          tooltip: tip,
          onPressed: enabled ? () => _setPassengers(_passengers + delta) : null,
          icon: Icon(icon, size: 20),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Icon(Icons.groups_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Passengers', style: AppTypography.bodyBold),
                  Text('Not counting the driver', style: AppTypography.caption),
                ],
              ),
            ),
            btn(Icons.remove_rounded, 'Fewer passengers', -1, _passengers > 1),
            SizedBox(
              width: 44,
              child: Text('$_passengers',
                  key: const Key('ride-passengers'),
                  textAlign: TextAlign.center,
                  style: AppTypography.h3),
            ),
            btn(Icons.add_rounded, 'More passengers', 1, _passengers < _maxPassengers),
          ],
        ),
      ),
    );
  }

  // ── Draft: reopened here after Android closed the app (LastPlace) ─────

  @override
  String get draftForm => 'ride';

  String? _draftVehicleId;

  @override
  Map<String, dynamic> draftToJson() => {
        'pickup': _pickupController.text,
        'pickupPoint': LastPlace.pointToJson(_pickupPoint),
        'destination': _destinationController.text,
        'destinationPoint': LastPlace.pointToJson(_destinationPoint),
        'stops': [
          for (var i = 0; i < _stopControllers.length; i++)
            {'address': _stopControllers[i].text, 'point': LastPlace.pointToJson(_stopPoints[i])},
        ],
        'passengers': _passengers,
        'vehicleId': _vehicle?.id,
        'payment': _paymentMethod,
        'scheduledFor': _scheduledFor?.toIso8601String(),
      };

  @override
  void draftFromJson(Map<String, dynamic> d) {
    _pickupController.text = d['pickup'] as String? ?? '';
    _pickupPoint = LastPlace.pointFromJson(d['pickupPoint']);
    _destinationController.text = d['destination'] as String? ?? '';
    _destinationPoint = LastPlace.pointFromJson(d['destinationPoint']);
    for (final s in (d['stops'] as List? ?? const []).take(_maxStops)) {
      if (s is! Map) continue;
      _stopControllers.add(TextEditingController(text: s['address'] as String? ?? ''));
      _stopPoints.add(LastPlace.pointFromJson(s['point']));
    }
    _passengers = ((d['passengers'] as num?)?.toInt() ?? 1).clamp(1, _maxPassengers);
    _draftVehicleId = d['vehicleId'] as String?;
    _paymentMethod = d['payment'] as String? ?? 'cash';
    final at = DateTime.tryParse(d['scheduledFor'] as String? ?? '');
    _scheduledFor = at != null && at.isAfter(DateTime.now()) ? at : null;
  }

  @override
  void afterDraftRestored() => _refreshRoute();

  @override
  void initState() {
    super.initState();
    initDraft();
  }

  @override
  void dispose() {
    disposeDraft();
    _pickupController.dispose();
    _destinationController.dispose();
    for (final c in _stopControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Location picking ──────────────────────────────────────────────────

  /// Pickup and destination share the web-style map ("1 Set Pickup /
  /// 2 Set Drop-off"); a stop gets a one-pin map.
  Future<void> _pickLocation({required bool isPickup, int? stopIndex}) async {
    if (stopIndex != null) {
      final picked = await MapPickerScreen.show(
        context,
        title: 'Set stop ${stopIndex + 1}',
        initialCenter: _stopPoints[stopIndex],
        initialAddress: _nullIfEmpty(_stopControllers[stopIndex].text),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _stopControllers[stopIndex].text = picked.address;
        _stopPoints[stopIndex] = picked.point;
      });
      _refreshRoute();
      return;
    }

    final pickup = _pickupPoint, destination = _destinationPoint;
    final result = await MapPickerScreen.showRoute(
      context,
      pickup: pickup == null ? null : PickedPlace(point: pickup, address: _pickupController.text),
      dropoff: destination == null ? null : PickedPlace(point: destination, address: _destinationController.text),
      startWith: isPickup ? PinMode.pickup : PinMode.dropoff,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.pickup != null) {
        _pickupController.text = result.pickup!.address;
        _pickupPoint = result.pickup!.point;
      }
      if (result.dropoff != null) {
        _destinationController.text = result.dropoff!.address;
        _destinationPoint = result.dropoff!.point;
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
    if (_vehicle == null) return; // the fields were checked by BookingStepper
    if (!checkServiceArea(context, {
      'Pickup': _pickupPoint,
      'Destination': _destinationPoint,
      for (var i = 0; i < _stopPoints.length; i++) 'Stop ${i + 1}': _stopPoints[i],
    })) {
      return;
    }
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
          passengers: _passengers,
          onBooked: finishDraft,
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
    final vehiclesAsync = ref.watch(vehiclesForServiceProvider('ride'));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Book a Ride')),
      body: vehiclesAsync.when(
        loading: () => const SkeletonList(count: 3),
        error: (e, _) => Center(child: Text('Could not load vehicles.\n$e', textAlign: TextAlign.center)),
        data: (allVehicles) {
          final vehicles = _fitVehicles(allVehicles);
          final fare = _fare;
          // Where → Vehicle → Payment here; Confirm is BookingConfirmationScreen.
          return BookingStepper(
            key: ValueKey('ride-steps-$draftGeneration'),
            initialStep: draftStep,
            onStepChanged: onDraftStep,
            fare: fare == null ? '—' : Formatters.currency(fare),
            finishLabel: 'Review Booking',
            onFinish: allVehicles.isEmpty ? null : _submit,
            onChanged: () => setState(() {}),
            steps: [
              BookingStep('Where', [
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
              ]),
              BookingStep('Vehicle', [
                  _passengerStepper(),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<VehicleModel>(
                    // Rebuilt when the group size changes the list.
                    key: ValueKey('ride-vehicle-$_passengers-${vehicles.length}'),
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Vehicle type',
                      prefixIcon: const Icon(Icons.directions_rounded),
                      helperText: vehicles.isEmpty
                          ? null
                          : 'Only vehicles that fit your group are listed.',
                    ),
                    hint: Text(
                        'No vehicle fits $_passengers passenger${_passengers == 1 ? '' : 's'} right now'),
                    validator: (v) => v == null
                        ? 'No vehicle fits $_passengers passenger${_passengers == 1 ? '' : 's'} — change the number'
                        : null,
                    items: vehicles
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(_vehicleLabel(v), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _vehicle = v),
                  ),
                  const SizedBox(height: 12),
                  // Riders with the chosen vehicle within 10 km of the pickup
                  // from step 1 — updates as the vehicle changes.
                  RidersNearYouMap(vehicleName: _vehicle?.name, origin: _pickupPoint),
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
                  _fareBox(),
              ]),
              BookingStep('Payment', [
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
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _fareBox() {
    final km = _distanceKm;
    final fare = _fare;

    final vehicle = _vehicle;

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
          if (fare != null && km != null && vehicle != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.cardBorder),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                FareEstimator.rideFareBreakdown(vehicle, km, _passengers, Formatters.currency),
                key: const Key('ride-fare-breakdown'),
                style: AppTypography.caption.copyWith(color: AppColors.neutral700),
              ),
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
