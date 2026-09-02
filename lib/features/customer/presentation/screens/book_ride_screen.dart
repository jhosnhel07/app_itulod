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
import '../widgets/route_preview_map.dart';
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

  /// Road route from OSRM. Null means it hasn't answered (or failed), in which
  /// case the straight-line estimate stands in.
  RouteResult? _route;
  bool _routing = false;
  int _routeToken = 0;

  VehicleModel? _vehicle;
  String _paymentMethod = 'cash';

  bool get _hasBothPoints => _pickupPoint != null && _destinationPoint != null;

  /// Kilometres for the fare, best source first: real road distance, then
  /// straight line scaled by the road factor. Null until both pins are down —
  /// showing a number before then would be inventing one.
  double? get _distanceKm {
    if (_route != null) return _route!.distanceKm;
    final pickup = _pickupPoint;
    final destination = _destinationPoint;
    if (pickup == null || destination == null) return null;
    return FareEstimator.roadDistanceKm(pickup, destination);
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
    super.dispose();
  }

  // ── Location picking ──────────────────────────────────────────────────

  Future<void> _pickLocation({required bool isPickup}) async {
    final picked = await MapPickerScreen.show(
      context,
      title: isPickup ? 'Set pickup location' : 'Set destination',
      pinColor: isPickup ? AppColors.success : AppColors.danger,
      // Opening on the last known point saves the customer a pan; the
      // destination picker starts from the pickup when it has nothing else.
      initialCenter: isPickup ? _pickupPoint : (_destinationPoint ?? _pickupPoint),
      initialAddress: isPickup
          ? _nullIfEmpty(_pickupController.text)
          : _nullIfEmpty(_destinationController.text),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isPickup) {
        _pickupController.text = picked.address;
        _pickupPoint = picked.point;
      } else {
        _destinationController.text = picked.address;
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

    final result = await ref.read(routeServiceProvider).fetchRoute(pickup, destination);
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingConfirmationScreen(
          vehicle: _vehicle!,
          pickupAddress: _pickupController.text,
          destinationAddress: _destinationController.text,
          distanceKm: _distanceKm,
          fare: fare,
          paymentMethod: _paymentMethod,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _locationField(
                            controller: _pickupController,
                            hint: 'Tap to set pickup on the map',
                            icon: Icons.circle,
                            iconColor: AppColors.success,
                            iconSize: 12,
                            emptyError: 'Set a pickup location',
                            isPickup: true,
                          ),
                          const SizedBox(height: 14),
                          _locationField(
                            controller: _destinationController,
                            hint: 'Tap to set destination on the map',
                            icon: Icons.location_on_outlined,
                            iconColor: AppColors.danger,
                            iconSize: 20,
                            emptyError: 'Set a destination',
                            isPickup: false,
                          ),
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
                                ...['cash', 'gcash'].map((method) => RadioListTile<String>(
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

  /// Read-only field that opens the map picker on tap.
  ///
  /// Still a [TextFormField] so the existing form validation, controller, and
  /// error display keep working — only typing is replaced by the picker.
  Widget _locationField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required double iconSize,
    required String emptyError,
    required bool isPickup,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      maxLines: 2,
      minLines: 1,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onTap: () => _pickLocation(isPickup: isPickup),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor, size: iconSize),
        suffixIcon: Icon(Icons.map_outlined, size: 20, color: AppColors.iconMuted),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? emptyError : null,
    );
  }

  Widget _fareBox() {
    final km = _distanceKm;
    final fare = _fare;

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
          const SizedBox(height: 8),
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
      case 'card':
        return 'Card';
      default:
        return 'Cash on arrival';
    }
  }
}
