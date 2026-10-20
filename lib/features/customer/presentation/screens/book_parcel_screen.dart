import 'package:flutter/material.dart';
import '../../../../core/constants/ilocos_norte.dart';
import '../../../../shared/widgets/sticky_action_bar.dart';
import '../../../../shared/widgets/loading_skeleton.dart';
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
import '../../data/customer_repository.dart';
import '../widgets/location_picker_field.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/riders_near_you_map.dart';
import '../widgets/route_preview_map.dart';
import 'map_picker_screen.dart';

const List<String> _parcelSizes = [
  'Small (fits a shoebox)',
  'Medium (fits a backpack)',
  'Large (needs two hands)',
];

class BookParcelScreen extends ConsumerStatefulWidget {
  const BookParcelScreen({super.key});

  @override
  ConsumerState<BookParcelScreen> createState() => _BookParcelScreenState();
}

class _BookParcelScreenState extends ConsumerState<BookParcelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _senderNameController = TextEditingController();
  final _senderPhoneController = TextEditingController();
  final _senderAddressController = TextEditingController();
  final _receiverNameController = TextEditingController();
  final _receiverPhoneController = TextEditingController();
  final _receiverAddressController = TextEditingController();
  final _weightController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _instructionsController = TextEditingController();
  VehicleModel? _vehicle;
  String _parcelSize = _parcelSizes.first;
  String _paymentMethod = 'cash';
  bool _submitting = false;

  bool _isRoundTrip = false;
  final _codAmountController = TextEditingController();

  /// Coordinates behind the two address fields — set only by the map picker.
  LatLng? _senderPoint;
  LatLng? _receiverPoint;

  RouteResult? _route;
  bool _routing = false;
  int _routeToken = 0;

  bool get _hasBothPoints => _senderPoint != null && _receiverPoint != null;

  double? get _distanceKm {
    if (_route != null) return _route!.distanceKm;
    final s = _senderPoint, r = _receiverPoint;
    if (s == null || r == null) return null;
    return FareEstimator.roadDistanceKm(s, r);
  }

  double? get _fare {
    final km = _distanceKm;
    if (km == null || _vehicle == null) return null;
    final effectiveKm = _isRoundTrip ? (km * 2) : km;
    return FareEstimator.estimateFare(_vehicle, effectiveKm);
  }

  @override
  void dispose() {
    for (final c in [
      _senderNameController,
      _senderPhoneController,
      _senderAddressController,
      _receiverNameController,
      _receiverPhoneController,
      _receiverAddressController,
      _weightController,
      _descriptionController,
      _instructionsController,
      _codAmountController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Optional PH mobile number — same rule as the web's isValidPhoneMobile
  /// (09XXXXXXXXX, spaces/dashes allowed, +63 accepted).
  static String? _optionalMobile(String? value) {
    final raw = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (raw.isEmpty) return null;
    final local = raw.startsWith('+63') ? '0${raw.substring(3)}' : raw;
    return RegExp(r'^09\d{9}$').hasMatch(local)
        ? null
        : 'Enter a valid mobile number (09XX XXX XXXX)';
  }

  static String? _personName(String? value, String label) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter the $label name';
    return RegExp(r"^[A-Za-zÀ-ÿñÑ .'-]+$").hasMatch(v)
        ? null
        : '$label name should be letters only';
  }

  static String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value;

  /// Sender and receiver share the web-style map ("1 Set Pickup /
  /// 2 Set Drop-off").
  Future<void> _pickLocation({required bool isSender}) async {
    final s = _senderPoint, r = _receiverPoint;
    final result = await MapPickerScreen.showRoute(
      context,
      pickup: s == null ? null : PickedPlace(point: s, address: _senderAddressController.text),
      dropoff: r == null ? null : PickedPlace(point: r, address: _receiverAddressController.text),
      startWith: isSender ? PinMode.pickup : PinMode.dropoff,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.pickup != null) {
        _senderAddressController.text = result.pickup!.address;
        _senderPoint = result.pickup!.point;
      }
      if (result.dropoff != null) {
        _receiverAddressController.text = result.dropoff!.address;
        _receiverPoint = result.dropoff!.point;
      }
    });
    _refreshRoute();
  }

  Future<void> _refreshRoute() async {
    final s = _senderPoint, r = _receiverPoint;
    final token = ++_routeToken;

    if (s == null || r == null) {
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

    final result = await ref.read(routeServiceProvider).fetchRoute(s, r);
    if (!mounted || token != _routeToken) return;
    setState(() {
      _route = result;
      _routing = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _vehicle == null) return;
    if (!checkServiceArea(context, {'Sender address': _senderPoint, 'Receiver address': _receiverPoint})) return;

    setState(() => _submitting = true);
    try {
      final profile = ref.read(authNotifierProvider).profile!;
      await ref.read(customerRepositoryProvider).createParcelBooking(
            customerId: profile.id,
            vehicle: _vehicle!,
            senderName: _senderNameController.text,
            senderPhone: _senderPhoneController.text,
            senderAddress: _senderAddressController.text,
            receiverName: _receiverNameController.text,
            receiverPhone: _receiverPhoneController.text,
            receiverAddress: _receiverAddressController.text,
            parcelSize: _parcelSize,
            parcelWeight: double.tryParse(_weightController.text),
            parcelDescription: _descriptionController.text,
            instructions: _instructionsController.text,
            distanceKm: _distanceKm,
            paymentMethod: _paymentMethod,
            isRoundTrip: _isRoundTrip,
            codAmount: double.tryParse(_codAmountController.text) ?? 0.0,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_paymentMethod == 'cash'
              ? 'Parcel delivery requested! Pay the rider in cash.'
              : 'Parcel delivery requested! We\'ll ask you to pay once the rider confirms the fare at pickup.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Booking failed: ${e.toString().replaceFirst('Exception: ', '')}'),
              backgroundColor: AppColors.danger),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Send Parcel')),
      bottomNavigationBar: StickyActionBar(
        child: AppButton(
          text: 'Book Parcel Delivery',
          isLoading: _submitting,
          onPressed: (vehiclesAsync.valueOrNull?.isEmpty ?? true) ? null : _submit,
        ),
      ),
      body: vehiclesAsync.when(
        loading: () => const SkeletonList(count: 3),
        error: (e, _) => Center(
            child: Text('Could not load vehicles.\n$e',
                textAlign: TextAlign.center)),
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
                  RidersNearYouMap(vehicleName: _vehicle?.name, origin: _senderPoint),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Sender',
                    children: [
                      TextFormField(
                        controller: _senderNameController,
                        decoration:
                            const InputDecoration(hintText: 'Your name *'),
                        validator: (v) => _personName(v, 'Sender'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _senderPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(hintText: 'Contact number (09XX XXX XXXX)'),
                        validator: _optionalMobile,
                      ),
                      const SizedBox(height: 14),
                      LocationPickerField(
                        controller: _senderAddressController,
                        hint: 'Tap to set the pickup point on the map',
                        isPickup: true,
                        emptyError: 'Set a pickup address',
                        onTap: () => _pickLocation(isSender: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Receiver',
                    children: [
                      TextFormField(
                        controller: _receiverNameController,
                        decoration:
                            const InputDecoration(hintText: 'Receiver name *'),
                        validator: (v) => _personName(v, 'Receiver'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _receiverPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(hintText: 'Contact number (09XX XXX XXXX)'),
                        validator: _optionalMobile,
                      ),
                      const SizedBox(height: 14),
                      LocationPickerField(
                        controller: _receiverAddressController,
                        hint: 'Tap to set the drop-off point on the map',
                        isPickup: false,
                        emptyError: 'Set a drop-off address',
                        onTap: () => _pickLocation(isSender: false),
                      ),
                    ],
                  ),
                  if (_hasBothPoints) ...[
                    const SizedBox(height: 16),
                    RoutePreviewMap(
                      pickup: _senderPoint!,
                      destination: _receiverPoint!,
                      routePoints: _route?.points,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Parcel details', style: AppTypography.bodyBold),
                          const SizedBox(height: 10),
                          RadioGroup<String>(
                            groupValue: _parcelSize,
                            onChanged: (v) => setState(
                                () => _parcelSize = v ?? _parcelSizes.first),
                            child: Column(
                              children: [
                                ..._parcelSizes.map((size) =>
                                    RadioListTile<String>(
                                      value: size,
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      activeColor: AppColors.primary,
                                      title: Text(size,
                                          style: AppTypography.bodyMedium
                                              .copyWith(fontSize: 14)),
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                hintText: 'Weight in kg (optional)'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                                hintText: 'What is inside? (optional)'),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _instructionsController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                hintText: 'Special instructions (optional)'),
                          ),
                          const SizedBox(height: 14),
                          const Divider(),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Round Trip'),
                            subtitle: const Text('Rider will return to pickup address'),
                            value: _isRoundTrip,
                            onChanged: (v) => setState(() => _isRoundTrip = v),
                            activeThumbColor: AppColors.primary,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _codAmountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Collect COD Amount (₱)',
                              hintText: 'Enter amount to collect from receiver',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<VehicleModel>(
                    initialValue: _vehicle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle type *',
                      prefixIcon: Icon(Icons.directions_rounded),
                    ),
                    items: vehicles
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text(v.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _vehicle = v),
                  ),
                  const SizedBox(height: 16),
                  PaymentMethodSelector(
                    value: _paymentMethod,
                    onChanged: (v) => setState(() => _paymentMethod = v),
                    onlineNote: 'You\'ll be asked to pay once the rider confirms the fare at pickup.',
                  ),
                  const SizedBox(height: 16),
                  _fareBox(),
                  const SizedBox(height: 16),
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
    final total = fare;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESTIMATED DISTANCE', style: AppTypography.overline),
                    Text(Formatters.distance(km), style: AppTypography.h3),
                  ],
                ),
              ),
              Container(
                  width: 1,
                  height: 36,
                  color: AppColors.success.withValues(alpha: 0.25)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('ESTIMATED FARE', style: AppTypography.overline),
                    Text(total == null ? '—' : Formatters.currency(total),
                        style: AppTypography.h3
                            .copyWith(color: AppColors.success)),
                  ],
                ),
              ),
            ],
          ),
          if (fare != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.success.withValues(alpha: 0.25)),
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

  String get _sourceLabel {
    if (!_hasBothPoints) {
      return 'Set both locations on the map to see the fare.';
    }
    if (_routing) return 'Measuring the road route…';
    if (_route != null) {
      final minutes = _route!.duration.inMinutes;
      final eta = minutes > 0 ? ' • about $minutes min' : '';
      return 'Measured along roads$eta';
    }
    return 'Straight-line estimate — routing service unavailable';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.bodyBold),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
